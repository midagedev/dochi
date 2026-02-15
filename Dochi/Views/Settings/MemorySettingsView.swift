import SwiftUI

/// 설정 > AI > 메모리 자동 정리 설정 뷰
struct MemorySettingsView: View {
    var settings: AppSettings
    var memoryConsolidator: MemoryConsolidator?

    @State private var showChangelog = false

    var body: some View {
        Form {
            // MARK: - 기본 설정
            Section {
                Toggle("메모리 자동 정리", isOn: Binding(
                    get: { settings.memoryConsolidationEnabled },
                    set: { settings.memoryConsolidationEnabled = $0 }
                ))

                Text("대화 종료 시 주요 사실과 결정을 자동으로 추출하여 메모리에 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.memoryConsolidationEnabled {
                    Stepper(
                        "최소 메시지 수: \(settings.memoryConsolidationMinMessages)개",
                        value: Binding(
                            get: { settings.memoryConsolidationMinMessages },
                            set: { settings.memoryConsolidationMinMessages = max(1, $0) }
                        ),
                        in: 1...20
                    )

                    Text("assistant 메시지가 이 수 이상인 대화에서만 자동 정리를 실행합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("상태 배너 표시", isOn: Binding(
                        get: { settings.memoryConsolidationBannerEnabled },
                        set: { settings.memoryConsolidationBannerEnabled = $0 }
                    ))
                }
            } header: {
                SettingsSectionHeader(
                    title: "메모리 자동 정리",
                    helpContent: "대화가 끝나면 중요한 사실과 결정을 자동으로 추출하여 메모리에 기록합니다. 이미 기록된 내용은 자동으로 중복 제거됩니다."
                )
            }

            // MARK: - 모델 설정
            Section {
                Picker("정리 모델", selection: Binding(
                    get: { settings.memoryConsolidationModel },
                    set: { settings.memoryConsolidationModel = $0 }
                )) {
                    Text("경량 모델 (비용 절약)").tag("light")
                    Text("기본 모델 (고품질)").tag("default")
                }

                Text("경량 모델은 gpt-4o-mini 등 저비용 모델을 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(
                    title: "추출 모델",
                    helpContent: "사실 추출에 사용할 LLM 모델을 선택합니다. 경량 모델은 비용이 적지만 정확도가 낮을 수 있습니다."
                )
            }

            // MARK: - 크기 한도
            Section {
                Toggle("자동 아카이브", isOn: Binding(
                    get: { settings.memoryAutoArchiveEnabled },
                    set: { settings.memoryAutoArchiveEnabled = $0 }
                ))

                Text("메모리 크기가 한도를 초과하면 오래된 내용을 자동으로 아카이브합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.memoryAutoArchiveEnabled {
                    HStack {
                        Text("개인 메모리 한도")
                        Spacer()
                        Text(formatSize(settings.memoryPersonalSizeLimit))
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.memoryPersonalSizeLimit) },
                            set: { settings.memoryPersonalSizeLimit = Int($0) }
                        ),
                        in: 2000...30000,
                        step: 1000
                    )

                    HStack {
                        Text("워크스페이스 메모리 한도")
                        Spacer()
                        Text(formatSize(settings.memoryWorkspaceSizeLimit))
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.memoryWorkspaceSizeLimit) },
                            set: { settings.memoryWorkspaceSizeLimit = Int($0) }
                        ),
                        in: 2000...30000,
                        step: 1000
                    )

                    HStack {
                        Text("에이전트 메모리 한도")
                        Spacer()
                        Text(formatSize(settings.memoryAgentSizeLimit))
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.memoryAgentSizeLimit) },
                            set: { settings.memoryAgentSizeLimit = Int($0) }
                        ),
                        in: 1000...20000,
                        step: 1000
                    )
                }
            } header: {
                SettingsSectionHeader(
                    title: "크기 관리",
                    helpContent: "메모리가 지정한 크기를 초과하면 오래된 항목을 별도 파일로 아카이브합니다. 아카이브된 메모리는 삭제되지 않으며 memory_archive 디렉토리에 보관됩니다."
                )
            }

            // MARK: - 변경 이력
            Section {
                Button {
                    showChangelog = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text("변경 이력 보기")
                        Spacer()
                        if let consolidator = memoryConsolidator {
                            Text("\(consolidator.changelog.count)건")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("이력")
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showChangelog) {
            if let consolidator = memoryConsolidator {
                MemoryDiffSheetView(
                    changelog: consolidator.changelog,
                    onRevert: { id in consolidator.revert(changeId: id) }
                )
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes >= 1000 {
            return String(format: "%.1fK", Double(bytes) / 1000.0)
        }
        return "\(bytes)"
    }
}
