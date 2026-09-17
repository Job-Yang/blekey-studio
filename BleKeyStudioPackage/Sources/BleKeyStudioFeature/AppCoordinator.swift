import AppKit

public final class AppCoordinator: NSObject, NSWindowDelegate {
  private var windowController: NSWindowController?

  public override init() {
    super.init()
  }

  init(windowController: NSWindowController) {
    self.windowController = windowController
    super.init()
    windowController.window?.delegate = self
  }

  public func start() {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    installMainMenu()

    let workspace = WorkspaceViewController()
    workspace.preferredContentSize = NSSize(width: 1120, height: 860)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "BleKey Studio"
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = AppTheme.panelBackground
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .visible
    window.minSize = NSSize(width: 960, height: 700)
    window.contentViewController = workspace
    window.delegate = self
    window.setFrameAutosaveName("BleKeyStudio.GraphiteWorkspace")
    if !window.setFrameUsingName("BleKeyStudio.GraphiteWorkspace") {
      window.setContentSize(NSSize(width: 1120, height: 860))
    }
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
  }

  public func windowWillClose(_ notification: Notification) {
    windowController = nil
  }

  public func shouldTerminate() -> Bool {
    (windowController?.window?.contentViewController as? WorkspaceViewController)?.confirmClose()
      ?? true
  }

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    shouldTerminate()
  }

  private func installMainMenu() {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem(title: "BleKey Studio", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "BleKey Studio")
    appMenu.addItem(
      withTitle: "关于 BleKey Studio",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "隐藏 BleKey Studio",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    let hideOthers = appMenu.addItem(
      withTitle: "隐藏其他",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h"
    )
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(
      withTitle: "全部显示",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "退出 BleKey Studio",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "编辑")
    editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(
      withTitle: "重做",
      action: Selector(("redo:")),
      keyEquivalent: "Z"
    )
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "窗口")
    windowMenu.addItem(
      withTitle: "最小化",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(
      withTitle: "缩放",
      action: #selector(NSWindow.performZoom(_:)),
      keyEquivalent: ""
    )
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    NSApp.windowsMenu = windowMenu

    NSApp.mainMenu = mainMenu
  }
}
