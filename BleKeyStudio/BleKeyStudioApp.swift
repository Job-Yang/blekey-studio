import AppKit
import BleKeyStudioFeature

@main
enum BleKeyStudioMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    coordinator = AppCoordinator()
    coordinator?.start()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    coordinator?.shouldTerminate() == false ? .terminateCancel : .terminateNow
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}
