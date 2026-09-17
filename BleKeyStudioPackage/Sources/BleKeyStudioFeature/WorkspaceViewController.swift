import AppKit
import UniformTypeIdentifiers

final class WorkspaceViewController: NSViewController {
  private enum Destination: Int {
    case mapping
    case settings
    case activity
  }

  private let profileStore: ProfileStore
  private let bluetooth: BluetoothController
  private let activityLogStore: ActivityLogStore
  private let history = UndoManager()

  private var selectedLayer = 1
  private var selectedKey = 1
  private var selectedCategory: ActionCategory = .keyboard
  private var activityLines: [String]
  private var lastWriteMessage = "尚未向设备写入"
  private var lastWriteProfileID: UUID?
  private var lastWriteDeviceID: UUID?
  private var didAutoConnect = false
  private var activeWriteProfile: DeviceProfile?
  private var historyProfileID: UUID?
  private var isRefreshingTable = false
  private var editorProfileID: UUID?
  private var editorAddress: MappingAddress?
  private var actionPopover: NSPopover?

  private let devicePopUp = StudioPopUpButton()
  private let profilePopUp = StudioPopUpButton()
  private let statusDot = NSTextField.label(
    "●", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
  private let statusLabel = NSTextField.label("等待连接", color: .secondaryLabelColor)
  private let bottomApplyButton = StudioButton()
  private let pendingLabel = NSTextField.label("无待写入更改", color: .secondaryLabelColor)
  private let lastResultLabel = NSTextField.label("尚未向设备写入", color: .secondaryLabelColor)
  private let persistenceBanner = StudioSurface(AppTheme.accentFill, bottomSeparator: true)
  private let persistenceLabel = NSTextField.label(
    "", font: .systemFont(ofSize: 13, weight: .medium))
  private let retryPersistenceButton = StudioButton()
  private let exportRecoveryButton = StudioButton()
  private var persistenceBannerHeight: NSLayoutConstraint?

  private var navigationButtons: [NSButton] = []
  private let layerPopUp = StudioPopUpButton()
  private let mappingTable = MappingTableView()
  private let centerHost = NSView()
  private lazy var mappingPage = makeMappingView()
  private lazy var settingsPage = makeSettingsView()
  private lazy var activityPage = makeActivityView()

  private let sourceTitleLabel = NSTextField.label(
    "按键 1",
    font: .systemFont(ofSize: 15, weight: .semibold)
  )
  private let sourceSubtitleLabel = NSTextField.label(
    "设备当前配置未读取",
    color: .secondaryLabelColor
  )
  private let recorderView = ShortcutRecorderView()
  private let categoryControl = StudioSegmentedControl(
    labels: ActionCategory.allCases.map(\.title),
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let keyboardView = KeyboardCanvasView()
  private let actionPaletteView = ActionPaletteView()
  private let actionSearchButton = StudioButton()
  private let keyboardSection = NSView()
  private let keyboardHeader = NSStackView.horizontal()
  private var keyboardExpanded = true
  private let readbackLabel = NSTextField.label(
    "尚未检测", color: .secondaryLabelColor)
  private let readbackButton = StudioButton()
  private let clearButton = StudioButton()
  private let undoButton = StudioButton()
  private let redoButton = StudioButton()

  private let protocolLabel = NSTextField.label(
    "",
    font: .monospacedSystemFont(ofSize: 12, weight: .medium),
    color: .secondaryLabelColor
  )
  private let copyPopUp = StudioPopUpButton()
  private let sleepPopup = StudioPopUpButton()
  private let keyCountPopup = StudioPopUpButton()
  private let activityTextView = NSTextView()

  init(
    profileStore: ProfileStore = ProfileStore(),
    bluetooth: BluetoothController = BluetoothController(),
    activityLogStore: ActivityLogStore = ActivityLogStore()
  ) {
    self.profileStore = profileStore
    self.bluetooth = bluetooth
    self.activityLogStore = activityLogStore
    activityLines = (try? activityLogStore.loadRecent()) ?? []
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    view = NSView()
    view.appearance = NSAppearance(named: .darkAqua)
    view.identifier = NSUserInterfaceItemIdentifier("workspace")
    view.wantsLayer = true
    view.layer?.backgroundColor = AppTheme.canvasBackground.cgColor

    let toolbar = makeToolbar()
    configurePersistenceBanner()
    let splitView = makeSplitView()
    let bottomBar = makeBottomBar()

    view.addSubview(toolbar)
    view.addSubview(persistenceBanner)
    view.addSubview(splitView)
    view.addSubview(bottomBar)
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    persistenceBanner.translatesAutoresizingMaskIntoConstraints = false
    splitView.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: view.topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 54),

      persistenceBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      persistenceBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      persistenceBanner.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      splitView.topAnchor.constraint(equalTo: persistenceBanner.bottomAnchor),
      splitView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

      bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      bottomBar.heightAnchor.constraint(equalToConstant: 54),
    ])
    persistenceBannerHeight = persistenceBanner.heightAnchor.constraint(equalToConstant: 0)
    persistenceBannerHeight?.isActive = true

    categoryControl.selectedSegment = 0
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--show-settings") {
      showDestination(.settings)
    } else if arguments.contains("--show-activity") {
      showDestination(.activity)
    } else {
      if arguments.contains("--show-media") {
        selectedCategory = .media
      }
      showDestination(.mapping)
    }
    bindActions()
    bindBluetooth()
    rebuildProfileMenu()
    refreshUI()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    bluetooth.refresh()
  }

  private func configurePersistenceBanner() {
    persistenceBanner.identifier = NSUserInterfaceItemIdentifier("persistenceBanner")
    persistenceLabel.identifier = NSUserInterfaceItemIdentifier("persistenceMessage")
    persistenceLabel.maximumNumberOfLines = 2
    persistenceLabel.lineBreakMode = .byTruncatingTail
    persistenceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    persistenceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    retryPersistenceButton.title = "重试保存"
    retryPersistenceButton.identifier = NSUserInterfaceItemIdentifier("retryPersistence")
    retryPersistenceButton.image = AppTheme.symbol("arrow.clockwise")
    retryPersistenceButton.target = self
    retryPersistenceButton.action = #selector(retryPersistence)
    exportRecoveryButton.title = "保存副本…"
    exportRecoveryButton.identifier = NSUserInterfaceItemIdentifier("exportRecovery")
    exportRecoveryButton.image = AppTheme.symbol("square.and.arrow.up")
    exportRecoveryButton.target = self
    exportRecoveryButton.action = #selector(exportRecovery)
    let row = NSStackView.horizontal(spacing: 12)
    row.addArrangedSubview(persistenceLabel)
    row.addArrangedSubview(retryPersistenceButton)
    row.addArrangedSubview(exportRecoveryButton)
    persistenceBanner.addSubview(row)
    row.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: persistenceBanner.leadingAnchor, constant: 16),
      row.trailingAnchor.constraint(equalTo: persistenceBanner.trailingAnchor, constant: -16),
      row.centerYAnchor.constraint(equalTo: persistenceBanner.centerYAnchor),
    ])
  }

  private func updatePersistenceFeedback() {
    let message: String
    switch profileStore.persistenceState {
    case .ready:
      message = ""
    case .loadFailed(let reason):
      message = "本地方案读取失败，原文件已保护，编辑与写入已暂停。\n\(reason)"
      retryPersistenceButton.title = "重新读取"
      exportRecoveryButton.title = "从副本恢复…"
    case .saveFailed(let reason):
      message =
        profileStore.hasUnsavedChanges
        ? "本地保存失败，编辑尚未保存到磁盘。\n\(reason)"
        : "本地保存失败，操作未完成。\n\(reason)"
      retryPersistenceButton.title = "重试保存"
      exportRecoveryButton.title = "保存副本…"
    }
    persistenceLabel.stringValue = message
    persistenceLabel.toolTip = message
    persistenceBanner.isHidden = message.isEmpty
    persistenceBannerHeight?.constant = message.isEmpty ? 0 : 66
    exportRecoveryButton.isHidden = profileStore.canEdit && !profileStore.hasUnsavedChanges
  }

  @objc private func retryPersistence() {
    _ = profileStore.retryPersistence()
  }

  @objc private func exportRecovery() {
    guard let window = view.window else { return }
    if !profileStore.canEdit {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.json]
      panel.allowsMultipleSelection = false
      panel.message = "选择方案或方案库副本。原文件会先备份，再恢复本地库；不会写入设备。"
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url, let self else { return }
        do {
          let backup = try self.profileStore.restoreLibrary(from: url)
          self.appendActivity("本地库已恢复；原文件备份：\(backup?.path ?? "原文件不存在")")
        } catch {
          self.showError(title: "无法恢复方案库", message: error.localizedDescription)
        }
      }
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "BleKey-library-recovery.json"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      do {
        try self.profileStore.exportLibrary(to: url)
        self.appendActivity("本地库副本已保存：\(url.path)")
      } catch {
        self.showError(title: "无法保存副本", message: error.localizedDescription)
      }
    }
  }

  func confirmClose() -> Bool {
    guard view.window?.attachedSheet == nil else { return false }
    if activeWriteProfile != nil || bluetooth.isBusy {
      showError(title: "设备操作尚未结束", message: "请等待当前操作结束后再退出。")
      return false
    }
    guard profileStore.hasUnsavedChanges else { return true }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "本地编辑尚未保存"
    alert.informativeText = "退出会丢失未保存的编辑。可以重试保存，或返回窗口保存副本。"
    alert.addButton(withTitle: "重试保存并退出")
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "放弃编辑并退出")
    alert.buttons.last?.hasDestructiveAction = true
    switch alert.runModal() {
    case .alertFirstButtonReturn: return profileStore.retryPersistence()
    case .alertThirdButtonReturn: return true
    default: return false
    }
  }

  private func makeToolbar() -> NSView {
    let material = StudioSurface(AppTheme.panelBackground, bottomSeparator: true)

    let refreshButton = NSButton.symbolButton(
      "arrow.clockwise",
      label: "刷新设备",
      target: self,
      action: #selector(refreshDevices)
    )

    devicePopUp.target = self
    devicePopUp.action = #selector(deviceSelectionChanged(_:))
    devicePopUp.setAccessibilityLabel("蓝牙设备")
    devicePopUp.toolTip = "选择要配置的蓝牙小键盘"
    devicePopUp.symbolName = "keyboard"
    devicePopUp.translatesAutoresizingMaskIntoConstraints = false

    let status = NSStackView.horizontal(spacing: 5)
    status.addArrangedSubview(statusDot)
    status.addArrangedSubview(statusLabel)

    profilePopUp.target = self
    profilePopUp.action = #selector(profileMenuChanged(_:))
    profilePopUp.setAccessibilityLabel("本地方案")
    profilePopUp.symbolName = "square.stack"
    profilePopUp.translatesAutoresizingMaskIntoConstraints = false

    let leading = NSStackView.horizontal(spacing: 8)
    leading.addArrangedSubview(devicePopUp)
    leading.addArrangedSubview(refreshButton)
    leading.addArrangedSubview(status)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let row = NSStackView.horizontal(spacing: 10)
    row.addArrangedSubview(leading)
    row.addArrangedSubview(spacer)
    let disconnect = NSButton.symbolButton(
      "xmark.circle", label: "断开设备", target: self, action: #selector(disconnectDevice))
    row.addArrangedSubview(disconnect)
    material.addSubview(row)
    row.pinEdges(
      to: material,
      insets: NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
    )

    NSLayoutConstraint.activate([
      devicePopUp.widthAnchor.constraint(equalToConstant: 212),
      profilePopUp.widthAnchor.constraint(equalToConstant: 178),
    ])
    return material
  }

  private func makeSplitView() -> NSSplitView {
    let splitView = NSSplitView()
    splitView.isVertical = true
    splitView.dividerStyle = .thin

    let sidebar = makeSidebar()
    splitView.addArrangedSubview(sidebar)
    splitView.addArrangedSubview(centerHost)
    NSLayoutConstraint.activate([
      sidebar.widthAnchor.constraint(equalToConstant: 174),
      centerHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 720),
    ])
    return splitView
  }

  private func makeSidebar() -> NSView {
    let material = StudioSurface(AppTheme.panelBackground)

    let stack = NSStackView.vertical(spacing: 6)
    stack.addArrangedSubview(
      NSTextField.label(
        "BleKey Studio", font: .systemFont(ofSize: 15, weight: .semibold),
        color: AppTheme.text))
    stack.setCustomSpacing(26, after: stack.arrangedSubviews[0])
    for (index, entry) in [
      ("按键映射", "keyboard"), ("设备设置", "slider.horizontal.3"), ("通信记录", "list.bullet.rectangle"),
    ].enumerated() {
      let button = StudioButton(
        title: entry.0, target: self, action: #selector(destinationChanged(_:)))
      button.treatment = .navigation
      button.image = AppTheme.symbol(entry.1, accessibilityDescription: entry.0)
      button.imagePosition = .imageLeading
      button.alignment = .left
      button.bezelStyle = .recessed
      button.setButtonType(.pushOnPushOff)
      button.tag = index
      button.identifier = NSUserInterfaceItemIdentifier("navigation.\(index)")
      stack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
      navigationButtons.append(button)
    }
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    stack.addArrangedSubview(spacer)

    material.addSubview(stack)
    stack.pinEdges(
      to: material,
      insets: NSEdgeInsets(top: 24, left: 12, bottom: 14, right: 12)
    )
    return material
  }

  private func makeMappingView() -> NSView {
    let content = FlippedContentView()
    content.wantsLayer = true
    content.layer?.backgroundColor = AppTheme.canvasBackground.cgColor

    let titleRow = NSStackView.horizontal()
    titleRow.addArrangedSubview(
      NSTextField.label(
        "按键映射", font: .systemFont(ofSize: 24, weight: .bold)))
    titleRow.addArrangedSubview(horizontalSpacer())
    titleRow.addArrangedSubview(NSTextField.label("本地方案", color: .secondaryLabelColor))
    titleRow.addArrangedSubview(profilePopUp)

    let layerRow = NSStackView.horizontal()
    layerRow.addArrangedSubview(
      NSTextField.label(
        "设备层", font: .systemFont(ofSize: 13, weight: .medium),
        color: AppTheme.secondaryText))
    for layer in 1...10 {
      layerPopUp.addItem(withTitle: "第 \(layer) 层")
      layerPopUp.lastItem?.tag = layer
    }
    layerPopUp.target = self
    layerPopUp.action = #selector(layerChanged(_:))
    layerPopUp.setAccessibilityLabel("当前设备层")
    layerPopUp.identifier = NSUserInterfaceItemIdentifier("layerSelector")
    layerPopUp.widthAnchor.constraint(equalToConstant: 98).isActive = true
    layerRow.addArrangedSubview(layerPopUp)
    let copyLayer = StudioPopUpButton()
    copyLayer.symbolName = "square.on.square"
    copyLayer.fixedTitle = "复制层"
    copyLayer.toolTip = "复制当前层到其他层"
    copyLayer.setAccessibilityLabel("复制当前层")
    copyLayer.addItem(withTitle: "复制层")
    for layer in 1...10 {
      let item = NSMenuItem(
        title: "第 \(layer) 层", action: #selector(copyLayer(_:)), keyEquivalent: "")
      item.target = self
      item.tag = layer
      copyLayer.menu?.addItem(item)
    }
    layerRow.addArrangedSubview(copyLayer)
    layerRow.addArrangedSubview(horizontalSpacer())
    layerRow.addArrangedSubview(sourceSubtitleLabel)
    let readInfo = NSButton.symbolButton(
      "info.circle", label: "配置读取状态", target: self, action: #selector(openDeviceSettings))
    layerRow.addArrangedSubview(readInfo)

    for (id, title, width) in [
      ("key", "实体按键", 110.0), ("local", "本地映射", 260.0),
      ("device", "设备当前值", 150.0), ("status", "状态", 130.0),
    ] {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
      column.title = title
      column.headerCell = StudioTableHeaderCell(textCell: title)
      column.width = width
      column.minWidth = id == "local" ? 150 : 90
      mappingTable.addTableColumn(column)
    }
    mappingTable.rowHeight = 34
    mappingTable.intercellSpacing = NSSize(width: 8, height: 0)
    mappingTable.usesAlternatingRowBackgroundColors = false
    mappingTable.backgroundColor = AppTheme.canvasBackground
    mappingTable.style = .plain
    mappingTable.focusRingType = .none
    mappingTable.allowsEmptySelection = false
    mappingTable.dataSource = self
    mappingTable.delegate = self
    mappingTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    mappingTable.identifier = NSUserInterfaceItemIdentifier("mappingTable")
    mappingTable.target = self
    mappingTable.doubleAction = #selector(mappingDoubleClicked)
    mappingTable.onRecord = { [weak self] in self?.beginRecordingSelectedMapping() }
    let tableScroll = NSScrollView()
    tableScroll.documentView = mappingTable
    tableScroll.hasVerticalScroller = true
    tableScroll.autohidesScrollers = true
    tableScroll.borderType = .noBorder
    tableScroll.backgroundColor = AppTheme.canvasBackground
    mappingTable.headerView?.frame.size.height = 26
    tableScroll.heightAnchor.constraint(equalToConstant: 128).isActive = true

    let editRow = NSStackView.horizontal()
    editRow.addArrangedSubview(sourceTitleLabel)
    editRow.addArrangedSubview(horizontalSpacer())
    copyPopUp.target = self
    copyPopUp.action = #selector(copyMapping(_:))
    copyPopUp.setAccessibilityLabel("复制当前映射")
    copyPopUp.symbolName = "square.on.square"
    copyPopUp.fixedTitle = "复制到"
    editRow.addArrangedSubview(copyPopUp)
    clearButton.title = ""
    clearButton.treatment = .quiet
    clearButton.toolTip = "清空当前映射"
    clearButton.setAccessibilityLabel("清空当前映射")
    clearButton.bezelStyle = .rounded
    clearButton.image = AppTheme.symbol("trash", accessibilityDescription: "清空映射")
    clearButton.imagePosition = .imageLeading
    clearButton.target = self
    clearButton.action = #selector(clearSelectedMapping)
    editRow.addArrangedSubview(clearButton)

    let categoryRow = NSStackView.horizontal(spacing: 12)
    categoryRow.addArrangedSubview(
      NSTextField.label(
        "动作", font: .systemFont(ofSize: 13, weight: .medium),
        color: AppTheme.secondaryText))
    for segment in 0..<categoryControl.segmentCount {
      categoryControl.setWidth(58, forSegment: segment)
    }
    categoryControl.target = self
    categoryControl.action = #selector(categoryChanged(_:))
    categoryControl.setAccessibilityLabel("动作类别")
    categoryRow.addArrangedSubview(categoryControl)
    categoryRow.addArrangedSubview(horizontalSpacer())
    actionSearchButton.target = self
    actionSearchButton.action = #selector(openActionSearch)
    actionSearchButton.image = AppTheme.symbol("magnifyingglass")
    actionSearchButton.setAccessibilityLabel("搜索并选择映射动作")
    actionSearchButton.identifier = NSUserInterfaceItemIdentifier("openActionSearch")
    actionSearchButton.toolTip = "搜索并选择映射动作"
    actionSearchButton.widthAnchor.constraint(equalToConstant: 180).isActive = true
    categoryRow.addArrangedSubview(actionSearchButton)
    recorderView.translatesAutoresizingMaskIntoConstraints = false
    recorderView.heightAnchor.constraint(equalToConstant: 52).isActive = true
    actionPaletteView.heightAnchor.constraint(equalToConstant: 228).isActive = true

    let disclosure = StudioButton(
      title: "MacBook 键盘", target: self, action: #selector(toggleKeyboard(_:)))
    disclosure.setButtonType(.pushOnPushOff)
    disclosure.bezelStyle = .inline
    disclosure.treatment = .quiet
    disclosure.image = AppTheme.symbol("keyboard", accessibilityDescription: "键盘")
    disclosure.imagePosition = .imageLeading
    disclosure.state = .on
    disclosure.toolTip = "显示或收起辅助键盘"
    keyboardHeader.addArrangedSubview(disclosure)
    keyboardHeader.addArrangedSubview(horizontalSpacer())
    let advanced = StudioButton(title: "", target: self, action: #selector(toggleAdvanced(_:)))
    advanced.treatment = .quiet
    advanced.image = AppTheme.symbol(
      "chevron.left.forwardslash.chevron.right",
      accessibilityDescription: "协议详情")
    advanced.toolTip = "显示或隐藏协议详情"
    advanced.setAccessibilityLabel("协议详情")
    advanced.widthAnchor.constraint(equalToConstant: 30).isActive = true
    advanced.setButtonType(.pushOnPushOff)
    advanced.bezelStyle = .inline
    protocolLabel.isHidden = true
    editRow.addArrangedSubview(advanced)
    keyboardSection.addSubview(keyboardView)
    keyboardView.pinEdges(to: keyboardSection)
    keyboardSection.heightAnchor.constraint(equalToConstant: 276).isActive = true

    let stack = NSStackView.vertical(spacing: 10)
    stack.addArrangedSubview(titleRow)
    stack.addArrangedSubview(layerRow)
    stack.addArrangedSubview(tableScroll)
    stack.addArrangedSubview(editRow)
    stack.addArrangedSubview(categoryRow)
    stack.addArrangedSubview(recorderView)
    stack.addArrangedSubview(actionPaletteView)
    stack.addArrangedSubview(SeparatorView())
    stack.addArrangedSubview(keyboardHeader)
    stack.addArrangedSubview(keyboardSection)
    stack.addArrangedSubview(protocolLabel)
    stack.setCustomSpacing(18, after: titleRow)
    stack.setCustomSpacing(18, after: tableScroll)
    for item in stack.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    content.addSubview(stack)
    stack.pinEdges(
      to: content,
      insets: NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
    )
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = content
    content.translatesAutoresizingMaskIntoConstraints = false
    content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    return scroll
  }

  private func horizontalSpacer() -> NSView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return spacer
  }

  private func makeSettingsView() -> NSView {
    let content = NSView()
    let title = NSTextField.label(
      "设备设置",
      font: .systemFont(ofSize: 24, weight: .bold)
    )
    let subtitle = NSTextField.label(
      "休眠时间将在设备重启后生效",
      color: .secondaryLabelColor
    )

    if sleepPopup.numberOfItems == 0 {
      sleepPopup.addItem(withTitle: "保持设备现有设置")
      for timeout in SleepTimeout.allCases {
        sleepPopup.addItem(withTitle: timeout.title)
        sleepPopup.lastItem?.representedObject = Int(timeout.rawValue)
      }
    }
    sleepPopup.target = self
    sleepPopup.action = #selector(sleepTimeoutChanged(_:))
    sleepPopup.setAccessibilityLabel("自动休眠时间")

    if keyCountPopup.numberOfItems == 0 {
      for count in 1...24 {
        keyCountPopup.addItem(withTitle: "\(count) 个按键")
        keyCountPopup.lastItem?.tag = count
      }
    }
    keyCountPopup.target = self
    keyCountPopup.action = #selector(keyCountChanged(_:))
    keyCountPopup.setAccessibilityLabel("实体按键数量")

    let grid = NSGridView(views: [
      [NSTextField.label("自动休眠", font: .systemFont(ofSize: 14, weight: .semibold)), sleepPopup],
      [
        NSTextField.label("实体按键数量", font: .systemFont(ofSize: 14, weight: .semibold)),
        keyCountPopup,
      ],
    ])
    grid.rowSpacing = 14
    grid.columnSpacing = 28
    grid.xPlacement = .fill
    grid.column(at: 0).width = 130

    let line = SeparatorView()
    let unsupportedTitle = NSTextField.label(
      "待机指示灯",
      font: .systemFont(ofSize: 14, weight: .semibold)
    )
    let unsupportedDetail = NSTextField.label(
      "未确认协议，暂不提供修改",
      color: .secondaryLabelColor
    )
    let unsupportedRow = NSStackView.vertical(spacing: 4)
    unsupportedRow.addArrangedSubview(unsupportedTitle)
    unsupportedRow.addArrangedSubview(unsupportedDetail)

    let stack = NSStackView.vertical(spacing: 12)
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(subtitle)
    stack.setCustomSpacing(28, after: subtitle)
    stack.addArrangedSubview(grid)
    stack.setCustomSpacing(26, after: grid)
    stack.addArrangedSubview(line)
    stack.addArrangedSubview(
      NSTextField.label(
        "设备配置读取", font: .systemFont(ofSize: 14, weight: .semibold)))
    stack.addArrangedSubview(readbackLabel)
    readbackButton.title = "检测读取能力"
    readbackButton.bezelStyle = .rounded
    readbackButton.image = AppTheme.symbol("arrow.down.doc", accessibilityDescription: "检测读取能力")
    readbackButton.imagePosition = .imageLeading
    readbackButton.target = self
    readbackButton.action = #selector(inspectReadback)
    readbackButton.toolTip = "只读取支持 Read 的配置特征；不发送改键命令，原始结果见通信记录"
    stack.addArrangedSubview(readbackButton)
    stack.setCustomSpacing(24, after: readbackButton)
    stack.addArrangedSubview(unsupportedRow)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    stack.addArrangedSubview(spacer)

    content.addSubview(stack)
    stack.pinEdges(
      to: content,
      insets: NSEdgeInsets(top: 28, left: 30, bottom: 24, right: 30)
    )
    line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    return content
  }

  private func makeActivityView() -> NSView {
    let content = NSView()
    let title = NSTextField.label(
      "通信记录",
      font: .systemFont(ofSize: 24, weight: .bold)
    )
    let subtitle = NSTextField.label(
      "本地修改与设备通信记录",
      color: .secondaryLabelColor
    )
    let pathLabel = NSTextField.label(
      "日志文件：\((activityLogStore.storageURL.path as NSString).abbreviatingWithTildeInPath)",
      font: .systemFont(ofSize: 12, weight: .medium),
      color: .secondaryLabelColor)
    pathLabel.identifier = NSUserInterfaceItemIdentifier("activityLogPath")
    pathLabel.maximumNumberOfLines = 1
    pathLabel.lineBreakMode = .byTruncatingMiddle
    pathLabel.toolTip = activityLogStore.storageURL.path
    pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let revealButton = StudioButton(
      title: "在 Finder 中显示", target: self, action: #selector(revealActivityLog))
    revealButton.image = AppTheme.symbol(
      "folder", accessibilityDescription: "在 Finder 中显示日志")
    revealButton.treatment = .quiet
    let pathRow = NSStackView.horizontal(spacing: 8)
    pathRow.addArrangedSubview(pathLabel)
    pathRow.addArrangedSubview(revealButton)

    activityTextView.isEditable = false
    activityTextView.isSelectable = true
    activityTextView.drawsBackground = false
    activityTextView.identifier = NSUserInterfaceItemIdentifier("activityLogView")
    activityTextView.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    activityTextView.textColor = AppTheme.secondaryText
    activityTextView.textContainerInset = NSSize(width: 8, height: 8)
    activityTextView.frame = NSRect(x: 0, y: 0, width: 760, height: 1)
    activityTextView.minSize = NSSize(width: 0, height: 0)
    activityTextView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude)
    activityTextView.isVerticallyResizable = true
    activityTextView.isHorizontallyResizable = false
    activityTextView.autoresizingMask = [.width]
    activityTextView.textContainer?.containerSize = NSSize(
      width: 760,
      height: CGFloat.greatestFiniteMagnitude)
    activityTextView.textContainer?.widthTracksTextView = true
    activityTextView.string = activityLines.joined(separator: "\n")

    let scroll = NSScrollView()
    scroll.drawsBackground = true
    scroll.backgroundColor = AppTheme.well
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    scroll.documentView = activityTextView

    let stack = NSStackView.vertical(spacing: 4)
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(subtitle)
    stack.addArrangedSubview(pathRow)
    stack.setCustomSpacing(14, after: pathRow)
    stack.addArrangedSubview(scroll)
    content.addSubview(stack)
    stack.pinEdges(
      to: content,
      insets: NSEdgeInsets(top: 28, left: 30, bottom: 24, right: 30)
    )
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
    return content
  }

  private func makeBottomBar() -> NSView {
    let bar = NSView()
    bar.wantsLayer = true
    bar.layer?.backgroundColor = AppTheme.panelBackground.cgColor

    let separator = SeparatorView()
    bar.addSubview(separator)
    separator.translatesAutoresizingMaskIntoConstraints = false

    for (button, symbol, label, selector) in [
      (undoButton, "arrow.uturn.backward", "撤销", #selector(undo(_:))),
      (redoButton, "arrow.uturn.forward", "重做", #selector(redo(_:))),
    ] {
      button.image = AppTheme.symbol(symbol, accessibilityDescription: label)
      button.isBordered = false
      button.treatment = .quiet
      button.toolTip = label
      button.target = self
      button.action = selector
      button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    bottomApplyButton.title = "应用更改"
    bottomApplyButton.identifier = NSUserInterfaceItemIdentifier("applyChanges")
    bottomApplyButton.image = AppTheme.symbol(
      "arrow.down.to.line", accessibilityDescription: "应用更改")
    bottomApplyButton.imagePosition = .imageLeading
    bottomApplyButton.bezelStyle = .rounded
    bottomApplyButton.treatment = .primary
    bottomApplyButton.target = self
    bottomApplyButton.action = #selector(applyChanges)
    bottomApplyButton.widthAnchor.constraint(equalToConstant: 148).isActive = true
    pendingLabel.identifier = NSUserInterfaceItemIdentifier("saveSummary")
    pendingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    pendingLabel.maximumNumberOfLines = 1
    pendingLabel.lineBreakMode = .byTruncatingTail
    pendingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    lastResultLabel.identifier = NSUserInterfaceItemIdentifier("deviceWriteStatus")
    lastResultLabel.font = .systemFont(ofSize: 12, weight: .medium)
    lastResultLabel.maximumNumberOfLines = 1
    lastResultLabel.lineBreakMode = .byTruncatingTail
    lastResultLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let status = NSStackView.vertical(spacing: 2)
    status.addArrangedSubview(pendingLabel)
    status.addArrangedSubview(lastResultLabel)
    status.setContentHuggingPriority(.defaultLow, for: .horizontal)
    status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    pendingLabel.widthAnchor.constraint(equalTo: status.widthAnchor).isActive = true
    lastResultLabel.widthAnchor.constraint(equalTo: status.widthAnchor).isActive = true

    let row = NSStackView.horizontal(spacing: 10)
    row.addArrangedSubview(status)
    row.addArrangedSubview(undoButton)
    row.addArrangedSubview(redoButton)
    row.addArrangedSubview(bottomApplyButton)
    row.distribution = .fill
    bar.addSubview(row)
    row.pinEdges(to: bar, insets: NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))

    NSLayoutConstraint.activate([
      separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
      separator.topAnchor.constraint(equalTo: bar.topAnchor),
    ])
    return bar
  }

  private func bindActions() {
    profileStore.onChange = { [weak self] in
      self?.refreshUI()
    }
    keyboardView.onActionSelected = { [weak self] action in
      guard let self else { return }
      // #region debug-point A-D:action-callback
      if let url = URL(string: "http://127.0.0.1:7777/event"),
        let body = try? JSONSerialization.data(withJSONObject: [
          "sessionId": "mapping-activity-log",
          "runId": "post-fix",
          "hypothesisId": "A,D",
          "location": "WorkspaceViewController.keyboardView.onActionSelected",
          "msg": "[DEBUG] Keyboard action callback",
          "data": [
            "layer": currentAddress.layer,
            "key": currentAddress.key,
            "actionID": action?.id ?? "nil",
            "modifiers": KeyModifier.normalized(keyboardView.activeModifiers).map(\.displayName)
              .joined(separator: " "),
          ],
        ])
      {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: request, from: body).resume()
      }
      // #endregion
      selectedCategory = .keyboard
      if let action {
        assign(action: action, modifiers: keyboardView.activeModifiers)
      } else if keyboardView.activeModifiers.isEmpty {
        clearCurrentAssignment(actionName: "清除主键")
      } else {
        assign(action: ActionCatalog.modifierOnly, modifiers: keyboardView.activeModifiers)
      }
    }
    keyboardView.onModifierChanged = { [weak self] modifiers in
      guard let self else { return }
      // #region debug-point A-C-D:modifier-callback
      if let url = URL(string: "http://127.0.0.1:7777/event"),
        let body = try? JSONSerialization.data(withJSONObject: [
          "sessionId": "mapping-activity-log",
          "runId": "post-fix",
          "hypothesisId": "A,C,D",
          "location": "WorkspaceViewController.keyboardView.onModifierChanged",
          "msg": "[DEBUG] Modifier callback",
          "data": [
            "layer": currentAddress.layer,
            "key": currentAddress.key,
            "currentActionID": currentAssignment?.actionID ?? "nil",
            "modifiers": KeyModifier.normalized(modifiers).map(\.displayName).joined(
              separator: " "),
          ],
        ])
      {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: request, from: body).resume()
      }
      // #endregion
      guard !modifiers.isEmpty else {
        if currentAssignment?.actionID == ActionCatalog.modifierOnly.id {
          clearCurrentAssignment(actionName: "清除修饰键")
        } else if let assignment = currentAssignment,
          let action = ActionCatalog.action(id: assignment.actionID),
          action.category == .keyboard
        {
          assign(action: action, modifiers: [])
        }
        return
      }
      if let assignment = currentAssignment,
        let action = ActionCatalog.action(id: assignment.actionID),
        action.category == .keyboard
      {
        assign(action: action, modifiers: modifiers)
      } else {
        assign(action: ActionCatalog.modifierOnly, modifiers: modifiers)
      }
    }
    recorderView.onRecorded = { [weak self] assignment in
      guard let action = ActionCatalog.action(id: assignment.actionID) else { return }
      self?.selectedCategory = .keyboard
      self?.assign(action: action, modifiers: assignment.modifierSet)
    }
    actionPaletteView.onActionSelected = { [weak self] action in
      self?.assign(action: action, modifiers: [])
    }
  }

  private func bindBluetooth() {
    bluetooth.onDevicesChange = { [weak self] devices in
      guard let self else { return }
      self.rebuildDeviceMenu(devices)
      if !self.didAutoConnect,
        let device = devices.first(where: \.isSystemConnected)
      {
        self.didAutoConnect = true
        self.profileStore.bindSelectedProfile(
          deviceIdentifier: device.id,
          deviceName: device.name,
          keyCount: device.inferredKeyCount
        )
        self.bluetooth.connect(deviceID: device.id)
      }
    }
    bluetooth.onStateChange = { [weak self] state in
      self?.updateConnectionState(state)
    }
    bluetooth.onLog = { [weak self] message in
      self?.appendActivity(message)
    }
    bluetooth.onReadbackChange = { [weak self] in self?.refreshUI() }
    bluetooth.onCommandResult = { [weak self] command, result in
      guard let self else { return }
      switch result {
      case .success:
        if let snapshot = self.activeWriteProfile {
          self.profileStore.recordSent(command, from: snapshot)
        }
        self.lastWriteMessage =
          self.bluetooth.isDemoMode
          ? "演示发送：\(command.label)；未写入真实设备"
          : "已发送 \(command.label)，设备配置未读回"
      case .failure(let error):
        self.lastWriteMessage = "写入失败：\(error.localizedDescription)"
      }
      self.refreshUI()
    }
    bluetooth.onBatchFinished = { [weak self] in
      guard let self else { return }
      if self.activeWriteProfile != nil, self.bluetooth.state.isReady {
        self.lastWriteMessage =
          self.bluetooth.isDemoMode
          ? "演示发送完成；未写入真实设备"
          : "本次发送完成，设备配置未读回"
      }
      self.activeWriteProfile = nil
      self.refreshUI()
    }
  }

  private var currentAddress: MappingAddress {
    MappingAddress(layer: selectedLayer, key: selectedKey)
  }

  private var currentAssignment: KeyAssignment? {
    profileStore.selectedProfile.assignment(at: currentAddress)
  }

  private func assign(action: KeyAction, modifiers: Set<KeyModifier>) {
    guard profileStore.canEdit else { return }
    recorderView.cancelRecording()
    let address = currentAddress
    let oldValue = currentAssignment
    let newValue = KeyAssignment(
      actionID: action.id,
      modifiers: action.category == .keyboard ? modifiers : []
    )
    // #region debug-point A-C-D:assignment-mutation
    if let url = URL(string: "http://127.0.0.1:7777/event"),
      let body = try? JSONSerialization.data(withJSONObject: [
        "sessionId": "mapping-activity-log",
        "runId": "post-fix",
        "hypothesisId": "A,C,D",
        "location": "WorkspaceViewController.assign",
        "msg": "[DEBUG] Assignment mutation requested",
        "data": [
          "layer": currentAddress.layer,
          "key": currentAddress.key,
          "oldActionID": oldValue?.actionID ?? "nil",
          "newActionID": newValue.actionID,
          "oldModifiers": oldValue.map {
            KeyModifier.normalized($0.modifierSet).map(\.displayName).joined(separator: " ")
          } ?? "",
          "newModifiers": KeyModifier.normalized(newValue.modifierSet).map(\.displayName)
            .joined(separator: " "),
          "isNoop": oldValue == newValue,
        ],
      ])
    {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      URLSession.shared.uploadTask(with: request, from: body).resume()
    }
    // #endregion
    guard oldValue != newValue else { return }
    registerUndo(oldValue, at: address, actionName: "更改按键映射")
    profileStore.updateSelectedProfile {
      $0.setAssignment(newValue, at: address)
    }
    recordActivity(
      "本地修改 · 第 \(address.layer) 层 · 按键 \(address.key) · "
        + "\(XKeyProtocol.displayName(for: oldValue)) → \(XKeyProtocol.displayName(for: newValue))")
  }

  private func clearCurrentAssignment(actionName: String) {
    guard profileStore.canEdit else { return }
    let address = currentAddress
    let oldValue = currentAssignment
    guard oldValue != nil else { return }
    registerUndo(oldValue, at: address, actionName: actionName)
    profileStore.updateSelectedProfile {
      $0.setAssignment(nil, at: address)
    }
    recordActivity(
      "本地修改 · 第 \(address.layer) 层 · 按键 \(address.key) · "
        + "\(XKeyProtocol.displayName(for: oldValue)) → 保持设备原值")
  }

  private func registerUndo(
    _ assignment: KeyAssignment?,
    at address: MappingAddress,
    actionName: String
  ) {
    history.registerUndo(withTarget: self) { target in
      let current = target.profileStore.selectedProfile.assignment(at: address)
      target.registerUndo(current, at: address, actionName: actionName)
      target.profileStore.updateSelectedProfile {
        $0.setAssignment(assignment, at: address)
      }
    }
    history.setActionName(actionName)
  }

  private func refreshUI() {
    guard isViewLoaded else { return }
    updatePersistenceFeedback()
    if !profileStore.canEdit { history.removeAllActions() }
    let profile = profileStore.selectedProfile
    if historyProfileID != profile.id {
      history.removeAllActions()
      historyProfileID = profile.id
    }
    selectedKey = min(max(1, selectedKey), profile.keyCount)
    let address = currentAddress
    if editorProfileID != profile.id || editorAddress != address {
      recorderView.cancelRecording()
      actionPopover?.close()
      editorProfileID = profile.id
      editorAddress = address
    }
    let assignment = profile.assignment(at: address)
    let action = assignment.flatMap { ActionCatalog.action(id: $0.actionID) }

    sourceTitleLabel.stringValue = "第 \(selectedLayer) 层 · 按键 \(selectedKey)"
    recorderView.assignment = action?.category == .keyboard ? assignment : nil
    keyboardView.selectedActionID = action?.category == .keyboard ? action?.id : nil
    keyboardView.activeModifiers = assignment?.modifierSet ?? []
    actionPaletteView.selectedActionID = action?.id

    isRefreshingTable = true
    mappingTable.reloadData()
    mappingTable.selectRowIndexes(IndexSet(integer: selectedKey - 1), byExtendingSelection: false)
    isRefreshingTable = false

    layerPopUp.selectItem(withTag: selectedLayer)
    sleepPopup.selectItem(
      withTitle: profile.shouldManageSleep ? profile.sleepTimeout.title : "保持设备现有设置"
    )
    keyCountPopup.selectItem(withTag: profile.keyCount)
    rebuildCopyMenu()

    if let assignment {
      do {
        protocolLabel.stringValue = try XKeyProtocol.mappingCommand(
          address: address,
          assignment: assignment
        ).hex.groupedHex
      } catch {
        protocolLabel.stringValue = error.localizedDescription
      }
    } else {
      protocolLabel.stringValue = "未设置"
    }

    let pendingCount = profile.dirtyAddresses.count + (profile.isSleepDirty ? 1 : 0)
    updateSaveFeedback(pendingCount: pendingCount)
    bottomApplyButton.title = pendingCount == 0 ? "无待写入更改" : "应用 \(pendingCount) 项更改"
    let canApply =
      pendingCount > 0 && bluetooth.canWrite && activeWriteProfile == nil
      && profileStore.canApplyToDevice
    bottomApplyButton.isEnabled = canApply
    devicePopUp.isEnabled =
      !bluetooth.devices.isEmpty && activeWriteProfile == nil && !bluetooth.isBusy
    profilePopUp.isEnabled = activeWriteProfile == nil && profileStore.canEdit
    layerPopUp.isEnabled = profileStore.canEdit
    categoryControl.isEnabled = profileStore.canEdit
    actionSearchButton.isEnabled = profileStore.canEdit
    recorderView.isEnabled = profileStore.canEdit
    if !profileStore.canEdit { actionPopover?.close() }
    copyPopUp.isEnabled = profileStore.canEdit
    sleepPopup.isEnabled = profileStore.canEdit
    keyCountPopup.isEnabled = profileStore.canEdit
    readbackButton.isEnabled = bluetooth.canInspectReadback
    readbackLabel.stringValue = bluetooth.readbackSummary
    undoButton.isEnabled = history.canUndo
    redoButton.isEnabled = history.canRedo
    clearButton.isEnabled = assignment != nil && profileStore.canEdit
    rebuildProfileMenu()
    updateCategoryVisibility()
  }

  private func updateSaveFeedback(pendingCount: Int) {
    let pending =
      pendingCount == 0
      ? "无待写入更改"
      : "\(pendingCount) 项待写入设备"
    let localStatus: String
    switch profileStore.persistenceState {
    case .ready:
      localStatus =
        profileStore.hasUnsavedChanges
        ? "尚未保存到本地"
        : (profileStore.hasSavedLibrary ? "已保存到本地" : "本地草稿")
    case .loadFailed:
      localStatus = "本地方案读取失败"
    case .saveFailed:
      localStatus = profileStore.hasUnsavedChanges ? "编辑未保存到本地" : "本地保存失败"
    }
    pendingLabel.stringValue = "\(localStatus) · \(pending)"
    pendingLabel.textColor = profileStore.canApplyToDevice ? AppTheme.text : AppTheme.pending
    pendingLabel.toolTip = pendingLabel.stringValue

    let reason: String
    if !profileStore.canApplyToDevice {
      reason = "先恢复本地保存，再应用到设备"
    } else if case .writing(let progress) = bluetooth.state {
      reason =
        "\(bluetooth.isDemoMode ? "演示发送" : "正在发送") \(progress.completed + 1)/\(progress.total)"
    } else if bluetooth.isBusy || activeWriteProfile != nil {
      reason = "设备操作进行中，暂不可应用"
    } else if case .failed(let message) = bluetooth.state {
      reason = "设备操作失败：\(message)"
    } else if !bluetooth.canWrite {
      switch bluetooth.state {
      case .connecting, .discovering, .unavailable:
        reason = bluetooth.state.title
      default:
        reason = "连接设备后可应用"
      }
    } else if lastWriteProfileID == profileStore.selectedProfile.id,
      lastWriteDeviceID == bluetooth.connectedDeviceID
    {
      reason = lastWriteMessage
    } else {
      reason = bluetooth.isDemoMode ? "演示模式；不会写入真实设备" : "设备当前配置未读回"
    }
    lastResultLabel.stringValue = reason
    lastResultLabel.toolTip = reason
    bottomApplyButton.toolTip = reason
  }

  private func updateCategoryVisibility() {
    categoryControl.selectedSegment = selectedCategory.rawValueIndex
    keyboardView.isHidden = false
    keyboardHeader.isHidden = selectedCategory != .keyboard
    keyboardSection.isHidden = selectedCategory != .keyboard || !keyboardExpanded
    actionPaletteView.isHidden = selectedCategory == .keyboard
    recorderView.isHidden = selectedCategory != .keyboard
    if selectedCategory != .keyboard {
      actionPaletteView.category = selectedCategory
    }
    let action = currentAssignment.flatMap { ActionCatalog.action(id: $0.actionID) }
    actionSearchButton.title = action?.category == selectedCategory ? action!.name : "搜索动作…"
  }

  private func adoptCategoryFromCurrentAssignment() {
    selectedCategory =
      currentAssignment
      .flatMap { ActionCatalog.action(id: $0.actionID)?.category }
      ?? .keyboard
  }

  private func showDestination(_ destination: Destination) {
    recorderView.cancelRecording()
    actionPopover?.close()
    for subview in centerHost.subviews {
      subview.removeFromSuperview()
    }
    let destinationView: NSView
    switch destination {
    case .mapping:
      destinationView = mappingPage
    case .settings:
      destinationView = settingsPage
    case .activity:
      destinationView = activityPage
    }
    centerHost.addSubview(destinationView)
    destinationView.pinEdges(to: centerHost)
    for button in navigationButtons {
      button.state = button.tag == destination.rawValue ? .on : .off
    }
    refreshUI()
    centerHost.layoutSubtreeIfNeeded()
    // #region debug-point B:activity-render
    if destination == .activity, let url = URL(string: "http://127.0.0.1:7777/event"),
      let body = try? JSONSerialization.data(withJSONObject: [
        "sessionId": "mapping-activity-log",
        "runId": "post-fix",
        "hypothesisId": "B",
        "location": "WorkspaceViewController.showDestination",
        "msg": "[DEBUG] Activity page opened",
        "data": [
          "bufferedLines": activityLines.count,
          "textCharacters": activityTextView.string.count,
          "textWidth": activityTextView.frame.width,
          "textHeight": activityTextView.frame.height,
        ],
      ])
    {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      URLSession.shared.uploadTask(with: request, from: body).resume()
    }
    // #endregion
  }

  private func rebuildDeviceMenu(_ devices: [BLEDeviceDescriptor]) {
    devicePopUp.removeAllItems()
    if devices.isEmpty {
      devicePopUp.addItem(withTitle: "未发现设备")
      devicePopUp.isEnabled = false
      return
    }
    devicePopUp.isEnabled = !bluetooth.isBusy && activeWriteProfile == nil
    for device in devices {
      devicePopUp.addItem(
        withTitle: device.isSystemConnected ? "\(device.name) · 已配对" : device.name
      )
      devicePopUp.lastItem?.representedObject = device.id.uuidString
    }
    if let connectedDeviceID = bluetooth.connectedDeviceID,
      let index = devices.firstIndex(where: { $0.id == connectedDeviceID })
    {
      devicePopUp.selectItem(at: index)
    }
  }

  private func rebuildProfileMenu() {
    profilePopUp.removeAllItems()
    for profile in profileStore.profiles {
      let item = NSMenuItem(
        title: profile.name,
        action: #selector(selectProfile(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = profile.id.uuidString
      item.state = profile.id == profileStore.selectedProfile.id ? .on : .off
      profilePopUp.menu?.addItem(item)
    }
    profilePopUp.menu?.addItem(.separator())
    addProfileCommand("新建方案", command: "new", symbol: "plus")
    addProfileCommand("复制方案", command: "duplicate", symbol: "plus.square.on.square")
    addProfileCommand("重命名…", command: "rename", symbol: "pencil")
    addProfileCommand("删除方案", command: "delete", symbol: "trash")
    profilePopUp.menu?.addItem(.separator())
    addProfileCommand("导入方案…", command: "import", symbol: "square.and.arrow.down")
    addProfileCommand("导出方案…", command: "export", symbol: "square.and.arrow.up")
    profilePopUp.selectItem(withTitle: profileStore.selectedProfile.name)
  }

  private func addProfileCommand(_ title: String, command: String, symbol: String) {
    let item = NSMenuItem(
      title: title,
      action: #selector(profileCommand(_:)),
      keyEquivalent: ""
    )
    item.target = self
    item.representedObject = command
    item.image = AppTheme.symbol(symbol, accessibilityDescription: title)
    profilePopUp.menu?.addItem(item)
  }

  private func rebuildCopyMenu() {
    copyPopUp.removeAllItems()
    copyPopUp.addItem(withTitle: "复制到…")
    copyPopUp.menu?.addItem(.separator())
    for key in 1...profileStore.selectedProfile.keyCount where key != selectedKey {
      let item = NSMenuItem(
        title: "本层按键 \(key)",
        action: #selector(copyMappingToKey(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = key
      copyPopUp.menu?.addItem(item)
    }
  }

  private func updateConnectionState(_ state: BluetoothConnectionState) {
    statusLabel.stringValue = bluetooth.isDemoMode ? "演示模式 · \(state.title)" : state.title
    switch state {
    case .ready:
      statusDot.textColor = AppTheme.connected
    case .writing:
      statusDot.textColor = AppTheme.pending
    case .failed, .unavailable:
      statusDot.textColor = .systemRed
    default:
      statusDot.textColor = AppTheme.secondaryText
    }
    refreshUI()
  }

  private func appendActivity(_ message: String) {
    activityLines.append(message)
    if activityLines.count > 300 {
      activityLines.removeFirst(activityLines.count - 300)
    }
    activityTextView.string = activityLines.joined(separator: "\n")
    activityTextView.scrollToEndOfDocument(nil)
    do {
      try activityLogStore.append(message)
    } catch {
      let failure =
        "\(Self.activityTimestamp.string(from: Date()))  日志写入失败 · \(error.localizedDescription)"
      activityLines.append(failure)
      activityTextView.string = activityLines.joined(separator: "\n")
    }
    // #region debug-point B-E:activity-append
    if let url = URL(string: "http://127.0.0.1:7777/event"),
      let body = try? JSONSerialization.data(withJSONObject: [
        "sessionId": "mapping-activity-log",
        "runId": "post-fix",
        "hypothesisId": "B,E",
        "location": "WorkspaceViewController.appendActivity",
        "msg": "[DEBUG] Activity line appended",
        "data": [
          "lineCount": activityLines.count,
          "message": message,
          "textCharacters": activityTextView.string.count,
          "textWidth": activityTextView.frame.width,
          "textHeight": activityTextView.frame.height,
        ],
      ])
    {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      URLSession.shared.uploadTask(with: request, from: body).resume()
    }
    // #endregion
  }

  private func recordActivity(_ message: String) {
    appendActivity("\(Self.activityTimestamp.string(from: Date()))  \(message)")
  }

  private static let activityTimestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  @objc private func revealActivityLog() {
    guard FileManager.default.fileExists(atPath: activityLogStore.storageURL.path) else {
      NSSound.beep()
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([activityLogStore.storageURL])
  }

  @objc private func refreshDevices() {
    guard activeWriteProfile == nil else { return }
    didAutoConnect = false
    bluetooth.refresh()
  }

  @objc private func deviceSelectionChanged(_ sender: NSPopUpButton) {
    guard !bluetooth.isBusy, activeWriteProfile == nil else { return }
    guard let value = sender.selectedItem?.representedObject as? String,
      let id = UUID(uuidString: value),
      let device = bluetooth.devices.first(where: { $0.id == id })
    else {
      return
    }
    profileStore.bindSelectedProfile(
      deviceIdentifier: device.id,
      deviceName: device.name,
      keyCount: device.inferredKeyCount
    )
    bluetooth.connect(deviceID: id)
  }

  @objc private func destinationChanged(_ sender: NSButton) {
    guard let destination = Destination(rawValue: sender.tag) else { return }
    showDestination(destination)
  }

  @objc private func openDeviceSettings() {
    showDestination(.settings)
  }

  @objc private func previousLayer() {
    selectedLayer = selectedLayer == 1 ? 10 : selectedLayer - 1
    adoptCategoryFromCurrentAssignment()
    refreshUI()
  }

  @objc private func nextLayer() {
    selectedLayer = selectedLayer == 10 ? 1 : selectedLayer + 1
    adoptCategoryFromCurrentAssignment()
    refreshUI()
  }

  @objc private func layerChanged(_ sender: NSPopUpButton) {
    selectedLayer = sender.selectedTag()
    adoptCategoryFromCurrentAssignment()
    refreshUI()
  }

  @objc private func categoryChanged(_ sender: NSSegmentedControl) {
    recorderView.cancelRecording()
    actionPopover?.close()
    selectedCategory = ActionCategory.allCases[sender.selectedSegment]
    updateCategoryVisibility()
  }

  @objc private func clearSelectedMapping() {
    clearCurrentAssignment(actionName: "清空按键映射")
  }

  @objc private func copyMapping(_ sender: NSPopUpButton) {
    sender.selectItem(at: 0)
  }

  @objc private func copyMappingToKey(_ sender: NSMenuItem) {
    guard profileStore.canEdit else { return }
    guard let assignment = currentAssignment else {
      NSSound.beep()
      return
    }
    let target = MappingAddress(layer: selectedLayer, key: sender.tag)
    let oldValue = profileStore.selectedProfile.assignment(at: target)
    registerUndo(oldValue, at: target, actionName: "复制按键映射")
    profileStore.updateSelectedProfile {
      $0.setAssignment(assignment, at: target)
    }
    recordActivity(
      "本地复制 · 第 \(selectedLayer) 层 · 按键 \(selectedKey) → 按键 \(target.key) · "
        + XKeyProtocol.displayName(for: assignment))
  }

  @objc private func copyLayer(_ sender: NSMenuItem) {
    let targetLayer = sender.tag
    guard targetLayer != selectedLayer else { return }
    let profile = profileStore.selectedProfile
    var sourceAssignments: [Int: KeyAssignment] = [:]
    for key in 1...profile.keyCount {
      let source = MappingAddress(layer: selectedLayer, key: key)
      sourceAssignments[key] = profile.assignment(at: source)
    }
    replaceLayer(targetLayer, with: sourceAssignments, actionName: "复制设备层")
  }

  private func replaceLayer(
    _ layer: Int,
    with assignments: [Int: KeyAssignment],
    actionName: String
  ) {
    guard profileStore.canEdit else { return }
    let profile = profileStore.selectedProfile
    var oldAssignments: [Int: KeyAssignment] = [:]
    for key in 1...profile.keyCount {
      oldAssignments[key] = profile.assignment(at: MappingAddress(layer: layer, key: key))
    }
    history.registerUndo(withTarget: self) { target in
      target.replaceLayer(layer, with: oldAssignments, actionName: actionName)
    }
    history.setActionName(actionName)
    profileStore.updateSelectedProfile { value in
      for key in 1...value.keyCount {
        value.setAssignment(assignments[key], at: MappingAddress(layer: layer, key: key))
      }
    }
    recordActivity("本地复制 · 第 \(selectedLayer) 层 → 第 \(layer) 层")
  }

  @objc private func sleepTimeoutChanged(_ sender: NSPopUpButton) {
    let raw = sender.selectedItem?.representedObject as? Int
    let timeout = raw.flatMap { SleepTimeout(rawValue: UInt8($0)) }
    changeSleep(timeout ?? profileStore.selectedProfile.sleepTimeout, enabled: timeout != nil)
  }

  private func changeSleep(_ timeout: SleepTimeout, enabled: Bool) {
    guard profileStore.canEdit else { return }
    let profile = profileStore.selectedProfile
    history.registerUndo(withTarget: self) { target in
      target.changeSleep(profile.sleepTimeout, enabled: profile.shouldManageSleep)
    }
    history.setActionName("更改休眠时间")
    profileStore.updateSelectedProfile {
      $0.sleepTimeout = timeout
      $0.managesSleep = enabled
    }
    let detail = enabled ? timeout.title : "保持设备现有设置"
    recordActivity("本地修改 · 自动休眠 → \(detail)")
  }

  @objc private func keyCountChanged(_ sender: NSPopUpButton) {
    let count = sender.selectedTag()
    guard count > 0 else { return }
    let oldCount = profileStore.selectedProfile.keyCount
    guard oldCount != count else { return }
    profileStore.updateSelectedProfile { $0.keyCount = count }
    recordActivity("本地修改 · 实体按键数量 \(oldCount) → \(count)")
  }

  @objc private func toggleAdvanced(_ sender: NSButton) {
    protocolLabel.isHidden = sender.state != .on
  }

  @objc private func toggleKeyboard(_ sender: NSButton) {
    keyboardExpanded = sender.state == .on
    keyboardSection.isHidden = !keyboardExpanded
  }

  @objc private func mappingDoubleClicked() {
    guard mappingTable.clickedRow >= 0 else { return }
    beginRecordingSelectedMapping()
  }

  private func beginRecordingSelectedMapping() {
    guard profileStore.canEdit, mappingTable.selectedRow >= 0 else { return }
    actionPopover?.close()
    selectedCategory = .keyboard
    updateCategoryVisibility()
    view.layoutSubtreeIfNeeded()
    recorderView.scrollToVisible(recorderView.bounds)
    recorderView.startRecording()
  }

  @objc private func openActionSearch() {
    guard profileStore.canEdit, view.window != nil else { return }
    if actionPopover?.isShown == true {
      actionPopover?.close()
      return
    }
    recorderView.cancelRecording()
    let profileID = profileStore.selectedProfile.id
    let address = currentAddress
    let picker = ActionPickerViewController(
      category: selectedCategory, selectedActionID: currentAssignment?.actionID)
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = false
    popover.contentViewController = picker
    picker.onCancel = { [weak popover] in popover?.close() }
    picker.onSelected = { [weak self, weak popover] action in
      guard let self, self.profileStore.canEdit,
        self.profileStore.selectedProfile.id == profileID, self.currentAddress == address
      else {
        popover?.close()
        return
      }
      popover?.close()
      self.selectedCategory = action.category
      self.assign(action: action, modifiers: self.keyboardView.activeModifiers)
      self.updateCategoryVisibility()
    }
    actionPopover = popover
    popover.show(
      relativeTo: actionSearchButton.bounds, of: actionSearchButton, preferredEdge: .maxY)
  }

  @objc private func inspectReadback() {
    bluetooth.inspectReadback()
  }

  @objc private func disconnectDevice() {
    guard activeWriteProfile == nil else { return }
    bluetooth.disconnect()
  }

  @objc private func applyChanges() {
    guard activeWriteProfile == nil, bluetooth.canWrite, profileStore.canApplyToDevice else {
      return
    }
    if let id = bluetooth.connectedDeviceID,
      let device = bluetooth.devices.first(where: { $0.id == id }),
      profileStore.selectedProfile.deviceIdentifier != id
    {
      profileStore.bindSelectedProfile(
        deviceIdentifier: id, deviceName: device.name, keyCount: device.inferredKeyCount)
    }
    guard profileStore.canApplyToDevice else { return }
    do {
      let snapshot = profileStore.selectedProfile
      let commands = try XKeyProtocol.commands(for: snapshot)
      guard !commands.isEmpty else { return }
      if !bluetooth.isDemoMode, let window = view.window {
        let alert = NSAlert()
        alert.messageText = "向设备写入 \(commands.count) 项更改？"
        alert.informativeText =
          "设备当前配置尚未读回。以下项目会覆盖设备现有值：\n\n"
          + commands.prefix(12).map(\.label).joined(separator: "\n")
          + (commands.count > 12 ? "\n其余 \(commands.count - 12) 项" : "")
        alert.addButton(withTitle: "写入设备")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
          if response == .alertFirstButtonReturn { self?.send(commands, snapshot: snapshot) }
        }
      } else {
        send(commands, snapshot: snapshot)
      }
    } catch {
      showError(title: "无法生成写入命令", message: error.localizedDescription)
    }
  }

  private func send(_ commands: [XKeyCommand], snapshot: DeviceProfile) {
    guard activeWriteProfile == nil, bluetooth.canWrite,
      profileStore.canApplyToDevice,
      snapshot.deviceIdentifier == bluetooth.connectedDeviceID
    else { return }
    lastWriteMessage = "准备写入 \(commands.count) 项更改"
    lastWriteProfileID = snapshot.id
    lastWriteDeviceID = snapshot.deviceIdentifier
    activeWriteProfile = snapshot
    if !bluetooth.send(commands) {
      activeWriteProfile = nil
      NSSound.beep()
    }
    refreshUI()
  }

  @objc func undo(_ sender: Any?) {
    guard history.canUndo else { return }
    let actionName = history.undoActionName
    history.undo()
    recordActivity("本地撤销 · \(actionName)")
    refreshUI()
  }

  @objc func redo(_ sender: Any?) {
    guard history.canRedo else { return }
    let actionName = history.redoActionName
    history.redo()
    recordActivity("本地重做 · \(actionName)")
    refreshUI()
  }

  @objc private func profileMenuChanged(_ sender: NSPopUpButton) {
    sender.selectItem(withTitle: profileStore.selectedProfile.name)
  }

  @objc private func selectProfile(_ sender: NSMenuItem) {
    guard let value = sender.representedObject as? String,
      let id = UUID(uuidString: value)
    else {
      return
    }
    do {
      try profileStore.selectProfile(id: id)
      selectedLayer = 1
      selectedKey = 1
      adoptCategoryFromCurrentAssignment()
      refreshUI()
    } catch {
      showError(title: "无法切换方案", message: error.localizedDescription)
    }
  }

  @objc private func profileCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    switch command {
    case "new":
      _ = profileStore.createProfile()
    case "duplicate":
      _ = profileStore.duplicateSelectedProfile()
    case "rename":
      renameProfile()
    case "delete":
      confirmDeleteProfile()
    case "import":
      importProfile()
    case "export":
      exportProfile()
    default:
      break
    }
  }

  private func renameProfile() {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "重命名方案"
    alert.informativeText = "为当前本地方案输入一个容易识别的名称。"
    alert.addButton(withTitle: "重命名")
    alert.addButton(withTitle: "取消")
    let input = NSTextField(string: profileStore.selectedProfile.name)
    input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
    alert.accessoryView = input
    alert.beginSheetModal(for: window) { [weak self] response in
      if response == .alertFirstButtonReturn {
        self?.profileStore.renameSelectedProfile(to: input.stringValue)
      }
    }
  }

  private func confirmDeleteProfile() {
    guard let window = view.window else { return }
    let profileName = profileStore.selectedProfile.name
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "删除“\(profileName)”？"
    alert.informativeText = "此操作会删除该方案中的全部本地键位配置。"
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")
    alert.buttons.first?.hasDestructiveAction = true
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      do {
        try self?.profileStore.deleteSelectedProfile()
      } catch {
        self?.showError(title: "无法删除方案", message: error.localizedDescription)
      }
    }
  }

  private func importProfile() {
    guard let window = view.window else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      do {
        _ = try self?.profileStore.importProfiles(from: url)
      } catch {
        self?.showError(title: "无法导入方案", message: error.localizedDescription)
      }
    }
  }

  private func exportProfile() {
    guard let window = view.window else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "\(profileStore.selectedProfile.name).blekey.json"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try self?.profileStore.exportSelectedProfile(to: url)
      } catch {
        self?.showError(title: "无法导出方案", message: error.localizedDescription)
      }
    }
  }

  private func showError(title: String, message: String) {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "好")
    alert.beginSheetModal(for: window)
  }
}

extension WorkspaceViewController: NSTableViewDataSource, NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    StudioTableRow()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    profileStore.selectedProfile.keyCount
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let profile = profileStore.selectedProfile
    let address = MappingAddress(layer: selectedLayer, key: row + 1)
    let assignment = profile.assignment(at: address)
    let dirty = profile.dirtyAddresses.contains(address)
    let text: String
    let color: NSColor
    switch tableColumn?.identifier.rawValue {
    case "key":
      text = "按键 \(row + 1)"
      color = AppTheme.text
    case "device":
      text = "未读取"
      color = AppTheme.secondaryText
    case "local":
      text =
        assignment.map { XKeyProtocol.displayName(for: $0) }
        ?? (dirty ? "清空映射" : "保持设备原值")
      color = AppTheme.text
    default:
      text =
        dirty ? "待写入" : (assignment == nil ? "未修改" : (bluetooth.isDemoMode ? "演示已发送" : "已发送，未读回"))
      color = dirty ? AppTheme.pending : AppTheme.secondaryText
    }
    let label = NSTextField.label(
      text,
      font: .systemFont(
        ofSize: 13, weight: tableColumn?.identifier.rawValue == "local" ? .semibold : .medium),
      color: color)
    label.maximumNumberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    label.toolTip =
      tableColumn?.identifier.rawValue == "device"
      ? "未取得设备配置。上次发送的本地记录不代表设备当前值。" : text
    let cell = NSTableCellView()
    cell.addSubview(label)
    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6).isActive = true
    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
    cell.textField = label
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isRefreshingTable, mappingTable.selectedRow >= 0 else { return }
    selectedKey = mappingTable.selectedRow + 1
    view.window?.makeFirstResponder(mappingTable)
    adoptCategoryFromCurrentAssignment()
    refreshUI()
  }
}

private final class FlippedContentView: NSView {
  override var isFlipped: Bool { true }
}

final class MappingTableView: NSTableView {
  var onRecord: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    if [36, 76].contains(event.keyCode),
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    {
      onRecord?()
    } else {
      super.keyDown(with: event)
    }
  }
}

private final class SeparatorView: NSView {
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 1)
  }

  override func draw(_ dirtyRect: NSRect) {
    AppTheme.hairline.setFill()
    dirtyRect.fill()
  }
}

extension ActionCategory {
  fileprivate var rawValueIndex: Int {
    ActionCategory.allCases.firstIndex(of: self) ?? 0
  }
}

extension String {
  fileprivate var groupedHex: String {
    stride(from: 0, to: count, by: 2).map { offset in
      let start = index(startIndex, offsetBy: offset)
      let end = index(start, offsetBy: min(2, distance(from: start, to: endIndex)))
      return String(self[start..<end])
    }.joined(separator: " ")
  }
}
