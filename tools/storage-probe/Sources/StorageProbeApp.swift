import SwiftUI

@main
struct StorageProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}

struct ProbeView: View {
    @State private var report = "Running storage probe…"

    var body: some View {
        ScrollView {
            Text(verbatim: report)
                .font(.system(size: 24, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(60)
        }
        .task {
            let result = await StorageProbe().run(write: ProcessInfo.processInfo.arguments.contains("--write"))
            report = result
            print(result)
        }
    }
}

#Preview {
    ProbeView()
}
