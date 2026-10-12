import Combine
import ServiceManagement
import SwiftUI

@main
struct SpindleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Spindle", systemImage: "record.circle") {
            MenuContent(prefs: delegate.prefs, player: delegate.player, toggleWindow: delegate.toggleWindow)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Preferences()
    let player = Player()

    private var window: NSWindow!
    private var sceneView: SceneView!
    private var cancellables = Set<AnyCancellable>()
    /// Whether the desktop press in progress began on part of the turntable.
    private var trackingDesktopPress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        sceneView = SceneView(prefs: prefs, player: player)
        sceneView.wantsLayer = true

        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = sceneView

        // Each fires once immediately, which also performs the initial layout.
        Publishers.CombineLatest3(prefs.$display, prefs.$size, prefs.$floating)
            .sink { [weak self] display, size, floating in
                self?.arrange(display: display, size: size.dimensions, floating: floating)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.arrange(display: self.prefs.display, size: self.prefs.size.dimensions, floating: self.prefs.floating)
            }
            .store(in: &cancellables)

        NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        ) { [weak self] event in
            self?.handleDesktop(event)
        }
        window.orderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func toggleWindow() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFront(nil)
        }
    }

    private func arrange(display: DisplayMode, size: CGSize, floating: Bool) {
        guard let screen = NSScreen.screens.first else { return }
        switch display {
        case .wallpaper:
            // Above the system wallpaper, below the desktop icons.
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.setFrame(screen.frame, display: true)
            sceneView.layer?.cornerRadius = 0
            sceneView.captionInset = screen.visibleFrame.minY - screen.frame.minY + 16
        case .window:
            window.level = floating ? .floating : .normal
            window.collectionBehavior = [.canJoinAllSpaces]
            window.ignoresMouseEvents = false
            let visible = screen.visibleFrame
            let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            sceneView.layer?.cornerRadius = 14
            sceneView.layer?.masksToBounds = true
            sceneView.captionInset = 14
        }
    }

    // MARK: Desktop clicks

    /// In wallpaper mode the scene can't be clicked directly, so clicks that reach the bare
    /// desktop are observed here and passed on. Finder still receives them as well.
    private func handleDesktop(_ event: NSEvent) {
        guard prefs.display == .wallpaper, window.isVisible else { return }
        let screenPoint = NSEvent.mouseLocation
        let point = sceneView.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        switch event.type {
        case .leftMouseDown:
            trackingDesktopPress = Self.desktopIsExposed(at: screenPoint) && sceneView.pointerDown(at: point)
        case .leftMouseDragged:
            if trackingDesktopPress { sceneView.pointerDragged(to: point) }
        case .leftMouseUp:
            if trackingDesktopPress { sceneView.pointerUp(at: point) }
            trackingDesktopPress = false
        case .scrollWheel:
            if Self.desktopIsExposed(at: screenPoint) {
                sceneView.scrolled(at: point, deltaY: event.scrollingDeltaY)
            }
        default:
            break
        }
    }

    /// True when no visible window of any app covers this point of the desktop.
    private static func desktopIsExposed(at screenPoint: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        // Window bounds are measured from the top-left of the primary display.
        let point = CGPoint(x: screenPoint.x, y: primary.frame.maxY - screenPoint.y)
        return !windows.contains { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.contains(point)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var player: Player
    let toggleWindow: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if let track = player.track {
            Text("\(track.title) — \(track.artist)")
        } else {
            Text("Play a track in Spotify, Spotifast or Apple Music")
        }
        Button(player.isPlaying ? "Pause" : "Play", action: player.togglePlayPause)
        Button("Next Track", action: player.next)
        Button("Previous Track", action: player.previous)
        Divider()
        Button("Show / Hide Turntable", action: toggleWindow)
        Picker("Display", selection: $prefs.display) {
            ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
        }
        Picker("Scene", selection: $prefs.theme) {
            ForEach(SceneTheme.allCases) { Text($0.title).tag($0) }
        }
        if prefs.display == .window {
            Picker("Size", selection: $prefs.size) {
                ForEach(SceneSize.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Float Above Windows", isOn: $prefs.floating)
        }
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = enabled
                } catch {
                    NSLog("Launch at login failed: \(error.localizedDescription)")
                }
            }
        ))
        Divider()
        Button("Quit Spindle") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
