//
//  WindARView.swift
//  Windkraft Schwedeneck
//
//  Created by Codex on 20.05.26.
//

import ARKit
import Combine
import RealityKit
import SwiftUI

struct WindARView: UIViewRepresentable {
    @ObservedObject var model: WindARViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.environment.background = .cameraFeed()
        arView.renderOptions.insert(.disableMotionBlur)

        guard ARWorldTrackingConfiguration.isSupported else {
            context.coordinator.install(on: arView)
            model.setARStatus("ARKit wird auf diesem Gerät nicht unterstützt.")
            return arView
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.isLightEstimationEnabled = true

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.install(on: arView)
        model.setARStatus("AR läuft")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.model = model
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.session.pause()
    }

    final class Coordinator {
        weak var arView: ARView?
        var model: WindARViewModel
        private var updateSubscription: Cancellable?
        private var lastProjectionUpdate = Date.distantPast

        init(model: WindARViewModel) {
            self.model = model
        }

        func install(on arView: ARView) {
            self.arView = arView
            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateProjection()
                }
            }
        }

        func stop() {
            updateSubscription?.cancel()
            updateSubscription = nil
        }

        @MainActor
        private func updateProjection() {
            guard Date().timeIntervalSince(lastProjectionUpdate) > 1.0 / 30.0 else {
                return
            }
            lastProjectionUpdate = Date()

            guard
                let arView,
                let frame = arView.session.currentFrame,
                arView.bounds.width > 0,
                arView.bounds.height > 0
            else {
                return
            }

            let orientation = arView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
            model.updateProjection(
                frame: frame,
                viewportSize: arView.bounds.size,
                orientation: orientation
            )
        }
    }
}
