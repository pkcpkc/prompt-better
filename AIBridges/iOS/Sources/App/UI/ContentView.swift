import SwiftUI

struct ContentView: View {
  @EnvironmentObject var serverManager: ServerManager
  @State private var showChat = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        // Custom Header Row
        HStack {
            Text("AI Bridge")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: {
                if serverManager.isRunning {
                    Task {
                        await serverManager.stop()
                    }
                } else {
                    Task {
                        await serverManager.start()
                    }
                }
            }) {
                Text(serverManager.isRunning ? "Stop" : "Start")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(serverManager.isRunning ? .red : .green)
        }
        .padding(.horizontal)
        .padding(.top)

        statusHeader
        


        LogsView(logsManager: serverManager.logsManager)

        // Bottom button actions row (destructive left, primary right)
        HStack {
          Button(action: {
            serverManager.logsManager.clear()
          }) {
            HStack(spacing: 8) {
              Image(systemName: "trash.fill")
              Text("Clear Logs")
                .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.red)
            .cornerRadius(24)
            .shadow(color: Color.red.opacity(0.3), radius: 6, x: 0, y: 4)
          }
          .buttonStyle(.plain)
          .padding(.leading, 20)

          Spacer()

          Button(action: {
            showChat = true
          }) {
            HStack(spacing: 8) {
              Image(systemName: "bubble.left.and.bubble.right.fill")
              Text("Chat")
                .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green)
            .cornerRadius(24)
            .shadow(color: Color.green.opacity(0.3), radius: 6, x: 0, y: 4)
          }
          .buttonStyle(.plain)
          .padding(.trailing, 20)
        }
        .padding(.bottom, 20)
      }
#if os(iOS)
      .toolbar(.hidden, for: .navigationBar)
#endif
      .sheet(isPresented: $showChat) {
        ChatWindowView()
          .environmentObject(serverManager)
      }
    }
  }

  private var statusHeader: some View {
    HStack {
      VStack(alignment: .leading) {
        HStack {
          Circle()
            .fill(serverManager.isRunning ? Color.green : Color.red)
            .frame(width: 10, height: 10)
          Text(serverManager.isRunning ? "Running" : "Stopped")
            .fontWeight(.bold)
        }

        if serverManager.isRunning {
          Link(destination: URL(string: "http://\(serverManager.ipAddress):\(String(serverManager.port))/v1/models")!) {
            Text("http://\(serverManager.ipAddress):\(String(serverManager.port))/v1/models")
              .underline()
              .font(.subheadline)
              .foregroundColor(.blue)
          }
        } else {
          Text("Server offline")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
      Spacer()
    }
    .padding()
    .background(Color.gray.opacity(0.05))
    .cornerRadius(12)
    .shadow(radius: 2)
    .padding()
  }
}

struct LogsView: View {
  @ObservedObject var logsManager: LogsManager

  var body: some View {
    VStack(alignment: .leading) {
      Text("Logs")
        .font(.headline)
        .padding(.horizontal)

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(logsManager.logs) { log in
              Text(log.text)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal)
                .id(log.id)
            }
          }
        }
        .onChange(of: logsManager.logs) { oldValue, newValue in
          if let last = newValue.last {
            DispatchQueue.main.async {
              withAnimation {
                proxy.scrollTo(last.id)
              }
            }
          }
        }
      }
      .background(Color.gray.opacity(0.1))
      .cornerRadius(8)
      .padding(.horizontal)
    }
  }
}
