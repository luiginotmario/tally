import Darwin
import Foundation
import TallyKit

/// The app's mailbox: a Unix datagram socket that only this user can write to.
///
/// Each `tally` call sends one datagram and exits, and the app sleeps until one arrives:
/// no port, no polling, nothing leaves the Mac.
final class Inbox {
  static let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "Tally/inbox.sock").path

  private let socket: Int32
  private let source: DispatchSourceRead

  init?(onSignal: @escaping (Signal) -> Void) {
    try? FileManager.default.createDirectory(
      atPath: (Self.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    unlink(Self.path)

    let socket = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
    guard socket >= 0, Self.withAddress({ bind(socket, $0, $1) }) == 0 else { return nil }
    chmod(Self.path, 0o600)
    _ = fcntl(socket, F_SETFL, O_NONBLOCK)
    self.socket = socket

    source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
    source.setEventHandler { [socket] in
      var buffer = [UInt8](repeating: 0, count: 8192)
      while true {
        let count = recv(socket, &buffer, buffer.count, 0)
        guard count > 0 else { return }
        guard let signal = try? JSONDecoder().decode(Signal.self, from: Data(buffer[..<count])) else { continue }
        MainActor.assumeIsolated { onSignal(signal) }
      }
    }
    source.resume()
  }

  /// Sends one signal to the running app. Fails quietly when the app isn't running,
  /// because an agent's hook must never break the agent.
  @discardableResult
  static func send(_ signal: Signal) -> Bool {
    guard let data = try? JSONEncoder().encode(signal) else { return false }
    let socket = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
    guard socket >= 0 else { return false }
    defer { close(socket) }
    let sent = data.withUnsafeBytes { bytes in
      withAddress { sendto(socket, bytes.baseAddress, bytes.count, 0, $0, $1) }
    }
    return sent == data.count
  }

  private static func withAddress<Result>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> Result) -> Result? {
    var address = sockaddr_un()
    let path = Array(Self.path.utf8)
    guard path.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
    return withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
  }
}
