import SwiftUI

/// The introduction shown on first launch. Spindle has no window of its own and no Dock
/// icon, so this is where a new user learns where it went and how to work it.
struct WelcomeView: View {
    @ObservedObject var loginItem: LoginItem
    let done: () -> Void

    /// macOS's "Click wallpaper to reveal desktop" is set to Always unless the user has
    /// changed it, and then a click on the turntable also sweeps every window aside.
    private let clicksRevealDesktop =
        UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "EnableStandardClickToShowDesktop") as? Bool ?? true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Spindle").font(.title.bold())
                    Text("A turntable on your desktop that plays along with your music.")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            point("record.circle", "It lives on your desktop",
                  "Spindle sits behind your windows and icons. Its settings are under this record icon in the menu bar, at the top right of your screen.")
            point("play.circle", "Play something",
                  "Start a song in Spotify or Apple Music. Its cover appears beside the deck and the desk takes on its colours.")
            point("hand.tap", "The turntable is the remote",
                  "Click the record to play or pause. Drag the tonearm to move through the song. Click the cover for the next song, and the pile of sleeves for the one before. Scroll over the deck to change the volume.")
            point("checkmark.shield", "macOS will ask once",
                  "The first time, macOS asks whether Spindle may control your music app. Choose Allow, or the turntable can only watch.")
            if clicksRevealDesktop {
                point("macwindow.on.rectangle", "If your windows slide away when you click",
                      "macOS is set to show the desktop whenever the wallpaper is clicked. In Desktop & Dock settings, change “Click wallpaper to reveal desktop” to “Only in Stage Manager”.") {
                    Button("Open Desktop & Dock Settings…") { NSWorkspace.shared.open(SystemSettings.desktopAndDock) }
                }
            }
            Divider()
            HStack {
                Toggle("Open Spindle when I log in", isOn: Binding(get: { loginItem.isOn }, set: loginItem.set))
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        point(symbol, title, detail) { EmptyView() }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String,
                       @ViewBuilder extra: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
    }
}
