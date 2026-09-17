import Foundation
import Testing

@testable import BleKeyStudioFeature

@Suite struct InteractionModelTests {
  @Test(arguments: [
    (" Page ", ["key.pageUp", "key.pageDown"]),
    ("PAGE UP", ["key.pageUp"]),
    ("F12", ["key.f12"]),
    ("pgdn", ["key.pageDown"]),
    ("ENTER", ["key.return"]),
    ("esc", ["key.escape"]),
    ("backspace", ["key.deleteBackward"]),
    ("volume up", ["media.volumeUp"]),
    ("\u{97f3}\u{91cf}", ["media.volumeUp", "media.volumeDown"]),
    ("no-action-with-this-name", []),
  ])
  func searchesAllCategoriesUsingNamesAndAliases(query: String, expected: [String]) {
    #expect(ActionSearch.results(for: query, category: .system).map(\.id) == expected)
  }

  @Test func emptyQueriesRespectCategoryAndResultsStayStable() {
    for category in ActionCategory.allCases {
      #expect(
        ActionSearch.results(for: "  \n", category: category) == ActionCatalog.actions(in: category)
      )
    }
    #expect(ActionSearch.results(for: "a", category: .keyboard).first?.id == "key.a")
    let results = ActionSearch.results(for: "play", category: .system)
    #expect(Set(results.map(\.id)).count == results.count)
    #expect(results == ActionSearch.results(for: "play", category: .system))
  }

  @Test func savedStateRequiresActualReadOrWriteAndSurvivesFailure() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let parent = root.appendingPathComponent("storage")
    let file = parent.appendingPathComponent("library.json")
    let store = ProfileStore(storageURL: file)
    #expect(!store.hasSavedLibrary)
    #expect(!store.hasUnsavedChanges)
    store.renameSelectedProfile(to: "Saved")
    #expect(store.hasSavedLibrary)
    #expect(ProfileStore(storageURL: file).hasSavedLibrary)

    let backup = root.appendingPathComponent("backup")
    try FileManager.default.moveItem(at: parent, to: backup)
    try Data("obstruction".utf8).write(to: parent)
    store.renameSelectedProfile(to: "Draft")
    #expect(store.hasSavedLibrary)
    #expect(store.hasUnsavedChanges)
    #expect(!store.canApplyToDevice)
    #expect(!store.retryPersistence())
    try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("obstruction"))
    try FileManager.default.moveItem(at: backup, to: parent)
    #expect(store.retryPersistence())
    #expect(!store.hasUnsavedChanges)
    #expect(ProfileStore(storageURL: file).selectedProfile.name == "Draft")

    try Data("corrupt".utf8).write(to: file)
    let broken = ProfileStore(storageURL: file)
    #expect(!broken.hasSavedLibrary)
    #expect(!broken.canEdit)
    #expect(!broken.retryPersistence())
    try store.encodeLibrary().write(to: file)
    #expect(broken.retryPersistence())
    #expect(broken.hasSavedLibrary)
  }
}
