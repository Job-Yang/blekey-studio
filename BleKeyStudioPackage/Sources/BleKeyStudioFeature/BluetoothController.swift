import CoreBluetooth
import Foundation

public struct BLEDeviceDescriptor: Hashable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let isSystemConnected: Bool

  public init(id: UUID, name: String, isSystemConnected: Bool) {
    self.id = id
    self.name = name
    self.isSystemConnected = isSystemConnected
  }

  public var inferredKeyCount: Int {
    let prefix = name.prefix { $0.isNumber }
    guard let count = Int(prefix), (1...24).contains(count) else { return 3 }
    return count
  }
}

public enum BluetoothConnectionState: Equatable, Sendable {
  case unavailable(String)
  case idle
  case scanning
  case connecting(String)
  case discovering(String)
  case ready(String)
  case writing(WriteProgress)
  case disconnected(String?)
  case failed(String)

  public var title: String {
    switch self {
    case .unavailable(let reason): reason
    case .idle: "等待连接"
    case .scanning: "正在查找设备"
    case .connecting(let name): "正在连接 \(name)"
    case .discovering(let name): "正在准备 \(name)"
    case .ready: "已连接"
    case .writing(let progress): "正在写入 \(progress.completed + 1)/\(progress.total)"
    case .disconnected: "连接已断开"
    case .failed(let message): message
    }
  }

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }
}

public final class BluetoothController: NSObject {
  public private(set) var devices: [BLEDeviceDescriptor] = []
  public private(set) var state: BluetoothConnectionState = .idle {
    didSet { onStateChange?(state) }
  }
  public private(set) var connectedDeviceID: UUID?
  public var isDemoMode: Bool { demoMode }
  public var isBusy: Bool {
    currentCommand != nil || !writeQueue.isEmpty || isInspectingReadback
  }
  public private(set) var readbackSummary = "尚未取得设备配置；读取协议未确认"
  public var onReadbackChange: (() -> Void)?
  public var canInspectReadback: Bool {
    canWrite && !isInspectingReadback
  }
  public var canWrite: Bool {
    guard !isInspectingReadback else { return false }
    if demoMode {
      return connectedDeviceID != nil && currentCommand == nil && writeQueue.isEmpty
    }
    return connectedPeripheral != nil
      && writeCharacteristic != nil
      && currentCommand == nil
      && writeQueue.isEmpty
  }

  public var onDevicesChange: (([BLEDeviceDescriptor]) -> Void)?
  public var onStateChange: ((BluetoothConnectionState) -> Void)?
  public var onLog: ((String) -> Void)?
  public var onCommandResult: ((XKeyCommand, Result<Void, Error>) -> Void)?
  public var onBatchFinished: (() -> Void)?

  private let serviceUUID = CBUUID(string: XKeyProtocol.serviceUUID)
  private let writeUUID = CBUUID(string: XKeyProtocol.writeCharacteristicUUID)
  private let notifyUUID = CBUUID(string: XKeyProtocol.notifyCharacteristicUUID)
  private let demoMode: Bool

  private var centralManager: CBCentralManager!
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var connectedPeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var writeQueue: [XKeyCommand] = []
  private var currentCommand: XKeyCommand?
  private var batchTotal = 0
  private var batchCompleted = 0
  private var writeGeneration = UUID()
  private var isInspectingReadback = false
  private var readQueue: [CBCharacteristic] = []
  private var pendingRead: CBCharacteristic?
  private var readGeneration = UUID()

  public override convenience init() {
    self.init(
      demoMode: ProcessInfo.processInfo.environment["BLEKEY_DEMO_MODE"] == "1"
        || ProcessInfo.processInfo.arguments.contains("--demo")
    )
  }

  init(demoMode: Bool) {
    self.demoMode = demoMode
    super.init()

    if demoMode {
      let id = UUID(uuidString: "7BCDFF5E-1494-3B61-6B38-522471D9E080")!
      devices = [BLEDeviceDescriptor(id: id, name: "3KEY_1", isSystemConnected: true)]
      connectedDeviceID = id
      state = .ready("3KEY_1")
    } else {
      centralManager = CBCentralManager(
        delegate: self,
        queue: .main,
        options: [CBCentralManagerOptionShowPowerAlertKey: true]
      )
    }
  }

  public func refresh() {
    guard currentCommand == nil, !isInspectingReadback else { return }
    guard !demoMode else {
      onDevicesChange?(devices)
      onStateChange?(state)
      return
    }
    guard centralManager.state == .poweredOn else {
      updateUnavailableState()
      return
    }
    if connectedPeripheral?.state == .connected, writeCharacteristic != nil {
      onDevicesChange?(devices)
      state = .ready(connectedName)
      return
    }

    let connected = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
    for peripheral in connected {
      addOrUpdate(peripheral, systemConnected: true)
    }
    centralManager.stopScan()
    centralManager.scanForPeripherals(
      withServices: [serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    state = .scanning
    onDevicesChange?(devices)
    log("开始查找支持 XKey 协议的蓝牙设备")
  }

  public func connect(deviceID: UUID) {
    guard currentCommand == nil, !isInspectingReadback else { return }
    guard !demoMode else {
      connectedDeviceID = deviceID
      state = .ready(devices.first(where: { $0.id == deviceID })?.name ?? "演示设备")
      return
    }
    guard let peripheral = peripherals[deviceID] else {
      state = .failed("找不到该设备，请刷新后重试")
      return
    }

    centralManager.stopScan()
    if let old = connectedPeripheral, old.identifier != deviceID {
      centralManager.cancelPeripheralConnection(old)
    }
    resetConnection()
    connectedPeripheral = peripheral
    connectedDeviceID = peripheral.identifier
    peripheral.delegate = self
    state = .connecting(displayName(for: peripheral))
    centralManager.connect(peripheral, options: nil)
  }

  public func disconnect() {
    guard !demoMode else {
      resetConnection()
      state = .disconnected("3KEY_1")
      return
    }
    if let peripheral = connectedPeripheral {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    resetConnection()
    state = .disconnected(nil)
  }

  @discardableResult
  public func send(_ commands: [XKeyCommand]) -> Bool {
    guard !commands.isEmpty else { return true }
    guard canWrite else {
      state = .failed("设备尚未就绪")
      return false
    }

    writeQueue = commands
    currentCommand = nil
    batchTotal = commands.count
    batchCompleted = 0
    writeGeneration = UUID()
    writeNext()
    return true
  }

  private func writeNext() {
    guard currentCommand == nil else { return }
    guard !writeQueue.isEmpty else {
      let name = connectedName
      state = .ready(name)
      onBatchFinished?()
      return
    }

    let command = writeQueue.removeFirst()
    currentCommand = command
    state = .writing(
      WriteProgress(
        completed: batchCompleted,
        total: batchTotal,
        currentLabel: command.label
      )
    )
    log("发送 \(command.hex) · \(command.label)")

    if demoMode {
      let generation = writeGeneration
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        guard self?.writeGeneration == generation else { return }
        self?.completeCurrentCommand(error: nil)
      }
      return
    }

    guard let peripheral = connectedPeripheral,
      let characteristic = writeCharacteristic
    else {
      completeCurrentCommand(error: BLEWriteError.characteristicUnavailable)
      return
    }

    if characteristic.properties.contains(.write) {
      peripheral.writeValue(command.bytes, for: characteristic, type: .withResponse)
      let generation = writeGeneration
      DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
        guard self?.writeGeneration == generation, self?.currentCommand == command else { return }
        self?.completeCurrentCommand(error: BLEWriteError.timeout)
      }
    } else if characteristic.properties.contains(.writeWithoutResponse) {
      peripheral.writeValue(command.bytes, for: characteristic, type: .withoutResponse)
      let generation = writeGeneration
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
        guard self?.writeGeneration == generation else { return }
        self?.completeCurrentCommand(error: nil)
      }
    } else {
      completeCurrentCommand(error: BLEWriteError.writeUnsupported)
    }
  }

  private func completeCurrentCommand(error: Error?) {
    guard let command = currentCommand else { return }
    currentCommand = nil
    if let error {
      writeGeneration = UUID()
      if !demoMode, let peripheral = connectedPeripheral {
        writeCharacteristic = nil
        centralManager.cancelPeripheralConnection(peripheral)
      }
      onCommandResult?(command, .failure(error))
      log("写入失败 · \(command.label) · \(error.localizedDescription)")
      writeQueue.removeAll()
      state = .failed(error.localizedDescription)
      onBatchFinished?()
      return
    }

    batchCompleted += 1
    onCommandResult?(command, .success(()))
    log("写入完成 · \(command.label)")
    writeNext()
  }

  private func addOrUpdate(_ peripheral: CBPeripheral, systemConnected: Bool) {
    peripherals[peripheral.identifier] = peripheral
    let descriptor = BLEDeviceDescriptor(
      id: peripheral.identifier,
      name: displayName(for: peripheral),
      isSystemConnected: systemConnected || peripheral.state == .connected
    )
    devices.removeAll { $0.id == descriptor.id }
    devices.append(descriptor)
    devices.sort {
      if $0.isSystemConnected != $1.isSystemConnected {
        return $0.isSystemConnected && !$1.isSystemConnected
      }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    onDevicesChange?(devices)
  }

  private func displayName(for peripheral: CBPeripheral) -> String {
    let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    return name?.isEmpty == false ? name! : "未命名设备"
  }

  private var connectedName: String {
    guard let id = connectedDeviceID else { return "设备" }
    return devices.first(where: { $0.id == id })?.name ?? "设备"
  }

  private func resetConnection() {
    if currentCommand != nil {
      completeCurrentCommand(error: BLEWriteError.disconnected)
    }
    writeGeneration = UUID()
    readGeneration = UUID()
    isInspectingReadback = false
    pendingRead = nil
    readQueue = []
    readbackSummary = "尚未取得设备配置；读取协议未确认"
    connectedPeripheral = nil
    connectedDeviceID = nil
    writeCharacteristic = nil
    currentCommand = nil
    writeQueue.removeAll()
    onReadbackChange?()
  }

  public func inspectReadback() {
    guard canInspectReadback else { return }
    guard !demoMode else {
      readbackSummary = "演示模式：未读取真实设备"
      log(readbackSummary)
      onReadbackChange?()
      return
    }
    guard let service = connectedPeripheral?.services?.first(where: { $0.uuid == serviceUUID })
    else { return }
    readQueue = (service.characteristics ?? []).filter { $0.properties.contains(.read) }
    if readQueue.isEmpty {
      readbackSummary = "配置服务没有可直接读取的特征；专用查询协议未确认"
      log(readbackSummary)
      onReadbackChange?()
      return
    }
    isInspectingReadback = true
    readGeneration = UUID()
    readbackSummary = "正在读取原始特征值，尚未取得键位配置"
    log("只读检测开始；不发送配置写入或猜测的查询命令")
    onReadbackChange?()
    readNext()
  }

  private func readNext() {
    guard isInspectingReadback, let peripheral = connectedPeripheral else { return }
    guard !readQueue.isEmpty else {
      isInspectingReadback = false
      pendingRead = nil
      readbackSummary = "检测已结束；原始结果见通信记录，键位格式尚未确认"
      onReadbackChange?()
      return
    }
    let characteristic = readQueue.removeFirst()
    pendingRead = characteristic
    let generation = readGeneration
    log("读取 \(characteristic.uuid.uuidString)")
    peripheral.readValue(for: characteristic)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, self.readGeneration == generation, self.pendingRead === characteristic else {
        return
      }
      self.log("读取超时 · \(characteristic.uuid.uuidString)")
      self.isInspectingReadback = false
      self.pendingRead = nil
      self.readQueue = []
      self.readbackSummary = "读取超时；设备当前配置仍未知"
      self.onReadbackChange?()
    }
  }

  private func updateUnavailableState() {
    switch centralManager.state {
    case .poweredOff:
      state = .unavailable("蓝牙已关闭")
    case .unauthorized:
      state = .unavailable("未获得蓝牙权限")
    case .unsupported:
      state = .unavailable("此 Mac 不支持蓝牙低功耗")
    case .resetting:
      state = .unavailable("蓝牙正在重置")
    case .unknown:
      state = .unavailable("正在检查蓝牙")
    case .poweredOn:
      state = .idle
    @unknown default:
      state = .unavailable("蓝牙状态未知")
    }
  }

  private func log(_ message: String) {
    onLog?("\(Self.timestamp.string(from: Date()))  \(message)")
  }

  private static let timestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}

extension BluetoothController: CBCentralManagerDelegate {
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    updateUnavailableState()
    if central.state == .poweredOn {
      refresh()
    }
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    addOrUpdate(peripheral, systemConnected: false)
  }

  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard peripheral.identifier == connectedDeviceID else { return }
    connectedPeripheral = peripheral
    connectedDeviceID = peripheral.identifier
    peripheral.delegate = self
    state = .discovering(displayName(for: peripheral))
    log("已连接，正在发现配置服务")
    peripheral.discoverServices([serviceUUID])
  }

  public func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    guard peripheral.identifier == connectedDeviceID else { return }
    let message = error?.localizedDescription ?? "无法连接设备"
    resetConnection()
    state = .failed(message)
    log("连接失败 · \(message)")
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    guard peripheral.identifier == connectedDeviceID else { return }
    let name = displayName(for: peripheral)
    resetConnection()
    state = error.map { .failed($0.localizedDescription) } ?? .disconnected(name)
    log("设备已断开")
  }
}

extension BluetoothController: CBPeripheralDelegate {
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard peripheral.identifier == connectedDeviceID else { return }
    if let error {
      state = .failed(error.localizedDescription)
      return
    }
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
      state = .failed("设备未提供 XKey 配置服务")
      return
    }
    peripheral.discoverCharacteristics(nil, for: service)
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard peripheral.identifier == connectedDeviceID else { return }
    if let error {
      state = .failed(error.localizedDescription)
      return
    }
    writeCharacteristic = service.characteristics?.first(where: { $0.uuid == writeUUID })
    for characteristic in service.characteristics ?? [] {
      let flags = [
        characteristic.properties.contains(.read) ? "Read" : nil,
        characteristic.properties.contains(.write) ? "Write" : nil,
        characteristic.properties.contains(.writeWithoutResponse) ? "WriteWithoutResponse" : nil,
        characteristic.properties.contains(.notify) ? "Notify" : nil,
      ].compactMap { $0 }.joined(separator: ", ")
      log("配置特征 \(characteristic.uuid.uuidString) [\(flags)]")
    }
    if let notify = service.characteristics?.first(where: { $0.uuid == notifyUUID }),
      notify.properties.contains(.notify)
    {
      peripheral.setNotifyValue(true, for: notify)
    }
    guard writeCharacteristic != nil else {
      state = .failed("设备缺少写入特征 FFE7")
      return
    }
    state = .ready(displayName(for: peripheral))
    log("设备已就绪")
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard peripheral.identifier == connectedDeviceID, characteristic === writeCharacteristic else {
      return
    }
    completeCurrentCommand(error: error)
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard peripheral.identifier == connectedDeviceID else { return }
    let isReadResult = pendingRead === characteristic
    defer {
      if isReadResult {
        pendingRead = nil
        readNext()
      }
    }
    if let error {
      log("通知读取失败 · \(error.localizedDescription)")
      return
    }
    guard let data = characteristic.value else { return }
    let hex = data.map { String(format: "%02X", $0) }.joined()
    log(
      "\(isReadResult ? "原始读取" : "设备通知") \(characteristic.uuid.uuidString): \(hex.isEmpty ? "(空值)" : hex)"
    )
  }
}

private enum BLEWriteError: LocalizedError {
  case characteristicUnavailable
  case writeUnsupported
  case timeout
  case disconnected

  var errorDescription: String? {
    switch self {
    case .characteristicUnavailable:
      "写入特征尚未就绪"
    case .writeUnsupported:
      "设备的 FFE7 特征不支持写入"
    case .timeout:
      "设备写入超时，更改仍保留在本地"
    case .disconnected:
      "连接已断开，未完成的更改仍保留在本地"
    }
  }
}
