import SwiftUI

struct ContentView: View {
  @EnvironmentObject var serverManager: ServerManager

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("AI Bridge")
          .font(.largeTitle)
          .fontWeight(.bold)
        Spacer()
        Button(serverManager.isRunning ? "Stop" : "Start") {
          Task {
            if serverManager.isRunning {
              await serverManager.stop()
            } else {
              await serverManager.start()
            }
          }
        }
        .fontWeight(.bold)
        .buttonStyle(.borderedProminent)
        .tint(serverManager.isRunning ? .red : .green)
      }

      HStack {
        Circle()
          .fill(serverManager.isRunning ? Color.green : Color.red)
          .frame(width: 10, height: 10)
        Text(serverManager.isRunning ? "Running" : "Stopped")
          .fontWeight(.bold)
      }

      if serverManager.isRunning {
        // Use this as the student `base_url` in prompt-better.json.
        Text(serverManager.baseURL)
          .font(.system(.subheadline, design: .monospaced))
          .textSelection(.enabled)
      }

      Text("Logs")
        .font(.headline)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(serverManager.logs) { entry in
              Text(entry.text)
                .font(.system(.caption, design: .monospaced))
                .id(entry.id)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .onChange(of: serverManager.logs.last?.id) { _, last in
          if let last { proxy.scrollTo(last) }
        }
      }
    }
    .padding()
  }
}
