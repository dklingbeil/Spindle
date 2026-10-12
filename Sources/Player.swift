import AppKit

struct Track: Equatable {
    enum Source { case spotifast, spotify, appleMusic }

    var title: String
    var artist: String
    var album: String
    var source: Source
    var artURL: URL?
    var spotifyID: String?
    var duration: TimeInterval?
}

/// Follows and controls whichever supported player is active.
///
/// - Spotify and Apple Music broadcast playback notifications system-wide, so following
///   them needs no login or permission; nothing arrives until they next change state.
///   Controlling them goes through AppleScript, which macOS asks the user to allow once.
/// - Spotifast has no notifications but ships a command-line remote, which is polled
///   for state and used for control.
final class Player: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    /// Covers of previously played albums, newest first.
    @Published private(set) var history: [NSImage] = []
    /// 0...100
    @Published private(set) var volume = 70.0

    private static let spotifastBundleID = "rocks.spotifast.Spotifast"

    private var positionBase: TimeInterval = 0
    private var positionStamp = Date()
    private var artworkAlbum: String?
    private var artworkTask: Task<Void, Never>?
    private var pollTimer: Timer?
    /// Polls that were already in flight when a command was sent would undo its optimistic update.
    private var ignorePollsUntil = Date.distantPast
    private let commands = DispatchQueue(label: "spindle.player.commands")
    private let polling = DispatchQueue(label: "spindle.player.polling")

    init() {
        let center = DistributedNotificationCenter.default()
        let sources: [(String, Track.Source)] = [
            ("com.spotify.client.PlaybackStateChanged", .spotify),
            ("com.apple.Music.playerInfo", .appleMusic),
        ]
        for (name, source) in sources {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                self?.handleNotification(note.userInfo, from: source)
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollSpotifast()
        }
        pollSpotifast()
    }

    // MARK: State

    var position: TimeInterval {
        positionBase + (isPlaying ? Date().timeIntervalSince(positionStamp) : 0)
    }

    /// How far through the track playback is, 0...1, when the duration is known.
    var progress: Double? {
        guard let duration = track?.duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    private func apply(track next: Track?, playing: Bool, position: TimeInterval?, volume: Double?, from source: Track.Source) {
        // A paused player shouldn't take over from, or stop, a different one.
        if !playing, let track, track.source != source { return }

        var changed = false
        if let next, next != track {
            track = next
            changed = true
            loadArtwork(for: next)
        }
        setPlaying(playing)
        if let position = position ?? (changed ? 0 : nil) {
            positionBase = position
            positionStamp = Date()
        }
        if let volume, volume != self.volume { self.volume = volume }
    }

    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        positionBase = position
        positionStamp = Date()
        isPlaying = playing
    }

    // MARK: Controls

    func togglePlayPause() {
        send(.playPause)
        setPlaying(!isPlaying)
    }

    func pause() {
        send(.pause)
        setPlaying(false)
    }

    func next() { send(.next) }

    func previous() { send(.previous) }

    /// Jumps to a point in the track (0...1) and starts playback if it was paused.
    func seek(toFraction fraction: Double) {
        guard let duration = track?.duration else { return }
        let seconds = min(max(fraction, 0), 1) * duration
        send(.seek(seconds))
        if !isPlaying { send(.play) }
        setPlaying(true)
        positionBase = seconds
        positionStamp = Date()
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        guard Int(clamped) != Int(volume) else { return }
        volume = clamped
        send(.volume(Int(clamped)))
    }

    private enum Command {
        case playPause, play, pause, next, previous
        case seek(TimeInterval)
        case volume(Int)
    }

    private func send(_ command: Command) {
        let source = track?.source ?? (spotifastBinary != nil ? .spotifast : nil)
        guard let source else { return }
        ignorePollsUntil = Date().addingTimeInterval(0.8)

        let executable: URL
        let arguments: [String]
        switch source {
        case .spotifast:
            guard let binary = spotifastBinary else { return }
            executable = binary
            arguments = switch command {
            case .playPause: ["play-pause"]
            case .play: ["play"]
            case .pause: ["pause"]
            case .next: ["next"]
            case .previous: ["previous"]
            case .seek(let seconds): ["seek-to", String(Int(seconds))]
            case .volume(let percent): ["volume", String(percent)]
            }
        case .spotify, .appleMusic:
            let app = source == .spotify ? "Spotify" : "Music"
            let verb = switch command {
            case .playPause: "playpause"
            case .play: "play"
            case .pause: "pause"
            case .next: "next track"
            case .previous: "previous track"
            case .seek(let seconds): "set player position to \(seconds)"
            case .volume(let percent): "set sound volume to \(percent)"
            }
            executable = URL(fileURLWithPath: "/usr/bin/osascript")
            arguments = ["-e", "tell application \"\(app)\" to \(verb)"]
        }
        commands.async { _ = Self.run(executable, arguments) }
    }

    private static func run(_ executable: URL, _ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }

    // MARK: Spotifast

    private var spotifastBinary: URL? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifastBundleID).first?.executableURL
    }

    private func pollSpotifast() {
        guard let binary = spotifastBinary else {
            if track?.source == .spotifast { setPlaying(false) }
            return
        }
        polling.async { [weak self] in
            let output = Self.run(binary, ["now-playing", "--raw"])
            DispatchQueue.main.async { self?.handleSpotifast(output) }
        }
    }

    /// Fields: state, title, artists, album, position_ms, duration_ms, volume, shuffle, repeat, art_url, saved, device
    private func handleSpotifast(_ output: String?) {
        guard Date() > ignorePollsUntil, let line = output?.split(separator: "\n").first else { return }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 10, !fields[1].isEmpty else { return }
        let next = Track(
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            source: .spotifast,
            artURL: URL(string: fields[9]),
            duration: Double(fields[5]).map { $0 / 1000 }
        )
        apply(
            track: next,
            playing: fields[0] == "playing",
            position: Double(fields[4]).map { $0 / 1000 },
            volume: Double(fields[6]),
            from: .spotifast
        )
    }

    // MARK: Spotify and Apple Music

    private func handleNotification(_ info: [AnyHashable: Any]?, from source: Track.Source) {
        guard let info else { return }
        let playing = info["Player State"] as? String == "Playing"
        var next: Track?
        if playing, let title = info["Name"] as? String {
            let spotifyID = (info["Track ID"] as? String).flatMap { id in
                id.hasPrefix("spotify:track:") ? String(id.dropFirst("spotify:track:".count)) : nil
            }
            let milliseconds = (info["Duration"] ?? info["Total Time"]) as? Double
            next = Track(
                title: title,
                artist: info["Artist"] as? String ?? "",
                album: info["Album"] as? String ?? "",
                source: source,
                spotifyID: spotifyID,
                duration: milliseconds.map { $0 / 1000 }
            )
        }
        apply(track: next, playing: playing, position: info["Playback Position"] as? Double, volume: nil, from: source)
    }

    // MARK: Artwork

    private func loadArtwork(for track: Track) {
        if artwork != nil, artworkAlbum == track.album, !track.album.isEmpty { return }
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            let image = await Artwork.image(for: track)
            guard let self, !Task.isCancelled, self.track == track else { return }
            if let previous = self.artwork {
                self.history = Array(([previous] + self.history).prefix(3))
            }
            self.artwork = image
            self.artworkAlbum = track.album
        }
    }
}

/// Cover lookups that need no account: the player's own URL when it gives one,
/// Spotify's public oEmbed endpoint, then the iTunes Search API.
enum Artwork {
    static func image(for track: Track) async -> NSImage? {
        if let url = track.artURL, let image = await image(from: url) { return image }
        if let id = track.spotifyID, let image = await spotifyCover(trackID: id) { return image }
        return await iTunesCover(for: track)
    }

    private static func spotifyCover(trackID: String) async -> NSImage? {
        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/track/\(trackID)")]
        guard let json = await json(from: components.url),
              let thumbnail = json["thumbnail_url"] as? String else { return nil }
        return await image(from: URL(string: thumbnail))
    }

    private static func iTunesCover(for track: Track) async -> NSImage? {
        let byAlbum = !track.album.isEmpty
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(byAlbum ? track.album : track.title)"),
            URLQueryItem(name: "entity", value: byAlbum ? "album" : "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let json = await json(from: components.url),
              let result = (json["results"] as? [[String: Any]])?.first,
              let small = result["artworkUrl100"] as? String else { return nil }
        return await image(from: URL(string: small.replacingOccurrences(of: "100x100", with: "600x600")))
    }

    private static func json(from url: URL?) async -> [String: Any]? {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func image(from url: URL?) async -> NSImage? {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }
}
