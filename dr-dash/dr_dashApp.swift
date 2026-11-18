import AppKit
import SwiftData
import SwiftUI

/// Sets the ignore-state default before AppKit restores a window. A saved window with no identifier
/// comes back as nothing, and SwiftUI then does not open a new one.
@main
enum ClinicMain {
    static func main() {
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
        dr_dashApp.main()
    }
}

struct dr_dashApp: App {
    @NSApplicationDelegateAdaptor(ClinicAppDelegate.self) private var appDelegate
    @State private var library = ClinicLibrary()
    @AppStorage(ClinicAppearance.storageKey) private var appearance: ClinicAppearance = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .modelContainer(library.container)
                .frame(minWidth: 1100, minHeight: 720)
                .clinicPreferredAppearance(appearance)
        }
        .defaultSize(width: 1440, height: 900)
        .defaultLaunchBehavior(.presented)

        Settings {
            ClinicSettingsView()
                .environment(library)
                .clinicPreferredAppearance(appearance)
        }
    }
}

extension View {
    /// Sheets and the settings window follow the same stored choice. Match System passes `nil`.
    func clinicPreferredAppearance(_ appearance: ClinicAppearance) -> some View {
        preferredColorScheme(appearance.colorScheme)
            .background(ClinicWindowAppearanceSetter(appearance: appearance))
    }
}

/// Writes the stored choice onto the AppKit window so adaptive clinic colors resolve with it.
private struct ClinicWindowAppearanceSetter: NSViewRepresentable {
    var appearance: ClinicAppearance

    func makeNSView(context: Context) -> NSView {
        ClinicAppearanceView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let next = appearance.nsAppearance
        apply(next, to: nsView)
        if nsView.window == nil {
            DispatchQueue.main.async {
                apply(next, to: nsView)
            }
        }
    }

    private func apply(_ next: NSAppearance?, to view: NSView) {
        guard let window = view.window else { return }
        if window.appearance?.name != next?.name {
            window.appearance = next
        }
    }
}

private final class ClinicAppearanceView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Brings the clinic window forward at the designed size, with the traffic lights over the content.
final class ClinicAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if self.clinicWindow == nil {
                self.openClinicWindow()
            }
            self.styleClinicWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.styleClinicWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { styleClinicWindow() }
        return true
    }

    func application(_ application: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    private func openClinicWindow() {
        guard let item = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "New Window"),
              let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private var clinicWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.frame.height > 100 }
    }

    private func styleClinicWindow() {
        guard let window = clinicWindow else { return }
        if window.frame.width < 1100 || window.frame.height < 700 {
            window.setContentSize(NSSize(width: 1440, height: 900))
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.appearance = ClinicAppearance.current.nsAppearance
        window.makeKeyAndOrderFront(nil)
    }
}
