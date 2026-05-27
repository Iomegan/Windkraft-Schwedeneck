//
//  WindInterfaceMode.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 21.05.26.
//

import Foundation

enum WindInterfaceMode: String, CaseIterable, Identifiable {
    case simplified
    case expert

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .simplified:
            "Vereinfacht"
        case .expert:
            "Experte"
        }
    }
}
