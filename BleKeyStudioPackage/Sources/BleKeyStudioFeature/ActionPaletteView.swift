import AppKit

final class ActionPaletteView: NSView {
  var onActionSelected: ((KeyAction) -> Void)?

  var category: ActionCategory = .media {
    didSet { reload() }
  }
  var selectedActionID: String? {
    didSet { reloadSelection() }
  }

  private let scrollView = NSScrollView()
  private let collectionView = NSCollectionView()
  private var actions: [KeyAction] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    let layout = NSCollectionViewFlowLayout()
    layout.itemSize = NSSize(width: 138, height: 60)
    layout.minimumInteritemSpacing = 10
    layout.minimumLineSpacing = 10
    layout.sectionInset = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

    collectionView.collectionViewLayout = layout
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.isSelectable = true
    collectionView.backgroundColors = [.clear]
    collectionView.register(
      ActionCollectionItem.self,
      forItemWithIdentifier: ActionCollectionItem.identifier
    )

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = collectionView
    addSubview(scrollView)
    scrollView.pinEdges(to: self)

    reload()
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func reload() {
    actions = ActionCatalog.actions(in: category)
    collectionView.reloadData()
    reloadSelection()
  }

  private func reloadSelection() {
    collectionView.deselectAll(nil)
    guard let selectedActionID,
      let index = actions.firstIndex(where: { $0.id == selectedActionID })
    else {
      return
    }
    collectionView.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])
  }
}

extension ActionPaletteView: NSCollectionViewDataSource, NSCollectionViewDelegate {
  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int
  {
    actions.count
  }

  func collectionView(
    _ collectionView: NSCollectionView,
    itemForRepresentedObjectAt indexPath: IndexPath
  ) -> NSCollectionViewItem {
    let item =
      collectionView.makeItem(
        withIdentifier: ActionCollectionItem.identifier,
        for: indexPath
      ) as! ActionCollectionItem
    item.actionValue = actions[indexPath.item]
    return item
  }

  func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
  ) {
    guard let index = indexPaths.first?.item, actions.indices.contains(index) else { return }
    onActionSelected?(actions[index])
  }
}

private final class ActionCollectionItem: NSCollectionViewItem {
  static let identifier = NSUserInterfaceItemIdentifier("ActionCollectionItem")

  var actionValue: KeyAction? {
    didSet { updateContent() }
  }

  private let iconView = NSImageView()
  private let titleLabel = NSTextField.label(
    "",
    font: .systemFont(ofSize: 13, weight: .semibold)
  )
  override var isSelected: Bool {
    didSet { updateAppearance() }
  }

  override func loadView() {
    view = NSView()
    view.wantsLayer = true
    view.layer?.cornerRadius = 7
    view.layer?.borderWidth = 1

    iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
    iconView.contentTintColor = AppTheme.secondaryText
    iconView.translatesAutoresizingMaskIntoConstraints = false

    let textStack = NSStackView.vertical(spacing: 2)
    textStack.addArrangedSubview(titleLabel)

    let row = NSStackView.horizontal(spacing: 10)
    row.addArrangedSubview(iconView)
    row.addArrangedSubview(textStack)
    row.alignment = .centerY
    view.addSubview(row)
    row.pinEdges(to: view, insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 22),
      iconView.heightAnchor.constraint(equalToConstant: 22),
    ])
    updateAppearance()
  }

  private func updateContent() {
    guard isViewLoaded, let actionValue else { return }
    titleLabel.stringValue = actionValue.name
    iconView.image = AppTheme.symbol(
      actionValue.symbolName ?? "keyboard",
      accessibilityDescription: actionValue.name
    )
    view.setAccessibilityRole(.button)
    view.setAccessibilityLabel(actionValue.name)
  }

  private func updateAppearance() {
    guard isViewLoaded else { return }
    view.layer?.backgroundColor =
      (isSelected ? AppTheme.accentFill : AppTheme.controlBottom).cgColor
    view.layer?.borderColor = (isSelected ? AppTheme.accent : AppTheme.hairline).cgColor
    view.layer?.borderWidth = 1
    iconView.contentTintColor = isSelected ? AppTheme.accent : AppTheme.secondaryText
  }
}
