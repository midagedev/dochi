import AVFoundation
import Vision

/// Captures the front camera and runs Vision face detection to track user's face position.
final class FaceTrackingService: NSObject, @unchecked Sendable {
    /// Normalized face X: -1 (left) to +1 (right)
    private(set) var faceX: Float = 0
    /// Normalized face Y: -1 (bottom) to +1 (top)
    private(set) var faceY: Float = 0
    /// Whether a face is currently detected
    private(set) var isTracking = false

    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.dochi.facetracking")
    private var frameSkip = 0

    func startTracking() {
        guard captureSession == nil else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.setupCapture() }
            }
        default:
            Log.avatar.warning("Camera access denied — face tracking disabled")
        }
    }

    func stopTracking() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
        captureSession = nil
        isTracking = false
    }

    private func setupCapture() {
        let session = AVCaptureSession()
        session.sessionPreset = .low

        // macOS: front camera may be .unspecified, fall back to default
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            Log.avatar.error("No camera available for face tracking")
            return
        }

        session.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        session.addOutput(videoOutput)

        captureSession = session

        sessionQueue.async {
            session.startRunning()
            Log.avatar.info("Face tracking started (Vision)")
        }
    }
}

extension FaceTrackingService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // ~10 fps face detection (skip 2 of every 3 frames)
        frameSkip += 1
        guard frameSkip % 3 == 0 else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        try? handler.perform([request])

        guard let face = request.results?.first else {
            isTracking = false
            return
        }

        let box = face.boundingBox
        faceX = Float(box.midX) * 2.0 - 1.0
        faceY = Float(box.midY) * 2.0 - 1.0
        isTracking = true
    }
}
