//
//  GeoMath.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 20.05.26.
//

import CoreLocation
import Foundation

struct ENUOffset {
    let east: Double
    let north: Double
    let up: Double
}

enum GeoMath {
    private static let semiMajorAxis = 6_378_137.0
    private static let flattening = 1.0 / 298.257_223_563

    static func enuOffset(
        from origin: CLLocationCoordinate2D,
        altitudeMSL originAltitude: Double,
        to target: CLLocationCoordinate2D,
        altitudeMSL targetAltitude: Double
    ) -> ENUOffset {
        let originECEF = ecef(latitude: origin.latitude, longitude: origin.longitude, altitude: originAltitude)
        let targetECEF = ecef(latitude: target.latitude, longitude: target.longitude, altitude: targetAltitude)

        let deltaX = targetECEF.x - originECEF.x
        let deltaY = targetECEF.y - originECEF.y
        let deltaZ = targetECEF.z - originECEF.z

        let latitude = origin.latitude.degreesToRadians
        let longitude = origin.longitude.degreesToRadians
        let sinLatitude = sin(latitude)
        let cosLatitude = cos(latitude)
        let sinLongitude = sin(longitude)
        let cosLongitude = cos(longitude)

        let east = -sinLongitude * deltaX + cosLongitude * deltaY
        let north = -sinLatitude * cosLongitude * deltaX
            - sinLatitude * sinLongitude * deltaY
            + cosLatitude * deltaZ
        let up = cosLatitude * cosLongitude * deltaX
            + cosLatitude * sinLongitude * deltaY
            + sinLatitude * deltaZ

        return ENUOffset(east: east, north: north, up: up)
    }

    static func initialBearing(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double {
        let originLatitude = origin.latitude.degreesToRadians
        let targetLatitude = target.latitude.degreesToRadians
        let deltaLongitude = (target.longitude - origin.longitude).degreesToRadians

        let y = sin(deltaLongitude) * cos(targetLatitude)
        let x = cos(originLatitude) * sin(targetLatitude)
            - sin(originLatitude) * cos(targetLatitude) * cos(deltaLongitude)

        return atan2(y, x).radiansToDegrees.normalizedDegrees
    }

    private static func ecef(latitude: Double, longitude: Double, altitude: Double) -> (x: Double, y: Double, z: Double) {
        let latitudeRadians = latitude.degreesToRadians
        let longitudeRadians = longitude.degreesToRadians
        let eccentricitySquared = flattening * (2 - flattening)
        let sinLatitude = sin(latitudeRadians)
        let cosLatitude = cos(latitudeRadians)
        let radius = semiMajorAxis / sqrt(1 - eccentricitySquared * sinLatitude * sinLatitude)

        let x = (radius + altitude) * cosLatitude * cos(longitudeRadians)
        let y = (radius + altitude) * cosLatitude * sin(longitudeRadians)
        let z = (radius * (1 - eccentricitySquared) + altitude) * sinLatitude

        return (x, y, z)
    }
}

private extension Double {
    var degreesToRadians: Double {
        self * .pi / 180
    }

    var radiansToDegrees: Double {
        self * 180 / .pi
    }

    var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}
