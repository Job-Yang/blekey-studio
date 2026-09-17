import AppKit

enum ActionSearch {
  static func results(for query: String, category: ActionCategory) -> [KeyAction] {
    let normalized = query.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return ActionCatalog.actions(in: category) }
    let terms = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
    return ActionCatalog.all.filter { action in
      let text = [
        action.name, action.keycap, action.id, action.category.title, aliases[action.id] ?? "",
      ]
      .joined(separator: " ")
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      return terms.allSatisfy { text.contains($0) }
    }.sorted { first, second in
      let firstExact =
        first.name.lowercased() == normalized || first.keycap.lowercased() == normalized
      let secondExact =
        second.name.lowercased() == normalized || second.keycap.lowercased() == normalized
      if firstExact != secondExact { return firstExact }
      return ActionCatalog.all.firstIndex(of: first)! < ActionCatalog.all.firstIndex(of: second)!
    }
  }

  private static let aliases: [String: String] = [
    "key.return": "enter 回车",
    "key.escape": "esc 退出键",
    "key.space": "spacebar 空格键",
    "key.tab": "制表",
    "key.pageUp": "page up pgup 上翻页",
    "key.pageDown": "page down pgdn 下翻页",
    "key.deleteBackward": "backspace delete 退格",
    "key.deleteForward": "forward delete del",
    "key.printScreen": "print screen screenshot 屏幕截图",
    "key.capsLock": "caps lock 大写锁定",
    "media.volumeUp": "volume up 音量加",
    "media.volumeDown": "volume down 音量减",
    "media.playPause": "play pause 播放 暂停",
  ]
}

final class ActionPickerViewController: NSViewController, NSSearchFieldDelegate,
  NSTableViewDataSource, NSTableViewDelegate
{
  let searchField = NSSearchField()
  let table = NSTableView()
  private let emptyLabel = NSTextField.label("没有匹配的动作", color: .secondaryLabelColor)
  private(set) var results: [KeyAction] = []
  var onSelected: ((KeyAction) -> Void)?
  var onCancel: (() -> Void)?
  private let category: ActionCategory
  private let selectedActionID: String?

  init(category: ActionCategory, selectedActionID: String?) {
    self.category = category
    self.selectedActionID = selectedActionID
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    view = StudioSurface(AppTheme.panelBackground)
    view.appearance = NSAppearance(named: .darkAqua)
    preferredContentSize = NSSize(width: 340, height: 342)
    view.setFrameSize(preferredContentSize)
    searchField.placeholderString = "搜索动作"
    searchField.font = .systemFont(ofSize: 14, weight: .medium)
    searchField.identifier = NSUserInterfaceItemIdentifier("actionSearch")
    searchField.setAccessibilityLabel("搜索映射动作")
    searchField.sendsSearchStringImmediately = true
    searchField.sendsWholeSearchString = false
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(searchChanged)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
    column.width = 310
    table.addTableColumn(column)
    table.headerView = nil
    table.backgroundColor = AppTheme.panelBackground
    table.rowHeight = 38
    table.intercellSpacing = NSSize(width: 0, height: 0)
    table.focusRingType = .none
    table.style = .plain
    table.identifier = NSUserInterfaceItemIdentifier("actionSearchResults")
    table.setAccessibilityLabel("匹配动作")
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.action = #selector(chooseAction)
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    let stack = NSStackView.vertical(spacing: 8)
    stack.distribution = .fill
    stack.addArrangedSubview(searchField)
    stack.addArrangedSubview(scroll)
    view.addSubview(stack)
    stack.pinEdges(to: view, insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
    searchField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    searchField.heightAnchor.constraint(equalToConstant: 28).isActive = true
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    view.addSubview(emptyLabel)
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
      emptyLabel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 22),
    ])
    reloadResults(selecting: selectedActionID)
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.makeFirstResponder(searchField)
  }

  func controlTextDidChange(_ notification: Notification) {
    reloadResults()
  }

  @objc private func searchChanged() {
    reloadResults()
  }

  private func reloadResults(selecting id: String? = nil) {
    results = ActionSearch.results(for: searchField.stringValue, category: category)
    table.reloadData()
    emptyLabel.isHidden = !results.isEmpty
    if results.isEmpty {
      table.deselectAll(nil)
    } else {
      let row = id.flatMap { value in results.firstIndex(where: { $0.id == value }) } ?? 0
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      table.scrollRowToVisible(row)
    }
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(by: 1)
    case #selector(NSResponder.moveUp(_:)):
      moveSelection(by: -1)
    case #selector(NSResponder.insertNewline(_:)):
      chooseAction()
    case #selector(NSResponder.cancelOperation(_:)):
      onCancel?()
    default:
      return false
    }
    return true
  }

  private func moveSelection(by delta: Int) {
    guard !results.isEmpty else { return }
    let row = min(results.count - 1, max(0, table.selectedRow + delta))
    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    table.scrollRowToVisible(row)
  }

  @objc private func chooseAction() {
    guard results.indices.contains(table.selectedRow) else { return }
    onSelected?(results[table.selectedRow])
  }

  func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    StudioTableRow()
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let action = results[row]
    let name = NSTextField.label(action.name, font: .systemFont(ofSize: 13, weight: .semibold))
    name.lineBreakMode = .byTruncatingTail
    let categoryLabel = NSTextField.label(
      action.category.title, font: .systemFont(ofSize: 12, weight: .medium),
      color: .secondaryLabelColor)
    categoryLabel.setContentHuggingPriority(.required, for: .horizontal)
    let icon = NSImageView(image: AppTheme.symbol(action.symbolName ?? "keyboard") ?? NSImage())
    icon.contentTintColor = AppTheme.secondaryText
    icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
    let rowView = NSStackView.horizontal(spacing: 8)
    rowView.distribution = .fill
    rowView.addArrangedSubview(icon)
    rowView.addArrangedSubview(name)
    rowView.addArrangedSubview(categoryLabel)
    name.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let cell = NSTableCellView()
    cell.addSubview(rowView)
    rowView.pinEdges(to: cell, insets: NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8))
    cell.textField = name
    return cell
  }
}
