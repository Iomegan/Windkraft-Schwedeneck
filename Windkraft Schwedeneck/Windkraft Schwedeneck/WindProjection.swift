//
//  WindProjection.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 20.05.26.
//

import ARKit
import CoreLocation
import Foundation
import simd
import UIKit

struct WindTurbine: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let groundAltitudeMSL: Double
    let totalHeight: Double
    let rotorDiameter: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hubHeight: Double {
        totalHeight - rotorDiameter / 2
    }

    var hubAltitudeMSL: Double {
        groundAltitudeMSL + hubHeight
    }

    var tipAltitudeMSL: Double {
        groundAltitudeMSL + totalHeight
    }

    var rotorBottomAltitudeMSL: Double {
        groundAltitudeMSL + hubHeight - rotorDiameter / 2
    }

    static let schwedeneckPrototypes = [
        WindTurbine(
            name: "WEA 1",
            latitude: 54.458512,
            longitude: 10.084441,
            groundAltitudeMSL: 39,
            totalHeight: 230,
            rotorDiameter: 175
        ),
        WindTurbine(
            name: "WEA 2",
            latitude: 54.459011,
            longitude: 10.089719,
            groundAltitudeMSL: 38,
            totalHeight: 230,
            rotorDiameter: 175
        ),
        WindTurbine(
            name: "WEA 3",
            latitude: 54.459759,
            longitude: 10.096843,
            groundAltitudeMSL: 37,
            totalHeight: 230,
            rotorDiameter: 175
        ),
        WindTurbine(
            name: "WEA 4",
            latitude: 54.463399,
            longitude: 10.095556,
            groundAltitudeMSL: 30,
            totalHeight: 230,
            rotorDiameter: 175
        ),
        WindTurbine(
            name: "WEA 5",
            latitude: 54.466391,
            longitude: 10.098903,
            groundAltitudeMSL: 34,
            totalHeight: 230,
            rotorDiameter: 175
        ),
        WindTurbine(
            name: "WEA 6",
            latitude: 54.469698,
            longitude: 10.102905,
            groundAltitudeMSL: 34,
            totalHeight: 230,
            rotorDiameter: 175
        )
    ]
}

struct WindProjection {
    let turbineName: String
    let base: CGPoint
    let hub: CGPoint
    let rotorTop: CGPoint
    let rotorBottom: CGPoint
    let rotorRadiusPixels: CGFloat
    let rotorDiameterMeters: Double
    let isInFront: Bool
    let distanceMeters: Double
    let bearingDegrees: Double
    let rotorYawDegrees: Double
    let rotorViewAngleDegrees: Double
    let rotorFacingScale: CGFloat
    let nacelleSide: CGFloat
    let sunShadowSide: CGFloat
    let sunShadowStrength: Double

    var distanceText: String {
        if distanceMeters >= 1000 {
            return (distanceMeters / 1000).formatted(.number.precision(.fractionLength(2))) + " km"
        }
        return distanceMeters.formatted(.number.precision(.fractionLength(0))) + " m"
    }

    var bearingText: String {
        bearingDegrees.formatted(.number.precision(.fractionLength(0))) + "°"
    }

    var windDirectionText: String {
        WindDirectionFormatter.text(for: rotorYawDegrees)
    }

    var overlayBounds: CGRect {
        let rotorRect = CGRect(
            x: hub.x - rotorRadiusPixels,
            y: hub.y - rotorRadiusPixels,
            width: rotorRadiusPixels * 2,
            height: rotorRadiusPixels * 2
        )
        let mastRect = CGRect(
            x: min(base.x, hub.x),
            y: min(base.y, hub.y),
            width: abs(base.x - hub.x),
            height: abs(base.y - hub.y)
        ).insetBy(dx: -max(rotorRadiusPixels * 0.08, 8), dy: -max(rotorRadiusPixels * 0.08, 8))

        return rotorRect.union(mastRect)
    }

    func visualizationStatus(in viewportSize: CGSize) -> WindVisualizationStatus {
        guard isInFront else {
            return .behindCamera(turnDirection: "langsam nach links oder rechts")
        }

        guard isInsideViewport(viewportSize) else {
            return .outsideView(direction: outsideDirection(in: viewportSize))
        }

        return .visible
    }

    private func isInsideViewport(_ viewportSize: CGSize) -> Bool {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return false
        }

        let padding = max(rotorRadiusPixels, 24)
        let viewport = CGRect(origin: .zero, size: viewportSize).insetBy(dx: -padding, dy: -padding)
        let rotorRect = CGRect(
            x: hub.x - rotorRadiusPixels,
            y: hub.y - rotorRadiusPixels,
            width: rotorRadiusPixels * 2,
            height: rotorRadiusPixels * 2
        )

        return viewport.contains(base)
            || viewport.contains(hub)
            || viewport.contains(rotorTop)
            || viewport.contains(rotorBottom)
            || viewport.intersects(rotorRect)
    }

    private func outsideDirection(in viewportSize: CGSize) -> String {
        var directions: [String] = []

        if hub.x < 0 {
            directions.append("nach links")
        } else if hub.x > viewportSize.width {
            directions.append("nach rechts")
        }

        if hub.y < 0 {
            directions.append("nach oben")
        } else if hub.y > viewportSize.height {
            directions.append("nach unten")
        }

        if directions.isEmpty {
            return "langsam weiter"
        }

        return directions.joined(separator: " und ")
    }
}

enum WindProjectionCalculator {
    static func project(
        turbine: WindTurbine,
        from observer: CLLocation,
        frame: ARFrame,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation,
        headingOffsetDegrees: Double,
        pitchOffsetDegrees: Double,
        rotorYawDegrees: Double
    ) -> WindProjection {
        let cameraPosition = frame.camera.transform.translation
        let cameraRight = frame.camera.transform.xAxis

        let base = worldPoint(
            turbine: turbine,
            altitudeMSL: turbine.groundAltitudeMSL,
            observer: observer,
            cameraPosition: cameraPosition,
            cameraRight: cameraRight,
            headingOffsetDegrees: headingOffsetDegrees,
            pitchOffsetDegrees: pitchOffsetDegrees
        )

        let hub = worldPoint(
            turbine: turbine,
            altitudeMSL: turbine.hubAltitudeMSL,
            observer: observer,
            cameraPosition: cameraPosition,
            cameraRight: cameraRight,
            headingOffsetDegrees: headingOffsetDegrees,
            pitchOffsetDegrees: pitchOffsetDegrees
        )

        let top = worldPoint(
            turbine: turbine,
            altitudeMSL: turbine.tipAltitudeMSL,
            observer: observer,
            cameraPosition: cameraPosition,
            cameraRight: cameraRight,
            headingOffsetDegrees: headingOffsetDegrees,
            pitchOffsetDegrees: pitchOffsetDegrees
        )

        let bottom = worldPoint(
            turbine: turbine,
            altitudeMSL: turbine.rotorBottomAltitudeMSL,
            observer: observer,
            cameraPosition: cameraPosition,
            cameraRight: cameraRight,
            headingOffsetDegrees: headingOffsetDegrees,
            pitchOffsetDegrees: pitchOffsetDegrees
        )

        let projectedBase = frame.camera.projectPoint(base, orientation: orientation, viewportSize: viewportSize)
        let projectedHub = frame.camera.projectPoint(hub, orientation: orientation, viewportSize: viewportSize)
        let projectedTop = frame.camera.projectPoint(top, orientation: orientation, viewportSize: viewportSize)
        let projectedBottom = frame.camera.projectPoint(bottom, orientation: orientation, viewportSize: viewportSize)

        let hubCameraPoint = simd_inverse(frame.camera.transform) * SIMD4<Float>(hub.x, hub.y, hub.z, 1)
        let radius = max(
            projectedHub.distance(to: projectedTop),
            projectedHub.distance(to: projectedBottom),
            2
        )
        let observerBearingFromTurbine = GeoMath.initialBearing(from: turbine.coordinate, to: observer.coordinate)
        let rotorViewAngle = angularDifferenceDegrees(rotorYawDegrees, observerBearingFromTurbine)
        let facingScale = CGFloat(max(abs(cos(rotorViewAngle.degreesToRadians)), 0.12))
        let nacelleSide = CGFloat(sin(rotorViewAngle.degreesToRadians) >= 0 ? 1 : -1)
        let sunPosition = WindSunPosition.make(date: Date(), coordinate: observer.coordinate)
        let bearingToTurbine = GeoMath.initialBearing(from: observer.coordinate, to: turbine.coordinate)
        let relativeSunAngle = angularDifferenceDegrees(bearingToTurbine, sunPosition.azimuthDegrees)
        let sideLight = abs(sin(relativeSunAngle.degreesToRadians))
        let elevationFactor = 1 - min(max(sunPosition.elevationDegrees, 0), 65) / 65
        let shadowStrength = sunPosition.elevationDegrees > 0 ? (0.04 + 0.12 * elevationFactor) * sideLight : 0
        let shadowSide: CGFloat = relativeSunAngle >= 0 ? -1 : 1

        return WindProjection(
            turbineName: turbine.name,
            base: projectedBase,
            hub: projectedHub,
            rotorTop: projectedTop,
            rotorBottom: projectedBottom,
            rotorRadiusPixels: radius,
            rotorDiameterMeters: turbine.rotorDiameter,
            isInFront: hubCameraPoint.z < 0,
            distanceMeters: observer.distance(from: CLLocation(latitude: turbine.latitude, longitude: turbine.longitude)),
            bearingDegrees: GeoMath.initialBearing(from: observer.coordinate, to: turbine.coordinate),
            rotorYawDegrees: rotorYawDegrees,
            rotorViewAngleDegrees: rotorViewAngle,
            rotorFacingScale: facingScale,
            nacelleSide: nacelleSide,
            sunShadowSide: shadowSide,
            sunShadowStrength: shadowStrength
        )
    }

    private static func worldPoint(
        turbine: WindTurbine,
        altitudeMSL: Double,
        observer: CLLocation,
        cameraPosition: SIMD3<Float>,
        cameraRight: SIMD3<Float>,
        headingOffsetDegrees: Double,
        pitchOffsetDegrees: Double
    ) -> SIMD3<Float> {
        let enu = GeoMath.enuOffset(
            from: observer.coordinate,
            altitudeMSL: observer.validAltitudeMSL,
            to: turbine.coordinate,
            altitudeMSL: altitudeMSL
        )

        var arOffset = SIMD3<Float>(
            Float(enu.east),
            Float(enu.up),
            Float(-enu.north)
        )

        if headingOffsetDegrees != 0 {
            let headingRotation = simd_quatf(angle: Float(headingOffsetDegrees.degreesToRadians), axis: SIMD3<Float>(0, 1, 0))
            arOffset = headingRotation.act(arOffset)
        }

        if pitchOffsetDegrees != 0 {
            let pitchRotation = simd_quatf(angle: Float(pitchOffsetDegrees.degreesToRadians), axis: simd_normalize(cameraRight))
            arOffset = pitchRotation.act(arOffset)
        }

        return cameraPosition + arOffset
    }

    private static func angularDifferenceDegrees(_ first: Double, _ second: Double) -> Double {
        var difference = (second - first).truncatingRemainder(dividingBy: 360)

        if difference > 180 {
            difference -= 360
        } else if difference < -180 {
            difference += 360
        }

        return difference
    }
}

private struct WindSunPosition {
    let azimuthDegrees: Double
    let elevationDegrees: Double

    static func make(date: Date, coordinate: CLLocationCoordinate2D) -> WindSunPosition {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(components.hour ?? 0)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3600
        let gamma = 2 * Double.pi / 365 * (dayOfYear - 1 + (hour - 12) / 24)
        let equationOfTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma)
            - 0.040849 * sin(2 * gamma)
        )
        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)
        let trueSolarMinutes = (hour * 60 + equationOfTime + 4 * coordinate.longitude)
            .truncatingRemainder(dividingBy: 1440)
        let hourAngleDegrees = trueSolarMinutes / 4 < 0
            ? trueSolarMinutes / 4 + 180
            : trueSolarMinutes / 4 - 180
        let hourAngle = hourAngleDegrees.degreesToRadians
        let latitude = coordinate.latitude.degreesToRadians
        let cosZenith = sin(latitude) * sin(declination)
            + cos(latitude) * cos(declination) * cos(hourAngle)
        let zenith = acos(min(max(cosZenith, -1), 1))
        let elevation = 90 - zenith.radiansToDegrees
        let azimuth = atan2(
            -sin(hourAngle),
            tan(declination) * cos(latitude) - sin(latitude) * cos(hourAngle)
        ).radiansToDegrees.normalizedDegrees

        return WindSunPosition(azimuthDegrees: azimuth, elevationDegrees: elevation)
    }
}

private extension CLLocation {
    var validAltitudeMSL: Double {
        verticalAccuracy > 0 ? altitude : 0
    }
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    var xAxis: SIMD3<Float> {
        SIMD3(columns.0.x, columns.0.y, columns.0.z)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
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
        return value < 0 ? value + 360 : value
    }
}
