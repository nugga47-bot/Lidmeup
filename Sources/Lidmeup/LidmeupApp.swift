import SwiftUI

@main
struct LidmeupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sensor = LidSensor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 580)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(sensor: sensor)
        } label: {
            Text("\(Int(sensor.angle.rounded()))\u{00B0}")
        }
    }
}

struct MenuBarView: View {
    let sensor: LidSensor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lid Angle: \(Int(sensor.angle.rounded()))\u{00B0}")
                .font(.headline)
            Text("\(Int(sensor.percentage.rounded()))% open")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(sensor.status)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
