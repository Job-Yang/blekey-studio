import Foundation

final class ActivityLogStore {
  let storageURL: URL

  private let fileManager: FileManager
  private let retainedLineCount = 1_000
  private let trimThreshold = 1_048_576

  init(storageURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.storageURL =
      storageURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BleKey Studio", isDirectory: true)
        .appendingPathComponent("activity.log")
  }

  func loadRecent(limit: Int = 300) throws -> [String] {
    guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
    let contents = try String(contentsOf: storageURL, encoding: .utf8)
    return Array(contents.split(whereSeparator: \.isNewline).suffix(limit)).map(String.init)
  }

  func append(_ line: String) throws {
    try fileManager.createDirectory(
      at: storageURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: storageURL.path) {
      try Data().write(to: storageURL, options: .atomic)
    }
    let handle = try FileHandle(forWritingTo: storageURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\(line)\n".utf8))
    try trimIfNeeded()
  }

  private func trimIfNeeded() throws {
    let attributes = try fileManager.attributesOfItem(atPath: storageURL.path)
    guard let size = attributes[.size] as? NSNumber,
      size.intValue > trimThreshold
    else { return }
    let lines = try loadRecent(limit: retainedLineCount)
    try Data((lines.joined(separator: "\n") + "\n").utf8)
      .write(to: storageURL, options: .atomic)
  }
}
