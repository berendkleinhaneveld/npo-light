//
//  Item.swift
//  NPO light
//
//  Created by Berend Klein Haneveld on 29/08/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
