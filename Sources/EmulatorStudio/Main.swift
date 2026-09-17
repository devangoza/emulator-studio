import AppKit

/// Entry point for the Emulator Studio panel app.
/// The entire UI lives in a floating `NSPanel` created by `AppDelegate`.
///
/// Pass `--render [path]` to render the panel to a PNG and exit (used for previews).
@main
enum EmulatorStudioApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared

        if PreviewRenderer.isRequested {
            application.setActivationPolicy(.accessory)
            PreviewRenderer.start()
            application.run()
            return
        }

        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
