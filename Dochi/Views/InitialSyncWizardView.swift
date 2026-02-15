import SwiftUI

/// G-3: 초기 동기화 위저드 (3단계: 안내 -> 진행률 -> 완료)
struct InitialSyncWizardView: View {
    let syncEngine: SyncEngine
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case intro
        case progress
        case complete
    }

    @State private var currentStep: Step = .intro
    @State private var uploadProgress: Double = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("초기 동기화")
                    .font(.headline)
                Spacer()
                if currentStep == .intro {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            // Step content
            Group {
                switch currentStep {
                case .intro:
                    introView
                case .progress:
                    progressView
                case .complete:
                    completeView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Step 1: Intro

    private var introView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("로컬 데이터를 클라우드에 업로드합니다")
                .font(.title3)

            VStack(alignment: .leading, spacing: 8) {
                infoRow(icon: "bubble.left.and.bubble.right", text: "대화 기록")
                infoRow(icon: "brain", text: "메모리 데이터")
                infoRow(icon: "rectangle.3.group", text: "칸반 보드")
                infoRow(icon: "person.crop.circle", text: "프로필 정보")
            }
            .padding(.horizontal, 40)

            Text("이후 다른 기기에서 동일한 계정으로 로그인하면 데이터가 자동 동기화됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button("동기화 시작") {
                startUpload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: Progress

    private var progressView: some View {
        VStack(spacing: 20) {
            Spacer()

            if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("업로드 실패")
                    .font(.title3)

                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                HStack(spacing: 12) {
                    Button("다시 시도") {
                        errorMessage = nil
                        startUpload()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("닫기") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 20)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: true)

                Text("업로드 중...")
                    .font(.title3)

                ProgressView(value: uploadProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 60)

                Text("\(Int(uploadProgress * 100))%")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(syncEngine.syncProgress.currentEntity.isEmpty ? "준비 중..." : "\(syncEngine.syncProgress.currentEntity) 동기화 중...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    // MARK: - Step 3: Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("초기 동기화 완료!")
                .font(.title3)

            Text("모든 데이터가 클라우드에 업로드되었습니다. 이제 다른 기기에서도 동일한 데이터를 사용할 수 있습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button("완료") {
                onComplete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Helpers

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
            Spacer()
        }
    }

    private func startUpload() {
        currentStep = .progress
        Task {
            do {
                try await syncEngine.initialUpload { progress in
                    uploadProgress = progress
                }
                currentStep = .complete
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
