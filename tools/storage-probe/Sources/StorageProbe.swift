import Foundation
import SwiftData

/// An isolated capability experiment, not the app's persistence implementation.
actor StorageProbe {
    private let marker = "npo-storage-probe-v1"
    private let defaultsKey = "storage-probe-payload-v1"

    func run(write: Bool) -> String {
        var lines = ["Storage probe v1", "Operation: \(write ? "write" : "read only")"]
        #if targetEnvironment(simulator)
        lines.append("SIMULATOR: this is not hardware durability evidence.")
        #else
        lines.append("Physical device")
        #endif
        lines.append("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let schema = Schema([ProbeRecord.self])
        let standard = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        lines.append(checkStore(name: "Default SwiftData", configuration: standard, write: write))
        do {
            let caches = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let configuration = ModelConfiguration(
                "CacheProbe", schema: schema,
                url: caches.appendingPathComponent("StorageProbe.store"), cloudKitDatabase: .none
            )
            lines.append(checkStore(name: "Caches SwiftData", configuration: configuration, write: write))
        } catch {
            lines.append("Caches directory FAILED: \(error)")
        }
        lines.append(checkDefaults(write: write))
        lines.append("A relaunch/reboot pass does not establish resistance to cache eviction.")
        return lines.joined(separator: "\n\n")
    }

    private func checkStore(name: String, configuration: ModelConfiguration, write: Bool) -> String {
        do {
            let container = try ModelContainer(for: ProbeRecord.self, configurations: configuration)
            let context = ModelContext(container)
            let previous = try context.fetch(FetchDescriptor<ProbeRecord>())
            if write && previous.isEmpty {
                context.insert(ProbeRecord(marker: marker))
                try context.save()
            }
            let records = try context.fetch(FetchDescriptor<ProbeRecord>())
            let matches = records.count == 1 && records.first?.marker == marker
            return "\(name): \(matches ? "PASS" : "MISSING OR MISMATCH") (previous records: \(previous.count))"
        } catch {
            let failure = error as NSError
            return "\(name) FAILED: \(failure.domain) \(failure.code): \(failure.localizedDescription)"
        }
    }

    private func checkDefaults(write: Bool) -> String {
        // Stay below the documented 512 KB warning; 1 MB terminates a tvOS app.
        let expected = Data(repeating: 0x5A, count: 256 * 1024)
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: defaultsKey)
        if write {
            defaults.set(expected, forKey: defaultsKey)
        }
        let matches = defaults.data(forKey: defaultsKey) == expected
        return "UserDefaults 256 KiB: \(matches ? "PASS" : "MISSING OR MISMATCH")"
            + " (previous bytes: \(previous?.count ?? 0))"
    }
}
