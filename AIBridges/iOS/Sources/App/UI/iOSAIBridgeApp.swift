import SwiftUI
import Vapor

@main
struct iOSAIBridgeApp: App {
  @StateObject private var serverManager = ServerManager()
  @State private var showLaunchScreen = true

  var body: some Scene {
    WindowGroup {
      ZStack {
        if showLaunchScreen {
          LaunchScreenView()
            .task {
              let startTime = Date()
              // Start the server asynchronously
              await serverManager.start()
              
              // Ensure the premium launch screen remains visible for at least 2.5 seconds
              let elapsed = Date().timeIntervalSince(startTime)
              let remaining = max(2.5 - elapsed, 0)
              if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
              }
              
              // Switch instantly to the main interface
              showLaunchScreen = false
            }
        } else {
          ContentView()
            .environmentObject(serverManager)
        }
      }
    }
  }
}

@MainActor
class ServerManager: ObservableObject {
  @Published var isRunning = false
  @Published var logs: [String] = []
  @Published var port: Int = 8080
  @Published var ipAddress: String = "localhost"

  private var app: Application?

  func start() async {
    guard !isRunning else { return }

    // Refresh IP address every time we start
    self.ipAddress = getLocalIPAddress() ?? "localhost"

    do {
      let env = Environment(name: "development", arguments: ["vapor"])
      let app = try await Application.make(env)
      self.app = app

      // Configure server to bind only to the local WiFi interface
      app.http.server.configuration.hostname = ipAddress
      app.http.server.configuration.port = port

      // Register middleware for logging
      app.middleware.use(LogMiddleware(serverManager: self))

      // Register routes
      try routes(app)

      // Add a custom logger to capture logs for the UI
      app.logger.logLevel = .info

      log("Starting server on \(ipAddress):\(String(port))...")
      
      // Start the server using the embedded lifecycle
      try await app.startup()
      
      self.isRunning = true
      log("Server is running.")

    } catch {
      log("Failed to start server: \(error)")
    }
  }

  func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(
      from: Date(), dateStyle: .none, timeStyle: .medium)
    logs.append("[\(timestamp)] \(message)")
    if logs.count > 100 {
      logs.removeFirst()
    }
  }

  func stop() async {
    log("Stopping server...")
    isRunning = false
    
    if let app = self.app {
      // 1. Signal the server loop to stop
      app.running?.stop()
      
      // 2. Wait for the server to actually exit its loop
      // We use a try? await on the promise's get() if available, 
      // or we just rely on shutdown() being safer after the signal.
      // In Vapor 4, app.running?.onStop is a NIO event loop future.
      // We can ideally wait for it if we have NIO-to-Swift-Concurrency bridging,
      // but the signal alone already significantly improves the shutdown sequence.
      
      // 3. Gracefully shutdown the container
      try? await app.asyncShutdown()
      self.app = nil
    }
    
    log("Server stopped.")
  }

  private func getLocalIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&ifaddr) == 0 {
      var ptr = ifaddr
      while ptr != nil {
        defer { ptr = ptr?.pointee.ifa_next }

        guard let interface = ptr?.pointee,
              let addr = interface.ifa_addr else { continue }
        let addrFamily = addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
          let name = String(cString: interface.ifa_name)
          if name == "en0" || name == "en1" || name == "p2p0" {  // WiFi, Ethernet, or AirDrop/Sidecar
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
              interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname,
              socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)

            // Prioritize IPv4 for simplicity in connecting
            if addrFamily == UInt8(AF_INET) {
              return address
            }
          }
        }
      }
      freeifaddrs(ifaddr)
    }
    return address
  }
}

struct LogMiddleware: AsyncMiddleware {
  let serverManager: ServerManager

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    let method = request.method.rawValue
    let path = request.url.path

    // Log the incoming request
    await serverManager.log("\(method) \(path)")

    do {
      let response = try await next.respond(to: request)
      let status = response.status.code

      // Log the outgoing response
      await serverManager.log("\(status) \(method) \(path)")

      return response
    } catch {
      await serverManager.log("⚠️ \(error.localizedDescription)")
      throw error
    }
  }
}
