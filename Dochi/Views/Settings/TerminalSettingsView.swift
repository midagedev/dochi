import SwiftUI

/// 설정 > 터미널 — 쉘 경로, 폰트, LLM 연동
struct TerminalSettingsView: View {
    var settings: AppSettings

    var body: some View {
        Form {
            // 쉘 설정
            Section("쉘") {
                HStack {
                    Text("쉘 경로")
                    Spacer()
                    TextField("쉘 경로", text: Binding(
                        get: { settings.terminalShellPath },
                        set: { settings.terminalShellPath = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                }

                HStack {
                    Text("최대 세션 수")
                    Spacer()
                    Stepper(
                        "\(settings.terminalMaxSessions)",
                        value: Binding(
                            get: { settings.terminalMaxSessions },
                            set: { settings.terminalMaxSessions = $0 }
                        ),
                        in: 1...16
                    )
                }

                HStack {
                    Text("명령 타임아웃 (초)")
                    Spacer()
                    TextField("", value: Binding(
                        get: { settings.terminalCommandTimeout },
                        set: { settings.terminalCommandTimeout = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            }

            // 표시 설정
            Section("표시") {
                HStack {
                    Text("폰트 크기: \(settings.terminalFontSize)pt")
                    Slider(
                        value: Binding(
                            get: { Double(settings.terminalFontSize) },
                            set: { settings.terminalFontSize = Int($0) }
                        ),
                        in: 10...24,
                        step: 1
                    )
                }

                Text("미리보기")
                    .font(.system(size: CGFloat(settings.terminalFontSize), design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(.vertical, 2)

                HStack {
                    Text("최대 출력 버퍼 (줄)")
                    Spacer()
                    TextField("", value: Binding(
                        get: { settings.terminalMaxBufferLines },
                        set: { settings.terminalMaxBufferLines = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            }

            // 동작 설정
            Section("동작") {
                Toggle("닫기 전 확인", isOn: Binding(
                    get: { settings.terminalConfirmOnClose },
                    set: { settings.terminalConfirmOnClose = $0 }
                ))

                Toggle("패널 자동 표시 (세션 생성 시)", isOn: Binding(
                    get: { settings.terminalAutoShowPanel },
                    set: { settings.terminalAutoShowPanel = $0 }
                ))
            }

            // LLM 연동
            Section("LLM 연동") {
                Toggle("LLM 터미널 명령 실행 허용", isOn: Binding(
                    get: { settings.terminalLLMEnabled },
                    set: { settings.terminalLLMEnabled = $0 }
                ))

                if settings.terminalLLMEnabled {
                    Toggle("매번 실행 전 확인", isOn: Binding(
                        get: { settings.terminalLLMConfirmAlways },
                        set: { settings.terminalLLMConfirmAlways = $0 }
                    ))
                    .padding(.leading, 16)

                    Text("LLM이 terminal.run 도구를 통해 명령을 실행할 수 있습니다. restricted 카테고리로 분류됩니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // 단축키 안내
            Section("단축키") {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow("Ctrl+`", "터미널 패널 토글")
                    shortcutRow("Ctrl+Shift+`", "새 세션")
                    shortcutRow("Cmd+L", "출력 지우기 (터미널 포커스 시)")
                    shortcutRow("Up/Down", "명령 히스토리 탐색")
                    shortcutRow("Ctrl+C", "실행 중인 명령 중단")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
