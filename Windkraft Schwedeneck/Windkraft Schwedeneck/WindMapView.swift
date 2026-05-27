//
//  WindMapView.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 27.05.26.
//

import CoreLocation
import MapKit
import SwiftUI

struct WindMapView: View {
    @ObservedObject var model: WindARViewModel
    let onShowAR: () -> Void

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                WindModernMapView(model: model)

            } else {
                WindLegacyMapView(model: model)
            }
        }
        .safeAreaInset(edge: .top) {
            WindMapHeader(model: model, onShowAR: onShowAR)
                .padding(.horizontal, 14)
                .padding(.top, 12)
        }
    }
}

private struct WindMapHeader: View {
    @ObservedObject var model: WindARViewModel
    let onShowAR: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "map")
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text("Karte")
                    .font(.headline)
                Text("\(model.turbineTitle) · \(model.locationStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                onShowAR()
            } label: {
                ViewThatFits {
                    Label("AR", systemImage: "camera.viewfinder")
                    Text("AR")
                }
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .accessibilityLabel("AR Ansicht anzeigen")
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
    }
}

@available(iOS 17.0, *)
private struct WindModernMapView: View {
    @ObservedObject var model: WindARViewModel
    @Namespace private var mapScope
    @State private var cameraPosition: MapCameraPosition = .region(WindMapConfiguration.schwedeneckRegion)

    var body: some View {
        Map(position: $cameraPosition, scope: mapScope) {
            ForEach(model.turbines) { turbine in
                Annotation(turbine.name, coordinate: turbine.coordinate) {
                    WindTurbineMapMarker(name: turbine.name)
                }
            }

            ForEach(WindExistingTurbine.schwedeneckExisting) { turbine in
                Annotation(turbine.name, coordinate: turbine.coordinate) {
                    WindExistingTurbineMapMarker(name: turbine.name)
                }
            }

            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
}

private struct WindLegacyMapView: View {
    @ObservedObject var model: WindARViewModel
    @State private var region = WindMapConfiguration.schwedeneckRegion

    var mapItems: [WindMapItem] {
        var items = model.turbines.map { WindMapItem(turbine: $0) }
        items.append(contentsOf: WindExistingTurbine.schwedeneckExisting.map { WindMapItem(existingTurbine: $0) })

        if let location = model.deviceLocation {
            items.append(WindMapItem(userLocation: location))
        }

        return items
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: mapItems) { item in
            MapAnnotation(coordinate: item.coordinate) {
                switch item.kind {
                case .turbine(let name):
                    WindTurbineMapMarker(name: name)
                case .existingTurbine(let name):
                    WindExistingTurbineMapMarker(name: name)
                case .user:
                    WindUserLocationMarker()
                }
            }
        }
    }
}

private struct WindTurbineMapMarker: View {
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 30, height: 30)
            Image("windkraftanlage")
                .resizable()
                .foregroundStyle(.white)
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 25)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

private struct WindExistingTurbineMapMarker: View {
    let name: String

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.9))
                    .frame(width: 28, height: 28)
                Image("windkraftanlage")
                    .resizable()
                    .foregroundStyle(.white)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 22)
            }

            VStack(spacing: 1) {
                Text(name)
                    .font(.caption2.weight(.bold))
                Text("Bestand · vsl. Rückbau")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(.orange.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), bestehende Anlage, vermutlich Rückbau")
    }
}

private struct WindUserLocationMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.18))
                .frame(width: 34, height: 34)
            Circle()
                .fill(.blue)
                .frame(width: 14, height: 14)
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
        .accessibilityLabel("Aktuelle Position")
    }
}

private enum WindMapConfiguration {
    static let schwedeneckRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.4715, longitude: 10.0940),
        span: MKCoordinateSpan(latitudeDelta: 0.115, longitudeDelta: 0.175)
    )
}

private struct WindExistingTurbine: Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    let groundAltitudeMSL: Double

    var id: String { name }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let schwedeneckExisting = [
        WindExistingTurbine(name: "Bestand 1", latitude: 54.456132, longitude: 10.099338, groundAltitudeMSL: 42),
        WindExistingTurbine(name: "Bestand 2", latitude: 54.458414, longitude: 10.100861, groundAltitudeMSL: 42),
        WindExistingTurbine(name: "Bestand 3", latitude: 54.458526, longitude: 10.096473, groundAltitudeMSL: 40)
    ]
}

private struct WindMapItem: Identifiable {
    enum Kind {
        case turbine(String)
        case existingTurbine(String)
        case user
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    init(turbine: WindTurbine) {
        id = turbine.name
        coordinate = turbine.coordinate
        kind = .turbine(turbine.name)
    }

    init(existingTurbine: WindExistingTurbine) {
        id = existingTurbine.name
        coordinate = existingTurbine.coordinate
        kind = .existingTurbine(existingTurbine.name)
    }

    init(userLocation: CLLocation) {
        id = "user-location"
        coordinate = userLocation.coordinate
        kind = .user
    }
}
