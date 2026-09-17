import AppKit
import Foundation
import Testing

@testable import BleKeyStudioFeature

@Test func encodesKeyboardMappingWithModifiers() throws {
  let command = try XKeyProtocol.mappingCommand(
    address: MappingAddress(layer: 1, key: 5),
    assignment: KeyAssignment(
      actionID: "key.b",
      modifiers: [.leftControl, .leftShift]
    )
  )

  #expect(Array(command.bytes) == [0x01, 0x05, 0x03, 0x05])
  #expect(command.hex == "01050305")
}

@Test func encodesLayerTenAndHighestSupportedKey() throws {
  let command = try XKeyProtocol.mappingCommand(
    address: MappingAddress(layer: 10, key: 24),
    assignment: KeyAssignment(
      actionID: "key.k",
      modifiers: [.rightCommand]
    )
  )

  #expect(Array(command.bytes) == [0x10, 0x18, 0x80, 0x0E])
}

@Test func encodesModifierOnlyMappingWithoutAKeyCode() throws {
  let assignment = KeyAssignment(
    actionID: ActionCatalog.modifierOnly.id,
    modifiers: [.rightOption])
  let command = try XKeyProtocol.mappingCommand(
    address: MappingAddress(layer: 1, key: 3),
    assignment: assignment)

  #expect(Array(command.bytes) == [0x01, 0x03, 0x40, 0x00])
  #expect(XKeyProtocol.displayName(for: assignment) == "⌥")
  #expect(throws: XKeyProtocolError.modifierRequired) {
    try XKeyProtocol.mappingCommand(
      address: MappingAddress(layer: 1, key: 3),
      assignment: KeyAssignment(actionID: ActionCatalog.modifierOnly.id))
  }
}

@Test func encodesPointerAndMediaFamilies() throws {
  let pointer = try XKeyProtocol.mappingCommand(
    address: MappingAddress(layer: 1, key: 1),
    assignment: KeyAssignment(actionID: "pointer.leftClick")
  )
  let media = try XKeyProtocol.mappingCommand(
    address: MappingAddress(layer: 1, key: 2),
    assignment: KeyAssignment(actionID: "media.volumeUp")
  )

  #expect(Array(pointer.bytes) == [0x01, 0x01, 0xFE, 0x01])
  #expect(Array(media.bytes) == [0x01, 0x02, 0xFD, 0xE9])
}

@Test func encodesEverySupportedSleepTimeout() {
  for timeout in SleepTimeout.allCases {
    let command = XKeyProtocol.sleepCommand(timeout)
    #expect(Array(command.bytes) == [0xFF, 0xFF, 0xFF, timeout.rawValue])
  }
}

@Test func rejectsOutOfRangeAddresses() {
  #expect(throws: XKeyProtocolError.unsupportedLayer(11)) {
    try XKeyProtocol.mappingCommand(
      address: MappingAddress(layer: 11, key: 1),
      assignment: nil
    )
  }
  #expect(throws: XKeyProtocolError.unsupportedKey(25)) {
    try XKeyProtocol.mappingCommand(
      address: MappingAddress(layer: 1, key: 25),
      assignment: nil
    )
  }
}

@Test func tracksOnlyMappingsThatDifferFromLastSentState() {
  let address = MappingAddress(layer: 1, key: 2)
  let assignment = KeyAssignment(actionID: "key.k", modifiers: [.leftCommand])
  var profile = DeviceProfile()

  profile.setAssignment(assignment, at: address)
  #expect(profile.dirtyAddresses == [address])

  profile.markSent(at: address)
  #expect(profile.dirtyAddresses.isEmpty)

  profile.setAssignment(nil, at: address)
  #expect(profile.dirtyAddresses == [address])
}

@Test func profileLibraryPersistsAndReloads() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let url = root.appendingPathComponent("profiles.json")

  let store = ProfileStore(storageURL: url)
  store.renameSelectedProfile(to: "阅读")
  store.updateSelectedProfile {
    $0.sleepTimeout = SleepTimeout.oneHour
  }

  let reloaded = ProfileStore(storageURL: url)
  #expect(reloaded.selectedProfile.name == "阅读")
  #expect(reloaded.selectedProfile.sleepTimeout == SleepTimeout.oneHour)
}

@Test func actionCatalogHasStableUniqueIdentifiers() {
  let identifiers = ActionCatalog.all.map(\.id)
  #expect(Set(identifiers).count == identifiers.count)
  #expect(ActionCatalog.action(id: "key.k")?.code == 0x0E)
  #expect(ActionCatalog.action(id: "media.volumeUp")?.code == 0xE9)
}

@Test func commandBatchContainsOnlyPendingValues() throws {
  let sentAddress = MappingAddress(layer: 1, key: 1)
  let pendingAddress = MappingAddress(layer: 2, key: 3)
  let sent = KeyAssignment(actionID: "key.a")
  let pending = KeyAssignment(actionID: "media.playPause")
  var profile = DeviceProfile(
    mappings: [
      MappingRecord(address: sentAddress, assignment: sent),
      MappingRecord(address: pendingAddress, assignment: pending),
    ],
    lastSentMappings: [
      MappingRecord(address: sentAddress, assignment: sent)
    ],
    sleepTimeout: .tenMinutes,
    lastSentSleepTimeout: .tenMinutes
  )

  var commands = try XKeyProtocol.commands(for: profile)
  #expect(commands.count == 1)
  #expect(commands[0].target == .mapping(pendingAddress))

  profile.sleepTimeout = .oneHour
  commands = try XKeyProtocol.commands(for: profile)
  #expect(commands.count == 2)
  #expect(commands.last?.target == .sleep)
}

@Test @MainActor func demoTransportCompletesAWriteBatch() async {
  let controller = BluetoothController(demoMode: true)
  let commands = [
    XKeyProtocol.sleepCommand(.fiveMinutes),
    XKeyProtocol.sleepCommand(.tenMinutes),
  ]
  var completed = 0

  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    controller.onCommandResult = { _, result in
      if case .success = result {
        completed += 1
      }
    }
    controller.onBatchFinished = {
      continuation.resume()
    }
    #expect(controller.send(commands))
  }

  #expect(completed == 2)
  #expect(controller.canWrite)
}

@Test func translatesARealMacShortcutIntoAnAssignment() throws {
  let event = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command, .shift],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "K",
      charactersIgnoringModifiers: "k",
      isARepeat: false,
      keyCode: 40
    )
  )

  #expect(ActionCatalog.keyboardAction(for: event)?.id == "key.k")
  #expect(
    ActionCatalog.modifiers(for: event)
      == Set([KeyModifier.leftCommand, KeyModifier.leftShift])
  )
}

@Test func exportsAndImportsAProfileWithoutTrustingSentState() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let store = ProfileStore(storageURL: root.appendingPathComponent("library.json"))
  store.renameSelectedProfile(to: "演示")
  store.updateSelectedProfile {
    let address = MappingAddress(layer: 3, key: 2)
    $0.setAssignment(KeyAssignment(actionID: "pointer.leftClick"), at: address)
    $0.markSent(at: address)
  }

  let exportURL = root.appendingPathComponent("export.blekey.json")
  try store.exportSelectedProfile(to: exportURL)

  let importedStore = ProfileStore(storageURL: root.appendingPathComponent("other.json"))
  let imported = try importedStore.importProfile(from: exportURL)
  #expect(imported.name == "演示")
  #expect(imported.lastSentMappings.isEmpty)
  #expect(imported.dirtyAddresses == [MappingAddress(layer: 3, key: 2)])
}
