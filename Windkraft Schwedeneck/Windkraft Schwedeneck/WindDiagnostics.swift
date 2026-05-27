//
//  WindDiagnostics.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 20.05.26.
//

import CoreLocation
import Foundation
import SwiftUI

enum WindStatusTone {
    case good
    case warning
    case blocked

    var color: Color {
        switch self {
        case .good:
            .green
        case .warning:
            .orange
        case .blocked:
            .red
        }
    }

    var symbolName: String {
        switch self {
        case .good:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .blocked:
            "xmark.octagon.fill"
        }
    }
}

struct WindLightEnvironment: Equatable {
    let ambientIntensity: Double?

    static let unavailable = WindLightEnvironment(ambientIntensity: nil)

    var renderFactor: Double {
        guard let ambientIntensity else {
            return 1
        }

        let normalized = (ambientIntensity - 80) / 920
        return sqrt(min(max(normalized, 0), 1))
    }

    var isTooDarkForUnlitTurbine: Bool {
        guard let ambientIntensity else {
            return false
        }

        return ambientIntensity < 80
    }

    var isDim: Bool {
        guard let ambientIntensity else {
            return false
        }

        return ambientIntensity < 280
    }
}

struct WindVisualizationStatus {
    let title: String
    let detail: String
    let tone: WindStatusTone
    let drawsOverlay: Bool

    static let waitingForLocation = WindVisualizationStatus(
        title: "Warte auf Standort",
        detail: "Die Anlage erscheint, sobald Standort und Kamera bereit sind.",
        tone: .warning,
        drawsOverlay: false
    )

    static let invalidLocation = WindVisualizationStatus(
        title: "Standort ungültig",
        detail: "Das iPhone meldet gerade keinen brauchbaren Standort.",
        tone: .blocked,
        drawsOverlay: false
    )

    static func tooFar(distanceText: String) -> WindVisualizationStatus {
        WindVisualizationStatus(
            title: "Zu weit entfernt",
            detail: "\(distanceText) Abstand. Für diese Visualisierung bitte näher als 10 km an die Anlage gehen.",
            tone: .blocked,
            drawsOverlay: false
        )
    }

    static func behindCamera(turnDirection: String) -> WindVisualizationStatus {
        WindVisualizationStatus(
            title: "Anlage hinter dir",
            detail: "Drehe dich \(turnDirection), bis die Anlage ins Sichtfeld kommt.",
            tone: .warning,
            drawsOverlay: false
        )
    }

    static func outsideView(direction: String) -> WindVisualizationStatus {
        WindVisualizationStatus(
            title: "Anlage außerhalb des Bildes",
            detail: "Schwenke \(direction), um die Anlage ins Sichtfeld zu holen.",
            tone: .warning,
            drawsOverlay: false
        )
    }

    static let visible = WindVisualizationStatus(
        title: "Anlage im Sichtfeld",
        detail: "Die App zeigt die Anlage dort, wo sie ungefähr zu sehen wäre.",
        tone: .good,
        drawsOverlay: true
    )

    static let tooDark = WindVisualizationStatus(
        title: "Zu dunkel für Sichtbarkeit",
        detail: "Die Kamera sieht zu wenig Licht. Bei Nacht wäre die Anlage kaum zu erkennen. Bitte bei Tageslicht erneut prüfen.",
        tone: .blocked,
        drawsOverlay: false
    )

    static func visibleWithSkyMask(coverageText _: String) -> WindVisualizationStatus {
        WindVisualizationStatus(
            title: "Anlage im Sichtfeld",
            detail: "Die App berücksichtigt, dass Bäume oder Gebäude vor der Anlage stehen können.",
            tone: .good,
            drawsOverlay: true
        )
    }

    static let skyOccluded = WindVisualizationStatus(
        title: "Anlage verdeckt",
        detail: "Davor sind Bäume, Gebäude oder anderes im Bild. Deshalb wird die Anlage dort ausgeblendet.",
        tone: .warning,
        drawsOverlay: true
    )

    func adjustedForLight(_ lightEnvironment: WindLightEnvironment) -> WindVisualizationStatus {
        guard drawsOverlay, lightEnvironment.isDim else {
            return self
        }

        return WindVisualizationStatus(
            title: title,
            detail: detail + " Bei wenig Licht wird sie dunkler dargestellt.",
            tone: tone == .good ? .warning : tone,
            drawsOverlay: drawsOverlay
        )
    }
}

struct WindAccuracySummary {
    let gpsText: String
    let altitudeText: String
    let compassText: String
    let courseText: String
    let imageOffsetText: String
    let warningText: String?
    let infoText: String?
    let tone: WindStatusTone

    static let unavailable = WindAccuracySummary(
        gpsText: "GPS --",
        altitudeText: "Höhe --",
        compassText: "True --",
        courseText: "Kurs --",
        imageOffsetText: "Bildlage --",
        warningText: "Noch keine Standortdaten.",
        infoText: nil,
        tone: .warning
    )

    static func make(
        location: CLLocation?,
        heading: CLHeading?,
        distanceMeters: Double?,
        courseAssist: WindCourseAssist
    ) -> WindAccuracySummary {
        guard let location else {
            return .unavailable
        }

        let horizontalAccuracy = location.horizontalAccuracy > 0 ? location.horizontalAccuracy : nil
        let verticalAccuracy = location.verticalAccuracy > 0 ? location.verticalAccuracy : nil
        let headingAccuracy = heading?.headingAccuracy ?? -1
        let validHeadingAccuracy = headingAccuracy > 0 ? headingAccuracy : nil
        let headingSourceText = headingSourceText(heading: heading, accuracy: validHeadingAccuracy)
        let directionAccuracy = courseAssist.activeAccuracyDegrees ?? validHeadingAccuracy
        let headingDrivenOffset = offsetFromHeadingAccuracy(
            headingAccuracyDegrees: directionAccuracy,
            distanceMeters: distanceMeters
        )

        let combinedOffset = combinedHorizontalOffset(
            gpsAccuracy: horizontalAccuracy,
            headingOffset: headingDrivenOffset
        )

        let gpsText = horizontalAccuracy.map { "GPS ±\($0.metersText)" } ?? "GPS ungültig"
        let altitudeText = verticalAccuracy.map { "Höhe ±\($0.metersText)" } ?? "Höhe fehlt"
        let compassText = headingSourceText
        let imageOffsetText = combinedOffset.map { "Bildlage ±\($0.metersText)" } ?? "Bildlage --"

        let tone: WindStatusTone
        let warning: String?

        if horizontalAccuracy == nil {
            tone = .blocked
            warning = "GPS meldet keine gültige Genauigkeit."
        } else if let distanceMeters, distanceMeters > 10_000 {
            tone = .blocked
            warning = "Entfernung größer als 10 km."
        } else if validHeadingAccuracy == nil {
            tone = .warning
            warning = "True-North-Genauigkeit unbekannt. Die Anlage kann seitlich deutlich versetzt sein."
        } else if combinedOffset ?? 0 > 120 {
            tone = .warning
            warning = "Kompass/GPS liefern gerade nur eine grobe Bildlage."
        } else if horizontalAccuracy ?? 0 > 30 {
            tone = .warning
            warning = "GPS ist noch ungenau. Kurz warten oder Standort mit freiem Himmel wählen."
        } else {
            tone = .good
            warning = nil
        }

        return WindAccuracySummary(
            gpsText: gpsText,
            altitudeText: altitudeText,
            compassText: compassText,
            courseText: courseAssist.courseText,
            imageOffsetText: imageOffsetText,
            warningText: warning,
            infoText: courseAssist.message,
            tone: tone
        )
    }

    private static func headingSourceText(heading: CLHeading?, accuracy: Double?) -> String {
        guard let heading, heading.trueHeading >= 0 else {
            return "True --"
        }

        guard let accuracy else {
            return "True --"
        }

        return "True ±\(accuracy.degreesText)"
    }

    private static func offsetFromHeadingAccuracy(
        headingAccuracyDegrees: Double?,
        distanceMeters: Double?
    ) -> Double? {
        guard
            let headingAccuracyDegrees,
            let distanceMeters
        else {
            return nil
        }

        return abs(tan(headingAccuracyDegrees * .pi / 180) * distanceMeters)
    }

    private static func combinedHorizontalOffset(gpsAccuracy: Double?, headingOffset: Double?) -> Double? {
        switch (gpsAccuracy, headingOffset) {
        case (.some(let gps), .some(let heading)):
            return sqrt(gps * gps + heading * heading)
        case (.some(let gps), .none):
            return gps
        case (.none, .some(let heading)):
            return heading
        case (.none, .none):
            return nil
        }
    }
}

struct WindCourseAssist {
    let isActive: Bool
    let correctionDegrees: Double
    let activeAccuracyDegrees: Double?
    let courseText: String
    let message: String?

    static let unavailable = WindCourseAssist(
        isActive: false,
        correctionDegrees: 0,
        activeAccuracyDegrees: nil,
        courseText: "Kurs --",
        message: nil
    )

    static func make(location: CLLocation?, heading: CLHeading?) -> WindCourseAssist {
        guard
            let location,
            location.speed >= 0.8,
            location.course >= 0,
            location.course < 360,
            location.courseAccuracy > 0
        else {
            return .unavailable
        }

        let courseAccuracy = location.courseAccuracy
        let courseText = "Kurs ±\(courseAccuracy.degreesText)"

        guard let heading, heading.trueHeading >= 0 else {
            return WindCourseAssist(
                isActive: false,
                correctionDegrees: 0,
                activeAccuracyDegrees: nil,
                courseText: courseText,
                message: "Kurs verfügbar, aber True-North-Heading fehlt."
            )
        }

        let correction = signedAngleDegrees(from: heading.trueHeading, to: location.course)
        let pointsAlongCourse = abs(correction) <= 25
        let courseIsUseful = courseAccuracy <= 20

        guard pointsAlongCourse, courseIsUseful else {
            let message = pointsAlongCourse
                ? "Kurs verfügbar, aber noch zu ungenau."
                : "Kurs verfügbar, aber Kamera zeigt nicht in Gehrichtung."
            return WindCourseAssist(
                isActive: false,
                correctionDegrees: 0,
                activeAccuracyDegrees: nil,
                courseText: courseText,
                message: message
            )
        }

        return WindCourseAssist(
            isActive: true,
            correctionDegrees: correction,
            activeAccuracyDegrees: courseAccuracy,
            courseText: "Kurs aktiv ±\(courseAccuracy.degreesText)",
            message: "Kurs-Assist korrigiert seitlich um \(correction.degreesText)."
        )
    }

    private static func signedAngleDegrees(from source: Double, to target: Double) -> Double {
        let value = (target - source + 540).truncatingRemainder(dividingBy: 360) - 180
        return value
    }
}

private extension Double {
    var metersText: String {
        if self >= 1000 {
            return (self / 1000).formatted(.number.precision(.fractionLength(2))) + " km"
        }
        return formatted(.number.precision(.fractionLength(0))) + " m"
    }

    var degreesText: String {
        formatted(.number.precision(.fractionLength(1))) + "°"
    }
}
