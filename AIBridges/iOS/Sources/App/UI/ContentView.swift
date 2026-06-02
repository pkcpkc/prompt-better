import SwiftUI

struct ContentView: View {
  @EnvironmentObject var serverManager: ServerManager

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
        


        VStack(alignment: .leading) {
          Text("Logs")
            .font(.headline)
            .padding(.horizontal)

          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(serverManager.logs.indices, id: \.self) { index in
                  Text(serverManager.logs[index])
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal)
                }
              }
            }
            .onChange(of: serverManager.logs.count) {
              if let lastIndex = serverManager.logs.indices.last {
                withAnimation {
                  proxy.scrollTo(lastIndex)
                }
              }
            }
          }
          .background(Color.gray.opacity(0.1))
          .cornerRadius(8)
          .padding(.horizontal)
        }

        Spacer()
      }
#if os(iOS)
      .toolbar(.hidden, for: .navigationBar)
#endif
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
