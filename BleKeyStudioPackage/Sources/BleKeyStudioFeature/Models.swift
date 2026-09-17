import Foundation

public enum ActionCategory: String, Codable, CaseIterable, Sendable {
  case keyboard
  case media
  case pointer
  case system

  var title: String {
    switch self {
    case .keyboard: "键盘"
    case .media: "媒体"
    case .pointer: "鼠标"
    case .system: "系统"
    }
  }
}

public enum KeyModifier: UInt8, Codable, CaseIterable, Sendable {
  case leftControl = 0x01
  case leftShift = 0x02
  case leftOption = 0x04
  case leftCommand = 0x08
  case rightControl = 0x10
  case rightShift = 0x20
  case rightOption = 0x40
  case rightCommand = 0x80

  var displayName: String {
    switch self {
    case .leftControl, .rightControl: "⌃"
    case .leftShift, .rightShift: "⇧"
    case .leftOption, .rightOption: "⌥"
    case .leftCommand, .rightCommand: "⌘"
    }
  }

  var accessibilityName: String {
    switch self {
    case .leftControl: "左 Control"
    case .leftShift: "左 Shift"
    case .leftOption: "左 Option"
    case .leftCommand: "左 Command"
    case .rightControl: "右 Control"
    case .rightShift: "右 Shift"
    case .rightOption: "右 Option"
    case .rightCommand: "右 Command"
    }
  }

  static func normalized(_ modifiers: Set<KeyModifier>) -> [KeyModifier] {
    modifiers.sorted { $0.rawValue < $1.rawValue }
  }
}

public struct KeyAction: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let keycap: String
  public let detail: String?
  public let code: UInt8
  public let category: ActionCategory
  public let symbolName: String?

  public init(
    id: String,
    name: String,
    keycap: String,
    detail: String? = nil,
    code: UInt8,
    category: ActionCategory,
    symbolName: String? = nil
  ) {
    self.id = id
    self.name = name
    self.keycap = keycap
    self.detail = detail
    self.code = code
    self.category = category
    self.symbolName = symbolName
  }
}

public struct KeyAssignment: Codable, Hashable, Sendable {
  public let actionID: String
  public let modifiers: [KeyModifier]

  public init(actionID: String, modifiers: Set<KeyModifier> = []) {
    self.actionID = actionID
    self.modifiers = KeyModifier.normalized(modifiers)
  }

  public var modifierSet: Set<KeyModifier> {
    Set(modifiers)
  }
}

public struct MappingAddress: Codable, Hashable, Sendable {
  public let layer: Int
  public let key: Int

  public init(layer: Int, key: Int) {
    self.layer = layer
    self.key = key
  }
}

public struct MappingRecord: Codable, Hashable, Sendable {
  public let address: MappingAddress
  public let assignment: KeyAssignment

  public init(address: MappingAddress, assignment: KeyAssignment) {
    self.address = address
    self.assignment = assignment
  }
}

public enum SleepTimeout: UInt8, Codable, CaseIterable, Sendable {
  case never = 0x00
  case oneMinute = 0x01
  case fiveMinutes = 0x05
  case tenMinutes = 0x0A
  case thirtyMinutes = 0x1E
  case oneHour = 0x3C
  case threeHours = 0xB4
  case fourHours = 0xFF

  public var title: String {
    switch self {
    case .never: "不休眠"
    case .oneMinute: "1 分钟"
    case .fiveMinutes: "5 分钟"
    case .tenMinutes: "10 分钟"
    case .thirtyMinutes: "30 分钟"
    case .oneHour: "1 小时"
    case .threeHours: "3 小时"
    case .fourHours: "4 小时"
    }
  }
}

public struct DeviceProfile: Codable, Identifiable, Hashable, Sendable {
  public var documentVersion: Int? = 1
  public var id: UUID
  public var name: String
  public var deviceIdentifier: UUID?
  public var deviceName: String?
  public var keyCount: Int
  public var mappings: [MappingRecord]
  public var lastSentMappings: [MappingRecord]
  public var sleepTimeout: SleepTimeout
  public var lastSentSleepTimeout: SleepTimeout?
  public var managesSleep: Bool?
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    name: String = "默认方案",
    deviceIdentifier: UUID? = nil,
    deviceName: String? = nil,
    keyCount: Int = 3,
    mappings: [MappingRecord] = [],
    lastSentMappings: [MappingRecord] = [],
    sleepTimeout: SleepTimeout = .tenMinutes,
    lastSentSleepTimeout: SleepTimeout? = nil,
    managesSleep: Bool? = nil,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.deviceIdentifier = deviceIdentifier
    self.deviceName = deviceName
    self.keyCount = max(1, min(24, keyCount))
    self.mappings = mappings
    self.lastSentMappings = lastSentMappings
    self.sleepTimeout = sleepTimeout
    self.lastSentSleepTimeout = lastSentSleepTimeout
    self.managesSleep = managesSleep
    self.updatedAt = updatedAt
  }

  public func assignment(at address: MappingAddress) -> KeyAssignment? {
    mappings.first(where: { $0.address == address })?.assignment
  }

  public func lastSentAssignment(at address: MappingAddress) -> KeyAssignment? {
    lastSentMappings.first(where: { $0.address == address })?.assignment
  }

  public mutating func setAssignment(_ assignment: KeyAssignment?, at address: MappingAddress) {
    mappings.removeAll { $0.address == address }
    if let assignment {
      mappings.append(MappingRecord(address: address, assignment: assignment))
      mappings.sort { lhs, rhs in
        lhs.address.layer == rhs.address.layer
          ? lhs.address.key < rhs.address.key
          : lhs.address.layer < rhs.address.layer
      }
    }
    updatedAt = Date()
  }

  public mutating func markSent(at address: MappingAddress) {
    markSent(assignment(at: address), at: address)
  }

  public mutating func markSent(_ assignment: KeyAssignment?, at address: MappingAddress) {
    lastSentMappings.removeAll { $0.address == address }
    if let assignment {
      lastSentMappings.append(MappingRecord(address: address, assignment: assignment))
    }
    updatedAt = Date()
  }

  public var dirtyAddresses: [MappingAddress] {
    var addresses = Set(mappings.map(\.address))
    addresses.formUnion(lastSentMappings.map(\.address))
    return
      addresses
      .filter { assignment(at: $0) != lastSentAssignment(at: $0) }
      .sorted {
        $0.layer == $1.layer ? $0.key < $1.key : $0.layer < $1.layer
      }
  }

  public var shouldManageSleep: Bool {
    managesSleep ?? (lastSentSleepTimeout != nil)
  }

  public var isSleepDirty: Bool {
    shouldManageSleep && lastSentSleepTimeout != sleepTimeout
  }
}

public struct ProfileLibrary: Codable, Sendable {
  public var documentVersion: Int? = 1
  public var selectedProfileID: UUID
  public var profiles: [DeviceProfile]

  public init(selectedProfileID: UUID, profiles: [DeviceProfile]) {
    self.selectedProfileID = selectedProfileID
    self.profiles = profiles
  }

  public static func starter() -> ProfileLibrary {
    let profile = DeviceProfile()
    return ProfileLibrary(selectedProfileID: profile.id, profiles: [profile])
  }

  public static func demo() -> ProfileLibrary {
    let profile = DeviceProfile(
      mappings: [
        MappingRecord(
          address: MappingAddress(layer: 1, key: 1),
          assignment: KeyAssignment(actionID: "key.pageUp")
        ),
        MappingRecord(
          address: MappingAddress(layer: 1, key: 2),
          assignment: KeyAssignment(
            actionID: "key.k",
            modifiers: [.leftCommand, .leftShift]
          )
        ),
        MappingRecord(
          address: MappingAddress(layer: 1, key: 3),
          assignment: KeyAssignment(actionID: "media.volumeUp")
        ),
      ],
      lastSentMappings: [],
      sleepTimeout: .tenMinutes,
      managesSleep: true
    )
    return ProfileLibrary(selectedProfileID: profile.id, profiles: [profile])
  }
}

public enum WriteItem: Hashable, Sendable {
  case mapping(MappingAddress)
  case sleep
}

public struct WriteProgress: Equatable, Sendable {
  public let completed: Int
  public let total: Int
  public let currentLabel: String

  public init(completed: Int, total: Int, currentLabel: String) {
    self.completed = completed
    self.total = total
    self.currentLabel = currentLabel
  }
}
