import SwiftData

@Model
final class ProbeRecord {
    var marker: String

    init(marker: String) {
        self.marker = marker
    }
}
