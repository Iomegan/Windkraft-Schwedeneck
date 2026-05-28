//
//  ContentView.swift
//  Windkraft Schwedeneck
//
//  Created by Daniel Witt on 20.05.26.
//

import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model = WindARViewModel()
    @State private var hasAcceptedDisclaimer = false
    @State private var selectedMainView = WindMainView.ar
    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            if hasAcceptedDisclaimer {
                mainExperience
                    .transition(.opacity)
            } else {
                StartDisclaimerView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasAcceptedDisclaimer = true
                    }
                    requestRequiredPermissions()
                }
                .transition(.opacity)
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.25), value: hasAcceptedDisclaimer)
        .onAppear {
            refreshCameraAuthorization()
            if hasAcceptedDisclaimer {
                requestRequiredPermissions()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else {
                return
            }

            refreshCameraAuthorization()
            if hasAcceptedDisclaimer {
                model.startLocationUpdates()
            }
        }
        .onDisappear {
            model.stopLocationUpdates()
        }
    }

    @ViewBuilder
    private var mainExperience: some View {
        if let permissionPresentation {
            RequiredPermissionsView(
                presentation: permissionPresentation,
                requestPermissions: requestRequiredPermissions,
                openSettings: openAppSettings
            )
            .transition(.opacity)
        } else {
            switch selectedMainView {
            case .ar:
                arExperience
            case .map:
                WindMapView(model: model) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedMainView = .ar
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var arExperience: some View {
        ZStack {
            WindARView(model: model)
                .ignoresSafeArea()

            WindOverlayCanvas(
                projections: model.projections,
                drawsOverlay: model.visualizationStatus.drawsOverlay,
                skyMask: model.skyMask,
                skyOcclusionEnabled: model.skyOcclusionEnabled,
                lightEnvironment: model.lightEnvironment
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                StatusBar(model: model) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedMainView = .map
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer()

                CalibrationPanel(model: model)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    private var permissionPresentation: WindPermissionPresentation? {
        let cameraNeedsRequest = cameraAuthorizationStatus == .notDetermined
        let cameraBlocked = cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted
        let locationNeedsRequest = model.locationAuthorizationStatus == .notDetermined
        let locationBlocked = model.locationAuthorizationStatus == .denied || model.locationAuthorizationStatus == .restricted

        guard cameraNeedsRequest || cameraBlocked || locationNeedsRequest || locationBlocked else {
            return nil
        }

        var items: [WindPermissionItem] = []

        if cameraNeedsRequest || cameraBlocked {
            items.append(
                WindPermissionItem(
                    systemImage: "camera.viewfinder",
                    title: "Kamera",
                    detail: "Die App legt die Windkraftanlagen direkt über das Live-Bild. Ohne Kamera kann sie nicht zeigen, wie die Anlagen aus deinem Blickwinkel wirken."
                )
            )
        }

        if locationNeedsRequest || locationBlocked {
            items.append(
                WindPermissionItem(
                    systemImage: "location.fill",
                    title: "Standort",
                    detail: "Die App braucht deinen Standort und deine Höhe, um Entfernung, Richtung und Größe der Anlagen passend zu berechnen."
                )
            )
        }

        let isBlocked = cameraBlocked || locationBlocked
        return WindPermissionPresentation(
            title: isBlocked ? "Freigaben fehlen" : "Freigaben benötigt",
            detail: isBlocked
                ? "Bitte erlaube Kamera und Standort in den iOS-Einstellungen, damit die Visualisierung funktionieren kann."
                : "Bitte erlaube Kamera und Standort. Die Daten werden nur genutzt, um die Anlagen im Live-Bild richtig einzuordnen.",
            primaryButtonTitle: isBlocked ? "Einstellungen öffnen" : "Freigaben erlauben",
            opensSettings: isBlocked,
            items: items
        )
    }

    private func requestRequiredPermissions() {
        requestCameraPermission {
            model.startLocationUpdates()
        }
    }

    private func requestCameraPermission(then completion: @escaping @MainActor () -> Void = {}) {
        refreshCameraAuthorization()

        guard cameraAuthorizationStatus == .notDetermined else {
            completion()
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in
                refreshCameraAuthorization()
                completion()
            }
        }
    }

    private func refreshCameraAuthorization() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }
}

private enum WindMainView {
    case ar
    case map
}

private struct WindPermissionPresentation {
    let title: String
    let detail: String
    let primaryButtonTitle: String
    let opensSettings: Bool
    let items: [WindPermissionItem]
}

private struct WindPermissionItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let detail: String
}

private struct RequiredPermissionsView: View {
    let presentation: WindPermissionPresentation
    let requestPermissions: () -> Void
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("Renderd App Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("Windkraft Schwedeneck")
                        .font(.custom("Helvetica", size: 30).weight(.semibold))
                        .foregroundStyle(UBSWelcomeStyle.heading)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(presentation.title)
                        .font(.custom("Helvetica", size: 23).weight(.semibold))
                        .foregroundStyle(UBSWelcomeStyle.heading)

                    Text(presentation.detail)
                        .font(.custom("Helvetica", size: 17))
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 14) {
                    ForEach(presentation.items) { item in
                        PermissionReasonRow(item: item)
                    }
                }

                Button {
                    if presentation.opensSettings {
                        openSettings()
                    } else {
                        requestPermissions()
                    }
                } label: {
                    Text(presentation.primaryButtonTitle)
                        .font(.custom("Helvetica", size: 19).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(UBSWelcomeButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UBSWelcomeStyle.background)
        .foregroundStyle(UBSWelcomeStyle.bodyText)
        .tint(UBSWelcomeStyle.heading)
    }
}

private struct PermissionReasonRow: View {
    let item: WindPermissionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(UBSWelcomeStyle.heading)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.custom("Helvetica", size: 17).weight(.semibold))
                    .foregroundStyle(UBSWelcomeStyle.heading)

                Text(item.detail)
                    .font(.custom("Helvetica", size: 15))
                    .foregroundStyle(UBSWelcomeStyle.secondaryText)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StartDisclaimerView: View {
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("Renderd App Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("Windkraft Schwedeneck")
                        .font(.custom("Helvetica", size: 30).weight(.semibold))
                        .foregroundStyle(UBSWelcomeStyle.heading)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Hinweis")
                        .font(.custom("Helvetica", size: 23).weight(.semibold))
                        .foregroundStyle(UBSWelcomeStyle.heading)

                    Text("Die Unabhängige Bürgergemeinschaft Schwedeneck (UBS) möchte mit dieser App dabei helfen, die derzeit in der Gemeinde in Planung befindlichen Windkraftanlagen aus realen Perspektiven besser einzuordnen und die Diskussion darüber sachlicher und transparenter zu gestalten. Bürgerinnen und Bürger können damit von verschiedenen Standorten innerhalb der Gemeinde selbst nachvollziehen, ob und in welchem Ausmaß die Anlagen sichtbar wären. Die UBS möchte damit einen Beitrag zur persönlichen Meinungsbildung und den öffentlichen Austausch beitragen.")

                    Text("Es wurden die bekannten Standorte, Höhen und technischen Daten sorgfältig umgesetzt. Trotzdem bleibt die Darstellung eine Näherung: GPS, Kompass, AR-Tracking, Gelände, Verdeckung, Licht und Planungsdaten können von der Realität abweichen. Eine Haftung für die Richtigkeit wird nicht übernommen.")

                    Text("Aktuell wird die aus dem aktuellen Stand der Planung größtmögliche Anzahl und Höhe der Anlagen gezeigt. Betreiber der App ist Daniel Witt, der sie im Auftrag der Unabhängigen Bürgergemeinschaft Schwedeneck (UBS) entwickelt hat.")
                        .foregroundStyle(UBSWelcomeStyle.secondaryText)
                }
                .font(.custom("Helvetica", size: 17))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Weitere Informationen")
                        .font(.custom("Helvetica", size: 15).weight(.semibold))
                        .foregroundStyle(UBSWelcomeStyle.heading)

                    Link("www.ubs-schwedeneck.de", destination: URL(string: "https://www.ubs-schwedeneck.de")!)
                        .multilineTextAlignment(.leading)

                    Text("Immer wieder aufkommende Fragen zum Thema beantwortet die UBS hier:")
                        .font(.custom("Helvetica", size: 14))
                        .foregroundStyle(UBSWelcomeStyle.secondaryText)

                    Link("www.ubs-schwedeneck.de/windkraft-faq", destination: URL(string: "https://www.ubs-schwedeneck.de/windkraft-faq")!)
                        .multilineTextAlignment(.leading)

                    Text("Dieses Projekt ist als Open Source verfügbar:")
                        .font(.custom("Helvetica", size: 14))
                        .foregroundStyle(UBSWelcomeStyle.secondaryText)

                    Link(destination: URL(string: "https://github.com/Iomegan/Windkraft-Schwedeneck")!) {
                        Text("www.github.com/Iomegan/Windkraft-Schwedeneck")
                            .multilineTextAlignment(.leading)
                    }
                }
                .font(.custom("Helvetica", size: 17))
                .tint(UBSWelcomeStyle.heading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.easeInOut.speed(0.25)) {
                        onConfirm()
                    }
                } label: {
                    Text("Verstanden und starten")
                        .font(.custom("Helvetica", size: 19).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(UBSWelcomeButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UBSWelcomeStyle.background)
        .foregroundStyle(UBSWelcomeStyle.bodyText)
        .tint(UBSWelcomeStyle.heading)
    }
}

private enum UBSWelcomeStyle {
    static let background = Color(red: 101.0 / 255.0, green: 139.0 / 255.0, blue: 214.0 / 255.0)
    static let buttonBackground = Color(red: 255.0 / 255.0, green: 224.0 / 255.0, blue: 0.0 / 255.0)
    static let heading = Color(red: 255.0 / 255.0, green: 224.0 / 255.0, blue: 0.0 / 255.0)
    static let bodyText = Color(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 245.0 / 255.0)
    static let secondaryText = bodyText.opacity(0.72)
    static let buttonText = Color(red: 44.0 / 255.0, green: 89.0 / 255.0, blue: 171.0 / 255.0)
}

private struct UBSWelcomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(UBSWelcomeStyle.buttonText)
            .background(UBSWelcomeStyle.buttonBackground.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(UBSWelcomeStyle.buttonBackground, lineWidth: 1)
            }
    }
}

private struct WindOverlayCanvas: View {
    let projections: [WindProjection]
    let drawsOverlay: Bool
    let skyMask: WindSkyMask
    let skyOcclusionEnabled: Bool
    let lightEnvironment: WindLightEnvironment

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, _ in
                guard drawsOverlay, !projections.isEmpty else {
                    return
                }

                if skyOcclusionEnabled, skyMask.hasSamples {
                    context.clip(to: skyMaskPath(skyMask))
                }

                for projection in projections {
                    drawTurbine(projection, date: timeline.date, in: &context)
                }
            }
        }
    }

    private func skyMaskPath(_ skyMask: WindSkyMask) -> Path {
        Path { path in
            for rect in skyMask.skyRects {
                path.addRect(rect)
            }
        }
    }

    private func drawTurbine(_ projection: WindProjection, date: Date, in context: inout GraphicsContext) {
        let lightFactor = lightEnvironment.renderFactor
        let turbineFill = Color(
            red: 0.72 + 0.18 * lightFactor,
            green: 0.70 + 0.18 * lightFactor,
            blue: 0.66 + 0.20 * lightFactor
        )
        .opacity(0.28 + 0.46 * lightFactor)
        let turbineEdge = Color(
            red: 0.70 + 0.18 * lightFactor,
            green: 0.68 + 0.18 * lightFactor,
            blue: 0.64 + 0.20 * lightFactor
        )
        .opacity(0.16 + 0.20 * lightFactor)
        let markerColor = Color(
            red: 0.58 + 0.28 * lightFactor,
            green: 0.06 + 0.04 * lightFactor,
            blue: 0.04 + 0.04 * lightFactor
        )
        .opacity(0.24 + 0.46 * lightFactor)
        let sunShadowOpacity = projection.sunShadowStrength * (0.35 + 0.65 * lightFactor)
        let radius = max(projection.rotorRadiusPixels, 1)
        let pixelsPerMeter = radius / CGFloat(projection.rotorDiameterMeters / 2)
        let outlineWidth = min(max(pixelsPerMeter * 0.14, 0.25), 0.8)
        let towerBaseWidth = max(pixelsPerMeter * 5.0, 1.4)
        let towerTopWidth = max(pixelsPerMeter * 3.0, 0.9)
        let nacelleLength = max(pixelsPerMeter * 20.0, 4.5)
        let nacelleHeight = max(pixelsPerMeter * 5.2, 1.6)
        let hubRadius = max(pixelsPerMeter * 2.4, 1.0)
        let bladeRootChord = max(pixelsPerMeter * 4.2, 1.0)
        let bladeTipChord = max(pixelsPerMeter * 0.35, 0.25)
        let rotorPhase = date.timeIntervalSinceReferenceDate * 12.0
        let nacelleVisibleLength = nacelleLength * sqrt(max(0, 1 - projection.rotorFacingScale * projection.rotorFacingScale))
        let nacelleDrawLength = max(nacelleVisibleLength, nacelleLength * 0.12)

        let tower = towerPath(
            base: projection.base,
            hub: projection.hub,
            baseWidth: towerBaseWidth,
            topWidth: towerTopWidth
        )
        context.fill(tower, with: .color(turbineFill))
        applySunShade(to: tower, side: projection.sunShadowSide, opacity: sunShadowOpacity, in: &context)
        context.stroke(tower, with: .color(turbineEdge), lineWidth: outlineWidth)

        let nacelle = nacellePath(
            hub: projection.hub,
            length: nacelleDrawLength,
            height: nacelleHeight,
            side: projection.nacelleSide
        )
        context.fill(nacelle, with: .color(turbineFill))
        context.fill(nacelleMarkerPath(
            hub: projection.hub,
            length: nacelleDrawLength,
            height: nacelleHeight,
            side: projection.nacelleSide
        ), with: .color(markerColor))
        applySunShade(to: nacelle, side: projection.sunShadowSide, opacity: sunShadowOpacity, in: &context)
        context.stroke(nacelle, with: .color(turbineEdge), lineWidth: outlineWidth)

        for angle in [-90.0, 30.0, 150.0] {
            let blade = bladePath(
                hub: projection.hub,
                angleDegrees: angle + rotorPhase,
                radius: radius,
                hubRadius: hubRadius,
                rootChord: bladeRootChord,
                tipChord: bladeTipChord,
                facingScale: projection.rotorFacingScale
            )
            context.fill(blade, with: .color(turbineFill))
            context.fill(bladeTipMarkerPath(
                hub: projection.hub,
                angleDegrees: angle + rotorPhase,
                radius: radius,
                markerLength: max(radius * 0.12, pixelsPerMeter * 7.5),
                tipChord: bladeTipChord,
                facingScale: projection.rotorFacingScale
            ), with: .color(markerColor))
            applySunShade(to: blade, side: projection.sunShadowSide, opacity: sunShadowOpacity, in: &context)
            context.stroke(blade, with: .color(turbineEdge), lineWidth: outlineWidth)
        }

        let spinner = Path(ellipseIn: CGRect(
            x: projection.hub.x - hubRadius,
            y: projection.hub.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        ))
        context.fill(spinner, with: .color(turbineFill))
        applySunShade(to: spinner, side: projection.sunShadowSide, opacity: sunShadowOpacity, in: &context)
        context.stroke(spinner, with: .color(turbineEdge), lineWidth: outlineWidth)
    }

    private func applySunShade(to path: Path, side: CGFloat, opacity: Double, in context: inout GraphicsContext) {
        guard opacity > 0.005 else {
            return
        }

        let bounds = path.boundingRect.insetBy(dx: -1, dy: -1)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let shadeWidth = bounds.width * 0.58
        let shadeX = side < 0 ? bounds.minX : bounds.maxX - shadeWidth
        let shadeRect = CGRect(
            x: shadeX,
            y: bounds.minY,
            width: shadeWidth,
            height: bounds.height
        )
        var shadedContext = context
        shadedContext.clip(to: path)
        shadedContext.fill(Path(shadeRect), with: .color(.black.opacity(opacity)))
    }

    private func towerPath(base: CGPoint, hub: CGPoint, baseWidth: CGFloat, topWidth: CGFloat) -> Path {
        let axis = normalized(CGVector(dx: hub.x - base.x, dy: hub.y - base.y))
        let perpendicular = CGPoint(x: -axis.dy, y: axis.dx)
        let top = CGPoint(
            x: hub.x - axis.dx * topWidth * 0.25,
            y: hub.y - axis.dy * topWidth * 0.25
        )

        return Path { path in
            path.move(to: CGPoint(x: base.x - perpendicular.x * baseWidth / 2, y: base.y - perpendicular.y * baseWidth / 2))
            path.addLine(to: CGPoint(x: base.x + perpendicular.x * baseWidth / 2, y: base.y + perpendicular.y * baseWidth / 2))
            path.addLine(to: CGPoint(x: top.x + perpendicular.x * topWidth / 2, y: top.y + perpendicular.y * topWidth / 2))
            path.addLine(to: CGPoint(x: top.x - perpendicular.x * topWidth / 2, y: top.y - perpendicular.y * topWidth / 2))
            path.closeSubpath()
        }
    }

    private func nacellePath(hub: CGPoint, length: CGFloat, height: CGFloat, side: CGFloat) -> Path {
        let nose = CGPoint(x: hub.x - side * length * 0.35, y: hub.y)
        let tail = CGPoint(x: hub.x + side * length * 0.65, y: hub.y)
        return Path { path in
            path.move(to: CGPoint(x: nose.x, y: hub.y - height * 0.28))
            path.addQuadCurve(
                to: CGPoint(x: tail.x, y: hub.y - height * 0.40),
                control: CGPoint(x: hub.x + side * length * 0.22, y: hub.y - height * 0.62)
            )
            path.addLine(to: CGPoint(x: tail.x + side * length * 0.10, y: hub.y + height * 0.10))
            path.addQuadCurve(
                to: CGPoint(x: nose.x, y: hub.y + height * 0.32),
                control: CGPoint(x: hub.x + side * length * 0.18, y: hub.y + height * 0.58)
            )
            path.closeSubpath()
        }
    }

    private func nacelleMarkerPath(hub: CGPoint, length: CGFloat, height: CGFloat, side: CGFloat) -> Path {
        let markerWidth = length * 0.28
        let markerHeight = height * 0.62
        let markerX = side > 0 ? hub.x + length * 0.34 : hub.x - length * 0.62

        return Path(roundedRect: CGRect(
            x: markerX,
            y: hub.y - markerHeight * 0.5,
            width: markerWidth,
            height: markerHeight
        ), cornerRadius: max(markerHeight * 0.12, 0.4))
    }

    private func bladePath(
        hub: CGPoint,
        angleDegrees: Double,
        radius: CGFloat,
        hubRadius: CGFloat,
        rootChord: CGFloat,
        tipChord: CGFloat,
        facingScale: CGFloat
    ) -> Path {
        let angle = angleDegrees * .pi / 180
        let root = rotorPoint(hub: hub, radius: hubRadius * 0.75, angle: angle, facingScale: facingScale)
        let shoulder = rotorPoint(hub: hub, radius: radius * 0.24, angle: angle, facingScale: facingScale)
        let tip = rotorPoint(hub: hub, radius: radius, angle: angle, facingScale: facingScale)
        let direction = normalized(CGVector(dx: tip.x - root.x, dy: tip.y - root.y))
        let perpendicular = CGPoint(x: -direction.dy, y: direction.dx)
        let chordScale = max(0.45, sqrt(facingScale))
        let scaledRootChord = rootChord * chordScale
        let scaledTipChord = tipChord * chordScale
        let twist = CGPoint(x: perpendicular.x * scaledRootChord * 0.35, y: perpendicular.y * scaledRootChord * 0.35)

        return Path { path in
            path.move(to: CGPoint(x: root.x + perpendicular.x * scaledRootChord / 2, y: root.y + perpendicular.y * scaledRootChord / 2))
            path.addQuadCurve(
                to: CGPoint(x: tip.x + perpendicular.x * scaledTipChord / 2, y: tip.y + perpendicular.y * scaledTipChord / 2),
                control: CGPoint(x: shoulder.x + perpendicular.x * scaledRootChord * 0.62 + twist.x, y: shoulder.y + perpendicular.y * scaledRootChord * 0.62 + twist.y)
            )
            path.addQuadCurve(
                to: CGPoint(x: root.x - perpendicular.x * scaledRootChord / 2, y: root.y - perpendicular.y * scaledRootChord / 2),
                control: CGPoint(x: shoulder.x - perpendicular.x * scaledRootChord * 0.42 - twist.x * 0.5, y: shoulder.y - perpendicular.y * scaledRootChord * 0.42 - twist.y * 0.5)
            )
            path.closeSubpath()
        }
    }

    private func bladeTipMarkerPath(
        hub: CGPoint,
        angleDegrees: Double,
        radius: CGFloat,
        markerLength: CGFloat,
        tipChord: CGFloat,
        facingScale: CGFloat
    ) -> Path {
        let angle = angleDegrees * .pi / 180
        let innerRadius = max(radius - markerLength, radius * 0.82)
        let innerChord = max(tipChord * 2.4, tipChord + 0.35)
        let inner = rotorPoint(hub: hub, radius: innerRadius, angle: angle, facingScale: facingScale)
        let tip = rotorPoint(hub: hub, radius: radius, angle: angle, facingScale: facingScale)
        let direction = normalized(CGVector(dx: tip.x - inner.x, dy: tip.y - inner.y))
        let perpendicular = CGPoint(x: -direction.dy, y: direction.dx)
        let chordScale = max(0.45, sqrt(facingScale))
        let scaledInnerChord = innerChord * chordScale
        let scaledTipChord = tipChord * chordScale

        return Path { path in
            path.move(to: CGPoint(x: inner.x + perpendicular.x * scaledInnerChord / 2, y: inner.y + perpendicular.y * scaledInnerChord / 2))
            path.addLine(to: CGPoint(x: tip.x + perpendicular.x * scaledTipChord / 2, y: tip.y + perpendicular.y * scaledTipChord / 2))
            path.addLine(to: CGPoint(x: tip.x - perpendicular.x * scaledTipChord / 2, y: tip.y - perpendicular.y * scaledTipChord / 2))
            path.addLine(to: CGPoint(x: inner.x - perpendicular.x * scaledInnerChord / 2, y: inner.y - perpendicular.y * scaledInnerChord / 2))
            path.closeSubpath()
        }
    }

    private func rotorPoint(hub: CGPoint, radius: CGFloat, angle: Double, facingScale: CGFloat) -> CGPoint {
        CGPoint(
            x: hub.x + CGFloat(cos(angle)) * radius * facingScale,
            y: hub.y + CGFloat(sin(angle)) * radius
        )
    }

    private func normalized(_ vector: CGVector) -> CGVector {
        let length = max(hypot(vector.dx, vector.dy), 0.0001)
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}

private struct StatusBar: View {
    @ObservedObject var model: WindARViewModel
    let onShowMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image("windkraftanlage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 28)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.turbineTitle)
                        .font(.headline)
                    Text(model.interfaceMode == .expert ? model.statusLine : model.locationStatus)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    onShowMap()
                } label: {
                    ViewThatFits {
                        Label("Karte", systemImage: "map")
                        Text("Karte")
                    }
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .accessibilityLabel("Karte anzeigen")

                InterfaceModeButton(model: model)
            }

            VisualizationStatusView(status: model.visualizationStatus)

            if model.interfaceMode == .expert {
                if let projection = model.projection {
                    HStack(spacing: 12) {
                        MetricPill(title: "Distanz", value: projection.distanceText)
                        MetricPill(title: "Richtung", value: projection.bearingText)
                        MetricPill(title: "Höhe", value: model.altitudeText)
                    }
                } else {
                    HStack(spacing: 12) {
                        MetricPill(title: "Distanz", value: model.distanceText)
                        MetricPill(title: "Richtung", value: model.bearingText)
                        MetricPill(title: "Höhe", value: model.altitudeText)
                    }
                }

                AccuracySummaryView(summary: model.accuracySummary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.22), value: model.interfaceMode)
    }
}

private struct InterfaceModeButton: View {
    @ObservedObject var model: WindARViewModel

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                model.interfaceMode = model.interfaceMode == .expert ? .simplified : .expert
            }
        } label: {
            Text(buttonTitle)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .accessibilityLabel(accessibilityTitle)
        .contentShape(.rect)
    }

    private var buttonTitle: String {
        model.interfaceMode == .expert ? "Experte" : "Einfach"
    }

    private var accessibilityTitle: String {
        model.interfaceMode == .expert ? "Zur einfachen Ansicht wechseln" : "Zur Expertenansicht wechseln"
    }
}

private struct VisualizationStatusView: View {
    let status: WindVisualizationStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.tone.symbolName)
                .foregroundStyle(status.tone.color)
                .font(.subheadline)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

private struct AccuracySummaryView: View {
    let summary: WindAccuracySummary
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: summary.tone.symbolName)
                    .foregroundStyle(summary.tone.color)
                    .font(.caption)
                Text("Genauigkeit")
                    .font(.caption.weight(.semibold))
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                AccuracyPill(value: summary.gpsText)
                AccuracyPill(value: summary.altitudeText)
                AccuracyPill(value: summary.compassText)
                AccuracyPill(value: summary.courseText)
                AccuracyPill(value: summary.imageOffsetText)
            }

            if let warningText = summary.warningText {
                Text(warningText)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let infoText = summary.infoText {
                Text(infoText)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

private struct AccuracyPill: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.85))
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalibrationPanel: View {
    @ObservedObject var model: WindARViewModel

    var body: some View {
        VStack(spacing: 12) {
            if model.interfaceMode == .expert {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Label("Ausrichtung", systemImage: "scope")
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Toggle("Manuell", isOn: $model.manualCalibrationEnabled)
                            .font(.caption.weight(.semibold))
                            .toggleStyle(.switch)
                            .accessibilityLabel("Manuelle Ausrichtung")
                            .tint(.accentColor)
                    }

                    if model.manualCalibrationEnabled {
                        CalibrationSlider(
                            title: "Seitlich",
                            value: $model.headingOffsetDegrees,
                            range: -12...12,
                            step: 0.1,
                            unit: "°"
                        )

                        CalibrationSlider(
                            title: "Vertikal",
                            value: $model.pitchOffsetDegrees,
                            range: -8...8,
                            step: 0.1,
                            unit: "°"
                        )
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "location.north.line.fill")
                                .foregroundStyle(.primary.opacity(0.85))
                            Text("Automatisch")
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.85))
                            Spacer()
                        }
                        .frame(height: 32)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                ViewThatFits {
                    Label("Anlagen von Bäumen/Gebäuden verdecken lassen", systemImage: "building.2")
                    Label("Bäumen/Gebäuden verdecken Anlagen", systemImage: "building.2")
                    Label("Bäumen/Gebäuden", systemImage: "building.2")
                }
                .font(.caption.weight(.semibold))

                Spacer()

                Toggle("Einbeziehen", isOn: $model.skyOcclusionEnabled)
                    .font(.caption.weight(.semibold))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Bäume und Gebäude davor berücksichtigen")
                    .tint(.accentColor)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Label("Rotor", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Text(model.rotorYawDetailText)
                        .font(.caption2)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Picker("Rotor-Ausrichtung", selection: $model.rotorOrientationMode) {
                    ForEach(WindRotorOrientationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Rotor-Ausrichtung")

                if model.rotorOrientationMode == .manual {
                    CalibrationSlider(
                        title: "Wind aus",
                        value: $model.manualWindFromDegrees,
                        range: 0...359,
                        step: 1,
                        unit: "°"
                    )
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.22), value: model.interfaceMode)
        .animation(.easeInOut(duration: 0.22), value: model.rotorOrientationMode)
    }
}

private struct CalibrationSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))) + unit)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.85))
            }

            Slider(value: $value, in: range, step: step)
        }
    }
}
