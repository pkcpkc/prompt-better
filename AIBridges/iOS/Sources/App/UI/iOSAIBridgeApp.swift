import AIBridgeKit
import SwiftUI
import Vapor

@main
struct iOSAIBridgeApp: App {
  @StateObject private var serverManager = ServerManager()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(serverManager)
        .task { await serverManager.start() }
    }
  }
}

struct LogEntry: Identifiable, Equatable {
  let id = UUID()
  let text: String
}

@MainActor
final class ServerManager: ObservableObject {
  @Published var isRunning = false
  @Published var logs: [LogEntry] = []
  @Published private(set) var ipAddress = "localhost"
  let port = 8080

  private var app: Application?

  var baseURL: String { "http://\(ipAddress):\(port)/v1" }

  func start() async {
    guard !isRunning else { return }
    ipAddress = Self.localIPAddress() ?? "localhost"

    do {
      let app = try await Application.make(Environment(name: "development", arguments: ["vapor"]))
      // Bind to the local network interface so a Mac on the same network can reach the device.
      app.http.server.configuration.hostname = ipAddress
      app.http.server.configuration.port = port
      app.middleware.use(LogMiddleware(serverManager: self))
      try routes(app)

      log("Starting server on \(ipAddress):\(port)...")
      try await app.startup()
      self.app = app
      isRunning = true
      log("Server is running at \(baseURL)")
      log(BridgeModel.diagnostics)
      log("Models: \(BridgeModel.allCases.map(\.rawValue).joined(separator: ", "))")
    } catch {
      log("Failed to start server: \(error)")
    }
  }

  func stop() async {
    guard let app else { return }
    log("Stopping server...")
    app.running?.stop()
    try? await app.asyncShutdown()
    self.app = nil
    isRunning = false
    log("Server stopped.")
  }

  func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    logs.append(LogEntry(text: "[\(timestamp)] \(message)"))
    if logs.count > 200 {
      logs.removeFirst()
    }
  }

  /// IPv4 address of WiFi/Ethernet (preferred), falling back to IPv6.
  private static func localIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr = ifaddr
    while let interface = ptr?.pointee {
      defer { ptr = interface.ifa_next }
      guard let addr = interface.ifa_addr else { continue }
      let family = addr.pointee.sa_family
      guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
      let name = String(cString: interface.ifa_name)
      guard name == "en0" || name == "en1" else { continue }

      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
      address = String(cString: hostname)
      if family == UInt8(AF_INET) { return address }
    }
    return address
  }
}

struct LogMiddleware: AsyncMiddleware {
  let serverManager: ServerManager

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    let line = "\(request.method.rawValue) \(request.url.path)"
    await serverManager.log(line)
    let response = try await next.respond(to: request)
    await serverManager.log("\(response.status.code) \(line)")
    return response
  }
}
