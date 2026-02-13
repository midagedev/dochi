import SwiftUI
import RealityKit

@available(macOS 15.0, *)
struct AvatarView: View {
    let interactionState: InteractionState

    @State private var manager = AvatarManager()
    @State private var rootEntity: Entity?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let rootEntity {
                RealityView { content in
                    content.add(rootEntity)

                    // Camera: upper body + face framing
                    let camera = PerspectiveCamera()
                    camera.camera.fieldOfViewInDegrees = 35
                    camera.look(
                        at: SIMD3<Float>(0, 0, 0),
                        from: SIMD3<Float>(0, 0.03, 0.55),
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            do {
                let entity = try manager.loadModel(named: "default_avatar")
                rootEntity = entity
            } catch {
                errorMessage = error.localizedDescription
                Log.avatar.error("Failed to load avatar: \(error.localizedDescription)")
            }
        }
        .onChange(of: interactionState) { _, newState in
            manager.applyExpression(for: newState)
        }
        .onDisappear {
            manager.cleanup()
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
}

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
