import SwiftUI
import RealityKit
#if canImport(AppKit)
import AppKit
#endif

@available(macOS 15.0, *)
struct AvatarView: View {
    let interactionState: InteractionState
    let modelName: String
    @AppStorage("avatarModelName") private var storedModelName = AvatarModelCatalog.defaultModelID
    @AppStorage("avatarCameraZoom") private var storedCameraZoom = AppSettings.avatarCameraZoomDefault

    @State private var manager = AvatarManager()
    @State private var rootEntity: Entity?
    @State private var errorMessage: String?

    private var selectedModelName: String {
        AvatarModelCatalog.normalizedModelID(storedModelName)
    }

    private var selectedCameraZoom: Double {
        AppSettings.normalizedAvatarCameraZoom(storedCameraZoom)
    }

    private var cameraDistance: Float {
        let baseDistance: Float = 0.34
        return baseDistance / Float(selectedCameraZoom)
    }

    private var cameraConfigurationID: Int {
        Int((selectedCameraZoom * 100).rounded())
    }

    var body: some View {
        ZStack {
            if let rootEntity {
                RealityView { content in
                    content.add(rootEntity)

                    // Camera: upper body + face framing
                    let camera = PerspectiveCamera()
                    camera.camera.fieldOfViewInDegrees = 22
                    camera.look(
                        at: SIMD3<Float>(0, 0.04, 0),
                        from: SIMD3<Float>(0, 0.08, cameraDistance),
                        relativeTo: nil
                    )
                    content.add(camera)

                    // Soft key light from upper-right
                    let keyLight = DirectionalLight()
                    keyLight.light.intensity = 800
                    keyLight.light.color = .white
                    keyLight.look(
                        at: SIMD3<Float>(0, 0, 0),
                        from: SIMD3<Float>(1, 1.5, 1),
                        relativeTo: nil
                    )
                    content.add(keyLight)

                    // Fill light from left
                    let fillLight = DirectionalLight()
                    fillLight.light.intensity = 300
                    fillLight.light.color = .init(white: 0.9, alpha: 1)
                    fillLight.look(
                        at: SIMD3<Float>(0, 0, 0),
                        from: SIMD3<Float>(-1, 0.5, 0.5),
                        relativeTo: nil
                    )
                    content.add(fillLight)
                }
                .id(cameraConfigurationID)
            } else if let errorMessage {
                placeholderView(message: errorMessage)
            } else {
                ProgressView("모델 로딩 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            NightSkyBackground()
        )
        #if canImport(AppKit)
        .overlay {
            AvatarZoomInputOverlay(
                onScrollDeltaY: applyScrollZoom(deltaY:),
                onMagnificationDelta: applyMagnifyZoom(delta:)
            )
        }
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: selectedModelName) {
            await loadSelectedModel(named: selectedModelName)
        }
        .onChange(of: modelName) { _, newValue in
            let normalized = AvatarModelCatalog.normalizedModelID(newValue)
            if storedModelName != normalized {
                storedModelName = normalized
            }
        }
        .onChange(of: storedCameraZoom) { _, newValue in
            let normalized = AppSettings.normalizedAvatarCameraZoom(newValue)
            if normalized != newValue {
                storedCameraZoom = normalized
            }
        }
        .onChange(of: interactionState) { _, newState in
            manager.applyExpression(for: newState)
        }
        .onDisappear {
            manager.cleanup()
            rootEntity = nil
        }
    }

    // MARK: - Placeholder

    private func placeholderView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("VRM 모델을 설정해주세요")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadSelectedModel(named name: String) async {
        manager.cleanup()
        rootEntity = nil
        errorMessage = nil

        do {
            let entity = try manager.loadModel(named: name)
            rootEntity = entity
        } catch {
            errorMessage = "모델 '\(name)' 로딩 실패: \(error.localizedDescription)"
            Log.avatar.error("Failed to load avatar \(name): \(error.localizedDescription)")
        }
    }

    private func applyScrollZoom(deltaY: CGFloat) {
        // Mouse wheel / two-finger vertical scroll while hovering avatar
        let sensitivity = 0.002
        updateCameraZoom(selectedCameraZoom + Double(deltaY) * sensitivity)
    }

    private func applyMagnifyZoom(delta: CGFloat) {
        // Trackpad pinch delta from NSEvent.magnification
        updateCameraZoom(selectedCameraZoom * (1 + Double(delta)))
    }

    private func updateCameraZoom(_ value: Double) {
        let normalized = AppSettings.normalizedAvatarCameraZoom(value)
        let quantized = (normalized * 100).rounded() / 100
        guard quantized != storedCameraZoom else { return }
        storedCameraZoom = quantized
    }
}

#if canImport(AppKit)
private struct AvatarZoomInputOverlay: NSViewRepresentable {
    let onScrollDeltaY: (CGFloat) -> Void
    let onMagnificationDelta: (CGFloat) -> Void

    func makeNSView(context: Context) -> AvatarZoomInputNSView {
        let view = AvatarZoomInputNSView()
        view.onScrollDeltaY = onScrollDeltaY
        view.onMagnificationDelta = onMagnificationDelta
        return view
    }

    func updateNSView(_ nsView: AvatarZoomInputNSView, context: Context) {
        nsView.onScrollDeltaY = onScrollDeltaY
        nsView.onMagnificationDelta = onMagnificationDelta
    }
}

private final class AvatarZoomInputNSView: NSView {
    var onScrollDeltaY: ((CGFloat) -> Void)?
    var onMagnificationDelta: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : (event.deltaY * 10)
        onScrollDeltaY?(deltaY)
    }

    override func magnify(with event: NSEvent) {
        onMagnificationDelta?(event.magnification)
    }
}
#endif

// MARK: - Night Sky Background

private struct NightSkyBackground: View {
    @State private var stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Sky gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.12),
                        Color(red: 0.05, green: 0.05, blue: 0.22),
                        Color(red: 0.08, green: 0.06, blue: 0.18),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Stars
                Canvas { context, size in
                    for star in stars {
                        let rect = CGRect(
                            x: star.x * size.width,
                            y: star.y * size.height,
                            width: star.size,
                            height: star.size
                        )
                        context.opacity = star.opacity
                        context.fill(
                            Circle().path(in: rect),
                            with: .color(.white)
                        )
                    }
                }
            }
            .onAppear {
                generateStars(in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                generateStars(in: newSize)
            }
        }
    }

    private func generateStars(in size: CGSize) {
        var result: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = []
        let count = Int(size.width * size.height / 800)
        for _ in 0..<count {
            result.append((
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 0.5...2.5),
                opacity: Double.random(in: 0.3...1.0)
            ))
        }
        stars = result
    }
}
