import AppKit
import Combine

struct Track: Equatable {
    enum Source {
        case spotifast, spotify, appleMusic

        /// What the player is called in sentences shown to the listener.
        var name: String {
            switch self {
            case .spotifast: "Spotifast"
            case .spotify: "Spotify"
            case .appleMusic: "Music"
            }
        }

        var bundleID: String {
            switch self {
            case .spotifast: "rocks.spotifast.Spotifast"
            case .spotify: "com.spotify.client"
            case .appleMusic: "com.apple.Music"
            }
        }

        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    var title: String
    var artist: String
    var album: String
    var source: Source
    var artURL: URL?
    var spotifyID: String?
    var duration: TimeInterval?

    /// Whether this is the same song as `other`, however much else is known about either.
    func isSameSong(as other: Track) -> Bool {
        title == other.title && artist == other.artist && album == other.album && source == other.source
    }
}

/// Follows and controls whichever supported player is active.
///
/// - Spotify and Apple Music broadcast playback notifications system-wide. Those say nothing
///   of volume (or, for Apple Music, position) and only arrive when something changes, so the
///   two are also asked outright over AppleScript: at launch, after each notification, and
///   every few seconds while they play. macOS asks the user to allow that once per player.
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
    /// A player macOS has not allowed Spindle to control. Only the user can change that, in System Settings.
    @Published private(set) var blocked: Track.Source?
    /// Short messages for the listener, such as why the volume would not change.
    let notices = PassthroughSubject<String, Never>()

    private var positionBase: TimeInterval = 0
    private var positionStamp = Date()
    private var artworkAlbum: String?
    private var artworkTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var syncTimer: Timer?
    /// Polls that were already in flight when a command was sent would undo its optimistic update.
    private var ignorePollsUntil = Date.distantPast
    private let commands = DispatchQueue(label: "spindle.player.commands")
    private let polling = DispatchQueue(label: "spindle.player.polling")
    private let syncing = DispatchQueue(label: "spindle.player.syncing")

    /// The Spotify Connect device the music is coming out of, when the player says.
    private var device = ""
    /// What the player reported before the user began moving the fader.
    private var volumeBeforeChange: Double?
    /// Until then the player may not have caught up, so what it reports is left alone.
    private var volumeSettlesAt = Date.distantPast
    private var volumeInFlight = false
    private var volumeQueued: Int?
    /// A device that ignored a volume change: asking again soon would only make the fader jump back.
    private var deaf: (device: String, until: Date)?
    private var lastNotice: (text: String, at: Date)?

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
    }

    /// Begins asking the players what they are doing. Kept apart from `init` because the first
    /// question may make macOS ask the user for permission, which shouldn't happen before the
    /// app has decided to stay open.
    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollSpotifast()
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying, let source = self.track?.source else { return }
            self.sync(source)
        }
        pollSpotifast()
        sync(.spotify)
        sync(.appleMusic)
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
        if let next {
            if let current = track, current.isSameSong(as: next) {
                // The same song heard about again, perhaps with more detail than before.
                var fuller = current
                fuller.duration = next.duration ?? current.duration
                fuller.artURL = current.artURL ?? next.artURL
                fuller.spotifyID = current.spotifyID ?? next.spotifyID
                if fuller != current { track = fuller }
            } else {
                track = next
                changed = true
                loadArtwork(for: next)
            }
        }
        setPlaying(playing)
        if let position = position ?? (changed ? 0 : nil) {
            positionBase = position
            positionStamp = Date()
        }
        if let volume { reconcile(volume: volume) }
    }

    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        positionBase = position
        positionStamp = Date()
        isPlaying = playing
    }

    private func notify(_ text: String) {
        // Dragging the fader asks many times a second; saying so once is enough.
        if let lastNotice, lastNotice.text == text, Date().timeIntervalSince(lastNotice.at) < 5 { return }
        lastNotice = (text, Date())
        notices.send(text)
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

    private enum Command {
        case playPause, play, pause, next, previous
        case seek(TimeInterval)
        case volume(Int)
    }

    private var activeSource: Track.Source? {
        track?.source ?? (Track.Source.spotifast.isRunning ? .spotifast : nil)
    }

    /// `completion` runs on the main queue once the player has been told, or straight away
    /// if there is no player to tell.
    private func send(_ command: Command, then completion: (() -> Void)? = nil) {
        guard let source = activeSource, let (executable, arguments) = invocation(of: command, for: source) else {
            completion?()
            return
        }
        if case .volume = command {} else { ignorePollsUntil = Date().addingTimeInterval(0.8) }
        commands.async { [weak self] in
            let result = Self.run(executable, arguments)
            DispatchQueue.main.async {
                self?.noteAccess(to: source, after: result)
                completion?()
            }
        }
    }

    /// The program to run, and what to pass it, to give `source` a command.
    private func invocation(of command: Command, for source: Track.Source) -> (URL, [String])? {
        switch source {
        case .spotifast:
            guard let binary = spotifastBinary else { return nil }
            let arguments = switch command {
            case .playPause: ["play-pause"]
            case .play: ["play"]
            case .pause: ["pause"]
            case .next: ["next"]
            case .previous: ["previous"]
            case .seek(let seconds): ["seek-to", String(Int(seconds))]
            case .volume(let percent): ["volume", String(percent)]
            }
            return (binary, arguments)
        case .spotify, .appleMusic:
            let verb = switch command {
            case .playPause: "playpause"
            case .play: "play"
            case .pause: "pause"
            case .next: "next track"
            case .previous: "previous track"
            case .seek(let seconds): "set player position to \(Int(seconds))"
            case .volume(let percent): "set sound volume to \(percent)"
            }
            return (Self.osascript, ["-e", "tell application id \"\(source.bundleID)\" to \(verb)"])
        }
    }

    private static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    private static func run(_ executable: URL, _ arguments: [String]) -> (output: String?, complaint: String) {
        let process = Process()
        let (output, complaint) = (Pipe(), Pipe())
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = complaint
        guard (try? process.run()) != nil else { return (nil, "") }
        let said = output.fileHandleForReading.readDataToEndOfFile()
        let complained = String(data: complaint.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return (process.terminationStatus == 0 ? String(data: said, encoding: .utf8) : nil, complained)
    }

    /// AppleScript fails with error -1743 when the user has not allowed Spindle to control a player.
    private func noteAccess(to source: Track.Source, after result: (output: String?, complaint: String)) {
        guard source != .spotifast else { return }
        if result.complaint.contains("-1743") {
            if blocked != source {
                blocked = source
                notify("Spindle isn't allowed to control \(source.name) yet. See its menu.")
            }
        } else if result.output != nil, blocked == source {
            blocked = nil
        }
    }

    // MARK: Volume

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        guard Int(clamped) != Int(volume) else { return }
        if let deaf, deaf.device == device, Date() < deaf.until {
            return notify(volumeRefusal)
        }
        if volumeBeforeChange == nil { volumeBeforeChange = volume }
        volume = clamped
        volumeSettlesAt = Date().addingTimeInterval(2)
        sendVolume(Int(clamped))
    }

    /// A drag asks for a new volume many times a second. Only one request is out at a time,
    /// and of those that pile up behind it only the latest is passed on.
    private func sendVolume(_ percent: Int) {
        guard !volumeInFlight else { return volumeQueued = percent }
        guard let source = activeSource else { return }
        volumeInFlight = true
        send(.volume(percent)) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard let self else { return }
                self.volumeInFlight = false
                if let queued = self.volumeQueued {
                    self.volumeQueued = nil
                    if queued != percent { return self.sendVolume(queued) }
                }
                // Spotify and Apple Music aren't polled, so check what came of it once things settle.
                if source != .spotifast {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { self.sync(source) }
                }
            }
        }
    }

    private var volumeRefusal: String {
        device.isEmpty ? "The volume can't be changed from here right now"
            : "Playing on \(device): change the volume there"
    }

    /// Takes the volume the player reports, once it has had time to act on what it was asked.
    private func reconcile(volume reported: Double) {
        guard Date() >= volumeSettlesAt else { return }
        if let before = volumeBeforeChange {
            volumeBeforeChange = nil
            // Still exactly what it was before the fader moved: whatever is playing the music
            // ignored the change, as phones and some speakers do.
            if abs(reported - before) < 1.5, abs(volume - before) > 2 {
                if !device.isEmpty { deaf = (device, Date().addingTimeInterval(120)) }
                notify(volumeRefusal)
            }
        }
        if reported != volume { volume = reported }
    }

    // MARK: Spotifast

    private var spotifastBinary: URL? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Track.Source.spotifast.bundleID).first?.executableURL
    }

    private func pollSpotifast() {
        guard let binary = spotifastBinary else {
            if track?.source == .spotifast { setPlaying(false) }
            return
        }
        polling.async { [weak self] in
            let output = Self.run(binary, ["now-playing", "--raw"]).output
            DispatchQueue.main.async { self?.handleSpotifast(output) }
        }
    }

    /// Fields: state, title, artists, album, position_ms, duration_ms, volume, shuffle, repeat, art_url, saved, device
    private func handleSpotifast(_ output: String?) {
        guard Date() > ignorePollsUntil, let line = output?.split(separator: "\n").first else { return }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 10, !fields[1].isEmpty else { return }
        device = fields.count > 11 ? fields[11] : ""
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
            let milliseconds = (info["Duration"] ?? info["Total Time"]) as? Double
            next = Track(
                title: title,
                artist: info["Artist"] as? String ?? "",
                album: info["Album"] as? String ?? "",
                source: source,
                spotifyID: (info["Track ID"] as? String).flatMap(Self.spotifyID),
                duration: milliseconds.map { $0 / 1000 }
            )
        }
        apply(track: next, playing: playing, position: info["Playback Position"] as? Double, volume: nil, from: source)
        sync(source)
    }

    private static func spotifyID(from uri: String) -> String? {
        uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : nil
    }

    /// Asks a running Spotify or Apple Music what it is doing. It is never asked while it
    /// isn't running, because AppleScript would launch it to answer.
    private func sync(_ source: Track.Source) {
        guard source != .spotifast, source.isRunning else { return }
        // Spotify gives durations in milliseconds and knows where its covers are; Music does neither.
        let extras = source == .spotify ? " & tab & (id of t) & tab & (artwork url of t)" : ""
        let script = [
            "with timeout of 5 seconds",
            "tell application id \"\(source.bundleID)\"",
            "set s to player state as text",
            "if s is \"stopped\" then return s",
            "set t to current track",
            "return s & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (duration of t)"
                + " & tab & (player position) & tab & (sound volume)" + extras,
            "end tell",
            "end timeout",
        ]
        syncing.async { [weak self] in
            let result = Self.run(Self.osascript, script.flatMap { ["-e", $0] })
            DispatchQueue.main.async {
                self?.noteAccess(to: source, after: result)
                self?.handleSync(result.output, from: source)
            }
        }
    }

    /// Fields: state, title, artist, album, duration, position, volume, and from Spotify also track URI and cover address.
    private func handleSync(_ reply: String?, from source: Track.Source) {
        guard let reply else { return }
        let fields = reply.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        guard fields.count >= 7, !fields[1].isEmpty else {
            if track?.source == source { setPlaying(false) }
            return
        }
        // AppleScript writes numbers the way the user's region does, which may be with a comma.
        func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
        var next = Track(
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            source: source,
            duration: number(fields[4]).map { source == .spotify ? $0 / 1000 : $0 }
        )
        if fields.count >= 9 {
            next.spotifyID = Self.spotifyID(from: fields[7])
            next.artURL = URL(string: fields[8])
        }
        apply(track: next, playing: fields[0] == "playing", position: number(fields[5]), volume: number(fields[6]), from: source)
    }

    // MARK: Artwork

    private func loadArtwork(for track: Track) {
        if artwork != nil, artworkAlbum == track.album, !track.album.isEmpty { return }
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            let image = await Artwork.image(for: track)
            guard let self, !Task.isCancelled, self.track?.isSameSong(as: track) == true else { return }
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
