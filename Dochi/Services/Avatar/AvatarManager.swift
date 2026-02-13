import Foundation
import QuartzCore
import RealityKit
import VRMKit
import VRMRealityKit

@available(macOS 15.0, *)
@MainActor
@Observable
final class AvatarManager {
    private(set) var vrmEntity: VRMEntity?
    private(set) var isLoaded = false
    private(set) var loadError: String?

    private var updateTimer: Timer?
    private var lipSyncTimer: Timer?
    private var blinkTimer: Timer?
    private let startTime = CACurrentMediaTime()

    // Face tracking
    private let faceTracker = FaceTrackingService()
    private var smoothFaceX: Float = 0
    private var smoothFaceY: Float = 0

    // MARK: - Model Loading

    func loadModel(named name: String) throws -> Entity {
        Log.avatar.info("Loading VRM model: \(name)")

        let vrm = try VRMLoader().load(named: "\(name).vrm")
        let loader = VRMEntityLoader(vrm: vrm)
        let vrmEntity = try loader.loadEntity()

        self.vrmEntity = vrmEntity
        self.isLoaded = true
        self.loadError = nil

        // Rotate 180° to face camera
        vrmEntity.entity.transform.rotation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))

        // Auto-position: use head bone to center face in view
        if let headNode = vrmEntity.humanoid.node(for: .head) {
            let headWorldPos = headNode.position(relativeTo: nil)
            vrmEntity.entity.position = SIMD3<Float>(0, -headWorldPos.y, 0)
            Log.avatar.info("Head bone Y=\(headWorldPos.y), offset applied")
        } else {
            // Fallback: use bounding box
            let bounds = vrmEntity.entity.visualBounds(relativeTo: nil)
            let centerY = (bounds.min.y + bounds.max.y) * 0.5
            vrmEntity.entity.position = SIMD3<Float>(0, -centerY, 0)
            Log.avatar.info("No head bone, using bbox center Y=\(centerY)")
        }

        applyIdlePose()
        startUpdateLoop()
        startIdleBlink()
        faceTracker.startTracking()

        Log.avatar.info("VRM model loaded successfully")
        return vrmEntity.entity
    }

    // MARK: - Idle Pose (Arms Down)

    private func applyIdlePose() {
        guard let vrmEntity else { return }
        let h = vrmEntity.humanoid

        // Upper arms: bring down ~70° from T-pose
        h.node(for: .leftUpperArm)?.transform.rotation =
            simd_quatf(angle: 1.22, axis: SIMD3(0, 0, 1))
        h.node(for: .rightUpperArm)?.transform.rotation =
            simd_quatf(angle: -1.22, axis: SIMD3(0, 0, 1))

        // Lower arms: slight inward bend
        h.node(for: .leftLowerArm)?.transform.rotation =
            simd_quatf(angle: -0.26, axis: SIMD3(0, 1, 0))
        h.node(for: .rightLowerArm)?.transform.rotation =
            simd_quatf(angle: 0.26, axis: SIMD3(0, 1, 0))
    }

    // MARK: - Expression Control

    func applyExpression(for state: InteractionState) {
        guard vrmEntity != nil else { return }

        resetBlendShapes()

        switch state {
        case .idle:
            startIdleBlink()

        case .listening:
            vrmEntity?.setBlendShape(value: 0.2, for: .preset(.fun))
            startIdleBlink()

        case .processing:
            vrmEntity?.setBlendShape(value: 0.15, for: .preset(.sorrow))
            startFastBlink()

        case .speaking:
            vrmEntity?.setBlendShape(value: 0.1, for: .preset(.joy))
            startLipSync()
        }
    }

    // MARK: - Lip Sync (Simulated)

    private func startLipSync() {
        stopLipSync()
        let syncStart = CACurrentMediaTime()
        lipSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let vrmEntity = self.vrmEntity else { return }
                let elapsed = CACurrentMediaTime() - syncStart
                let amp = Self.simulatedAmplitude(at: elapsed)
                vrmEntity.setBlendShape(value: CGFloat(amp), for: .preset(.a))
            }
        }
    }

    private func stopLipSync() {
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        vrmEntity?.setBlendShape(value: 0, for: .preset(.a))
    }

    // MARK: - Blink

    private func startIdleBlink() {
        stopBlink()
        scheduleBlink(interval: 3.5)
    }

    private func startFastBlink() {
        stopBlink()
        scheduleBlink(interval: 1.8)
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    private func scheduleBlink(interval: TimeInterval) {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performBlink() }
        }
    }

    private func performBlink() {
        guard let vrmEntity else { return }
        vrmEntity.setBlendShape(value: 1.0, for: .preset(.blink))
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            vrmEntity.setBlendShape(value: 0, for: .preset(.blink))
        }
    }

    // MARK: - Frame Update (Spring Bones + Idle + Face Tracking)

    private func startUpdateLoop() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let vrmEntity = self.vrmEntity else { return }
                let time = CACurrentMediaTime() - self.startTime
                self.applyPerFrameAnimation(time: time)
                vrmEntity.update(at: time)
            }
        }
    }

    private func applyPerFrameAnimation(time: CFTimeInterval) {
        guard let vrmEntity else { return }
        let h = vrmEntity.humanoid

        // --- Breathing: spine oscillation ---
        if let spine = h.node(for: .spine) {
            let breathe = Float(sin(time * 2.1)) * 0.008
            spine.transform.rotation = simd_quatf(angle: breathe, axis: SIMD3(1, 0, 0))
        }

        // --- Face tracking smoothing ---
        if faceTracker.isTracking {
            smoothFaceX += (faceTracker.faceX - smoothFaceX) * 0.15
            smoothFaceY += (faceTracker.faceY - smoothFaceY) * 0.15
        } else {
            // Decay toward center when face lost
            smoothFaceX *= 0.95
            smoothFaceY *= 0.95
        }

        let hasFaceData = abs(smoothFaceX) > 0.01 || abs(smoothFaceY) > 0.01

        // --- Head rotation ---
        if let head = h.node(for: .head) {
            if hasFaceData {
                // Face tracking: avatar head follows user position
                // Negate X so avatar mirrors user (look left when user moves left)
                let yaw = -smoothFaceX * 0.7
                let pitch = smoothFaceY * 0.4
                head.transform.rotation =
                    simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) *
                    simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
            } else {
                // Idle micro-movement
                let nod = Float(sin(time * 1.3)) * 0.012
                let tilt = Float(sin(time * 0.9)) * 0.008
                head.transform.rotation =
                    simd_quatf(angle: nod, axis: SIMD3(1, 0, 0)) *
                    simd_quatf(angle: tilt, axis: SIMD3(0, 0, 1))
            }
        }

        // --- Eye gaze via lookAt blend shapes ---
        if hasFaceData {
            // Clear all directions first
            for preset: BlendShapePreset in [.lookLeft, .lookRight, .lookUp, .lookDown] {
                vrmEntity.setBlendShape(value: 0, for: .preset(preset))
            }
            // Horizontal (negated to mirror)
            if smoothFaceX > 0 {
                vrmEntity.setBlendShape(value: CGFloat(smoothFaceX * 0.8), for: .preset(.lookLeft))
            } else {
                vrmEntity.setBlendShape(value: CGFloat(-smoothFaceX * 0.8), for: .preset(.lookRight))
            }
            // Vertical
            if smoothFaceY > 0 {
                vrmEntity.setBlendShape(value: CGFloat(smoothFaceY * 0.5), for: .preset(.lookUp))
            } else {
                vrmEntity.setBlendShape(value: CGFloat(-smoothFaceY * 0.5), for: .preset(.lookDown))
            }
        } else {
            for preset: BlendShapePreset in [.lookLeft, .lookRight, .lookUp, .lookDown] {
                vrmEntity.setBlendShape(value: 0, for: .preset(preset))
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        stopLipSync()
        stopBlink()
        faceTracker.stopTracking()
        vrmEntity = nil
        isLoaded = false
        Log.avatar.info("Avatar manager cleaned up")
    }

    // MARK: - Helpers

    private func resetBlendShapes() {
        stopLipSync()
        stopBlink()
        guard let vrmEntity else { return }

        let presets: [BlendShapePreset] = [
            .neutral, .joy, .angry, .sorrow, .fun,
            .a, .i, .u, .e, .o, .blink,
        ]
        for preset in presets {
            vrmEntity.setBlendShape(value: 0, for: .preset(preset))
        }
    }

    private static func simulatedAmplitude(at time: CFTimeInterval) -> Float {
        let base = sin(time * 12.0) * 0.4
        let detail = sin(time * 22.0) * 0.2
        let variation = sin(time * 5.0) * 0.1
        return max(0, min(1, Float(0.35 + base + detail + variation)))
    }
}

// MARK: - Errors

enum AvatarError: Error, LocalizedError {
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            "VRM 모델 파일을 찾을 수 없습니다: \(name)"
        }
    }
}
