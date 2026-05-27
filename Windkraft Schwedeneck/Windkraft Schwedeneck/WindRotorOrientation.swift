//
//  WindRotorOrientation.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 21.05.26.
//

import Foundation

enum WindRotorOrientationMode: String, CaseIterable, Identifiable {
    case seasonal
    case manual

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .seasonal:
            "Automatisch"
        case .manual:
            "Manuell"
        }
    }
}

enum WindSeasonalDirection {
    static func currentWindFromDegrees(date: Date = Date()) -> Double {
        windFromDegrees(forMonth: Calendar.current.component(.month, from: date))
    }

    static func windFromDegrees(forMonth month: Int) -> Double {
        switch month {
        case 12, 1, 2:
            245
        case 3, 4, 5:
            265
        case 6, 7, 8:
            285
        case 9, 10, 11:
            250
        default:
            260
        }
    }

    static func seasonName(for date: Date = Date()) -> String {
        switch Calendar.current.component(.month, from: date) {
        case 12, 1, 2:
            "Winter"
        case 3, 4, 5:
            "Frühjahr"
        case 6, 7, 8:
            "Sommer"
        case 9, 10, 11:
            "Herbst"
        default:
            "Saison"
        }
    }
}

enum WindDirectionFormatter {
    static func text(for degrees: Double) -> String {
        let normalizedDegrees = normalized(degrees)
        let names = ["N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((normalizedDegrees / 22.5).rounded()) % names.count
        let degreesText = normalizedDegrees.formatted(.number.precision(.fractionLength(0)))
        return "\(degreesText)° \(names[index])"
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}
