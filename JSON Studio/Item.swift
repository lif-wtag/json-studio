//
//  Item.swift
//  JSON Studio
//
//  Created by Fazle Rabbi Linkon on 8/26/26.
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
