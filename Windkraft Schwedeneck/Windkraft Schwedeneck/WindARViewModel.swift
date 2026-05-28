//
//  WindARViewModel.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 20.05.26.
//

import ARKit
import Combine
@preconcurrency import CoreLocation
import Foundation
import simd
import UIKit
//import WeatherKit

@MainActor
final class WindARViewModel: NSObject, ObservableObject {
    @Published private(set) var projection: WindProjection?
    @Published private(set) var projections: [WindProjection] = []
    @Published private(set) var deviceLocation: CLLocation?
    @Published private(set) var currentHeading: CLHeading?
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationStatus = "Warte auf Standort"
    @Published private(set) var arStatus = "AR startet"
    @Published private(set) var visualizationStatus = WindVisualizationStatus.waitingForLocation
    @Published private(set) var accuracySummary = WindAccuracySummary.unavailable
    @Published private(set) var courseAssist = WindCourseAssist.unavailable
    @Published private(set) var skyMask = WindSkyMask.unavailable
    @Published private(set) var lightEnvironment = WindLightEnvironment.unavailable
    @Published private(set) var weatherWindFromDegrees: Double?
    @Published private(set) var weatherWindStatus = "Windrichtung saisonal geschätzt"
    @Published var manualCalibrationEnabled = false
    @Published var headingOffsetDegrees = 0.0
    @Published var pitchOffsetDegrees = 0.0
    @Published var skyOcclusionEnabled = false
    @Published var rotorOrientationMode = WindRotorOrientationMode.seasonal
    @Published var manualWindFromDegrees = WindSeasonalDirection.currentWindFromDegrees()
    @Published var interfaceMode = WindInterfaceMode.simplified

    let turbines = WindTurbine.schwedeneckPrototypes

    private let locationManager = CLLocationManager()
//    private let weatherService = WeatherService.shared
    private let maximumVisualizationDistance = 10_000.0
    private let weatherWindRefreshInterval: TimeInterval = 30 * 60
    private let weatherWindDistanceThreshold = 1_000.0
//    private var weatherWindTask: Task<Void, Never>?
    private var lastWeatherWindRequestDate: Date?
    private var lastWeatherWindLocation: CLLocation?

    var turbineTitle: String {
        turbines.count == 1 ? turbines[0].name : "\(turbines.count) Anlagen"
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationAuthorizationStatus = locationManager.authorizationStatus
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1
        locationManager.headingFilter = 0.5
        locationManager.headingOrientation = .portrait
    }

    var statusLine: String {
        "\(locationStatus) · \(arStatus)"
    }

    var altitudeText: String {
        guard let location = deviceLocation, location.verticalAccuracy > 0 else {
            return "--"
        }
        return location.altitude.formatted(.number.precision(.fractionLength(0))) + " m"
    }

    var distanceText: String {
        guard let distanceMeters else {
            return "--"
        }
        return formattedDistance(distanceMeters)
    }

    var bearingText: String {
        guard
            let location = deviceLocation,
            let nearest = nearestTurbine(to: location)
        else {
            return "--"
        }

        let bearing = GeoMath.initialBearing(from: location.coordinate, to: nearest.turbine.coordinate)
        return bearing.formatted(.number.precision(.fractionLength(0))) + "°"
    }

    var rotorYawDegrees: Double {
        switch rotorOrientationMode {
        case .seasonal:
            weatherWindFromDegrees ?? WindSeasonalDirection.currentWindFromDegrees()
        case .manual:
            manualWindFromDegrees
        }
    }

    var rotorYawText: String {
        WindDirectionFormatter.text(for: rotorYawDegrees)
    }

    var rotorYawDetailText: String {
        switch rotorOrientationMode {
        case .seasonal:
            weatherWindFromDegrees == nil
                ? "\(WindSeasonalDirection.seasonName()) · geschätzt aus \(rotorYawText)"
                : "Aktuell · Wind aus \(rotorYawText)"
        case .manual:
            "Wind aus \(rotorYawText)"
        }
    }

    private var distanceMeters: Double? {
        guard
            let location = deviceLocation,
            let nearest = nearestTurbine(to: location)
        else {
            return nil
        }

        return nearest.distance
    }

    func startLocationUpdates() {
        locationAuthorizationStatus = locationManager.authorizationStatus

        switch locationAuthorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginLocationStreams()
        case .denied, .restricted:
            locationStatus = "Standort nicht erlaubt"
            visualizationStatus = WindVisualizationStatus(
                title: "Standort nicht erlaubt",
                detail: "Erlaube Standortzugriff, damit die Anlage georeferenziert werden kann.",
                tone: .blocked,
                drawsOverlay: false
            )
        @unknown default:
            locationStatus = "Standortstatus unbekannt"
        }
    }

    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    func setARStatus(_ status: String) {
        guard arStatus != status else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self, self.arStatus != status else {
                return
            }

            self.arStatus = status
        }
    }

    func updateProjection(frame: ARFrame, viewportSize: CGSize, orientation: UIInterfaceOrientation) {
        lightEnvironment = WindLightEnvironment(ambientIntensity: frame.lightEstimate.map { Double($0.ambientIntensity) })

        guard let location = deviceLocation else {
            projection = nil
            projections = []
            skyMask = .unavailable
            visualizationStatus = .waitingForLocation
            accuracySummary = .unavailable
            courseAssist = .unavailable
            return
        }

        guard let nearest = nearestTurbine(to: location) else {
            projection = nil
            projections = []
            skyMask = .unavailable
            visualizationStatus = .waitingForLocation
            accuracySummary = .unavailable
            courseAssist = .unavailable
            return
        }

        let distance = nearest.distance
        let automaticCourseAssist = WindCourseAssist.make(location: location, heading: currentHeading)
        courseAssist = automaticCourseAssist
        accuracySummary = .make(
            location: location,
            heading: currentHeading,
            distanceMeters: distance,
            courseAssist: automaticCourseAssist
        )

        guard location.horizontalAccuracy > 0 else {
            projection = nil
            projections = []
            skyMask = .unavailable
            visualizationStatus = .invalidLocation
            return
        }

        guard distance <= maximumVisualizationDistance else {
            projection = nil
            projections = []
            skyMask = .unavailable
            visualizationStatus = .tooFar(distanceText: formattedDistance(distance))
            return
        }

        guard !lightEnvironment.isTooDarkForUnlitTurbine else {
            projection = nil
            projections = []
            skyMask = .unavailable
            visualizationStatus = .tooDark
            return
        }

        let usesManualCalibration = interfaceMode == .expert && manualCalibrationEnabled
        let headingOffset = usesManualCalibration ? headingOffsetDegrees : automaticCourseAssist.correctionDegrees
        let pitchOffset = usesManualCalibration ? pitchOffsetDegrees : 0

        let turbineProjections = turbines.map { turbine in
            WindProjectionCalculator.project(
                turbine: turbine,
                from: location,
                frame: frame,
                viewportSize: viewportSize,
                orientation: orientation,
                headingOffsetDegrees: headingOffset,
                pitchOffsetDegrees: pitchOffset,
                rotorYawDegrees: rotorYawDegrees
            )
        }
        let visibleProjections = turbineProjections
            .filter { $0.visualizationStatus(in: viewportSize).drawsOverlay }
            .sorted { $0.distanceMeters > $1.distanceMeters }

        projection = visibleProjections.last ?? turbineProjections.min { $0.distanceMeters < $1.distanceMeters }
        projections = visibleProjections
        updateVisualizationStatus(
            for: turbineProjections,
            visibleProjections: visibleProjections,
            location: location,
            frame: frame,
            viewportSize: viewportSize,
            orientation: orientation
        )
    }

    private func updateVisualizationStatus(
        for turbineProjections: [WindProjection],
        visibleProjections: [WindProjection],
        location: CLLocation,
        frame: ARFrame,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation
    ) {
        guard !visibleProjections.isEmpty else {
            skyMask = .unavailable
            visualizationStatus = bestUnavailableStatus(
                for: turbineProjections,
                location: location,
                viewportSize: viewportSize
            )
            return
        }

        guard skyOcclusionEnabled else {
            skyMask = .unavailable
            visualizationStatus = WindVisualizationStatus.visible.adjustedForLight(lightEnvironment)
            return
        }

        let newSkyMask = WindSkyMaskBuilder.make(
            frame: frame,
            viewportSize: viewportSize,
            orientation: orientation
        )
        skyMask = newSkyMask

        guard newSkyMask.hasSamples else {
            visualizationStatus = WindVisualizationStatus.visible.adjustedForLight(lightEnvironment)
            return
        }

        let hasVisibleSkyIntersection = visibleProjections.contains { projection in
            newSkyMask.intersects(projection.overlayBounds)
        }

        guard newSkyMask.hasSky, hasVisibleSkyIntersection else {
            visualizationStatus = WindVisualizationStatus.skyOccluded.adjustedForLight(lightEnvironment)
            return
        }

        visualizationStatus = WindVisualizationStatus
            .visibleWithSkyMask(coverageText: newSkyMask.coverageText)
            .adjustedForLight(lightEnvironment)
    }

    private func bestUnavailableStatus(
        for turbineProjections: [WindProjection],
        location: CLLocation,
        viewportSize: CGSize
    ) -> WindVisualizationStatus {
        guard let primaryProjection = turbineProjections.min(by: { $0.distanceMeters < $1.distanceMeters }) else {
            return .waitingForLocation
        }

        guard primaryProjection.isInFront else {
            return .behindCamera(turnDirection: turnDirection(to: primaryProjection, from: location))
        }

        return primaryProjection.visualizationStatus(in: viewportSize)
    }

    private func turnDirection(to projection: WindProjection, from location: CLLocation) -> String {
        guard let headingDegrees = currentHeadingDegrees else {
            return "langsam nach links oder rechts"
        }

        let difference = angularDifferenceDegrees(from: headingDegrees, to: projection.bearingDegrees)
        let magnitude = abs(difference)

        if magnitude > 155 {
            return "um"
        }

        let side = difference > 0 ? "rechts" : "links"

        if magnitude > 90 {
            return "deutlich nach \(side)"
        }

        if magnitude > 35 {
            return "mehr nach \(side)"
        }

        return "etwas nach \(side)"
    }

    private var currentHeadingDegrees: Double? {
        guard let heading = currentHeading else {
            return nil
        }

        if heading.trueHeading >= 0 {
            return heading.trueHeading
        }

        if heading.magneticHeading >= 0 {
            return heading.magneticHeading
        }

        return nil
    }

    private func angularDifferenceDegrees(from first: Double, to second: Double) -> Double {
        var difference = (second - first).truncatingRemainder(dividingBy: 360)

        if difference > 180 {
            difference -= 360
        } else if difference < -180 {
            difference += 360
        }

        return difference
    }

    private func beginLocationStreams() {
        locationManager.startUpdatingLocation()

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }

        locationStatus = "Suche genaue Position"
    }

    private func updateLocationStatus(for location: CLLocation) {
        let horizontal = location.horizontalAccuracy
        let vertical = location.verticalAccuracy

        if horizontal < 0 {
            locationStatus = "Standort ungenau"
            return
        }

        let horizontalText = horizontal.formatted(.number.precision(.fractionLength(0)))

        if vertical > 0 {
            let verticalText = vertical.formatted(.number.precision(.fractionLength(0)))
            locationStatus = "GPS ±\(horizontalText)m · Höhe ±\(verticalText)m"
        } else {
            locationStatus = "GPS ±\(horizontalText)m · Höhe fehlt"
        }
    }

    private func refreshAccuracySummary() {
        let automaticCourseAssist = WindCourseAssist.make(location: deviceLocation, heading: currentHeading)
        courseAssist = automaticCourseAssist
        accuracySummary = .make(
            location: deviceLocation,
            heading: currentHeading,
            distanceMeters: distanceMeters,
            courseAssist: automaticCourseAssist
        )
    }

//    private func refreshWeatherWindIfNeeded(for location: CLLocation) {
//        guard weatherWindTask == nil else {
//            return
//        }
//
//        guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 1_000 else {
//            return
//        }
//
//        if
//            let lastRequestDate = lastWeatherWindRequestDate,
//            Date().timeIntervalSince(lastRequestDate) < weatherWindRefreshInterval,
//            let lastLocation = lastWeatherWindLocation,
//            location.distance(from: lastLocation) < weatherWindDistanceThreshold
//        {
//            return
//        }

//        lastWeatherWindRequestDate = Date()
//        lastWeatherWindLocation = location
//        weatherWindStatus = "Windrichtung wird geladen"

//        weatherWindTask = Task { [weak self, weatherService] in
//            do {
//                let weather = try await weatherService.weather(for: location)
//                let windFromDegrees = weather.currentWeather.wind.direction.converted(to: .degrees).value
//                await MainActor.run {
//                    self?.weatherWindFromDegrees = WindDirectionFormatter.normalized(windFromDegrees)
//                    self?.weatherWindStatus = "Live-Windrichtung"
//                    self?.weatherWindTask = nil
//                }
//            } catch {
//                NSLog("Fehler beim Laden des Wetters: \(error.localizedDescription)")
//                await MainActor.run {
//                    self?.weatherWindFromDegrees = nil
//                    self?.weatherWindStatus = "Windrichtung saisonal geschätzt"
//                    self?.weatherWindTask = nil
//                }
//            }
//        }
//    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return (meters / 1000).formatted(.number.precision(.fractionLength(2))) + " km"
        }

        return meters.formatted(.number.precision(.fractionLength(0))) + " m"
    }

    private func nearestTurbine(to location: CLLocation) -> (turbine: WindTurbine, distance: Double)? {
        turbines
            .map { turbine in
                (
                    turbine: turbine,
                    distance: location.distance(from: CLLocation(latitude: turbine.latitude, longitude: turbine.longitude))
                )
            }
            .min { $0.distance < $1.distance }
    }
}

extension WindARViewModel: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorizationStatus = manager.authorizationStatus
        startLocationUpdates()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else {
            return
        }

        deviceLocation = newest
        updateLocationStatus(for: newest)
        refreshAccuracySummary()
//        refreshWeatherWindIfNeeded(for: newest)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading
        refreshAccuracySummary()
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatus = error.localizedDescription
        visualizationStatus = WindVisualizationStatus(
            title: "Standortfehler",
            detail: error.localizedDescription,
            tone: .blocked,
            drawsOverlay: false
        )
    }
}
