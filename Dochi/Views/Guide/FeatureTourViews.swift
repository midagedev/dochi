import SwiftUI

// MARK: - Tour Step Enum

/// 기능 투어 단계 (4단계)
enum TourStep: Int, CaseIterable {
    case overview = 0        // T1: 도구 카테고리 소개
    case conversation = 1   // T2: 대화의 기본
    case agentWorkspace = 2 // T3: 에이전트 & 워크스페이스
    case shortcuts = 3      // T4: 빠른 조작법
}

// MARK: - FeatureTourView (Container)

/// 기능 투어 컨테이너 뷰. 4단계를 네비게이션과 함께 관리한다.
struct FeatureTourView: View {
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var currentStep: TourStep = .overview

    var body: some View {
        VStack(spacing: 0) {
            // 단계 인디케이터
            HStack(spacing: 6) {
                ForEach(TourStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)

            Spacer()

            // 단계별 콘텐츠
            Group {
                switch currentStep {
                case .overview:
                    TourOverviewView()
                case .conversation:
                    TourConversationView()
                case .agentWorkspace:
                    TourAgentWorkspaceView()
                case .shortcuts:
                    TourShortcutsView()
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 32)

            Spacer()

            // 네비게이션 바
            HStack {
                if currentStep == .overview {
                    Button("건너뛰기") {
                        onSkip()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Button("이전") {
                        withAnimation {
                            currentStep = TourStep(rawValue: currentStep.rawValue - 1) ?? .overview
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // 단계 인디케이터 (중앙 레이블)
                Text("\(currentStep.rawValue + 1) / \(TourStep.allCases.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer()

                if currentStep == .shortcuts {
                    Button("시작하기") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("다음") {
                        withAnimation {
                            currentStep = TourStep(rawValue: currentStep.rawValue + 1) ?? .shortcuts
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - T1: 도구 카테고리 소개

struct TourOverviewView: View {
    private let categories: [(icon: String, name: String, description: String, color: Color)] = [
        ("calendar", "일정 & 미리알림", "캘린더 조회/추가, 미리알림 관리, 타이머", .red),
        ("rectangle.3.group", "칸반 보드", "프로젝트를 칸반으로 시각화하고 관리", .orange),
        ("magnifyingglass", "웹 검색", "실시간 웹 검색과 정보 수집", .blue),
        ("doc.text", "파일 & 클립보드", "파일 탐색, 읽기/쓰기, 클립보드", .green),
        ("terminal", "개발 도구", "Git, GitHub, 셸 명령 실행", .purple),
        ("music.note", "미디어", "음악 제어, 이미지 생성, 스크린샷", .pink),
        ("brain", "메모리", "대화 내용 기억, 개인 정보 관리", .indigo),
        ("puzzlepiece", "확장 (MCP)", "외부 도구 서버 연결", .teal),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text("도치가 할 수 있는 것")
                .font(.title2)
                .fontWeight(.semibold)

            Text("8가지 카테고리의 35개 도구를 대화로 활용할 수 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // 2열 4행 그리드
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 8) {
                ForEach(categories, id: \.name) { cat in
                    HStack(spacing: 8) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(cat.color)
                            .frame(width: 28, height: 28)
                            .background(cat.color.opacity(0.1))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(cat.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(cat.description)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - T2: 대화의 기본

struct TourConversationView: View {
    private let sections: [(icon: String, title: String, description: String)] = [
        ("text.bubble", "텍스트 입력",
         "하단 입력창에 메시지를 입력하면 AI가 답변합니다. Shift+Enter로 줄바꿈."),
        ("slash.circle", "슬래시 명령",
         "/ 를 입력하면 명령 목록이 나타납니다. 빠르게 기능을 실행할 수 있습니다."),
        ("mic", "음성 대화",
         "마이크 버튼을 누르거나 웨이크워드를 말하면 음성으로 대화합니다."),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text("대화의 기본")
                .font(.title2)
                .fontWeight(.semibold)

            Text("세 가지 방식으로 도치와 소통할 수 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(section.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)

                    if index < sections.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("도치는 필요한 도구를 자동으로 선택합니다. 별도로 도구를 지정할 필요 없어요.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - T3: 에이전트 & 워크스페이스

struct TourAgentWorkspaceView: View {
    private let templateIcons = [
        ("chevron.left.slash.chevron.right", "코딩"),
        ("magnifyingglass", "리서치"),
        ("calendar", "일정"),
        ("pencil.line", "작문"),
        ("rectangle.3.group", "칸반"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("에이전트 & 워크스페이스")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 16) {
                // 좌측: 에이전트
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                        Text("에이전트")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    Text("목적에 맞는 AI 비서를 만들 수 있습니다. 코딩, 리서치, 일정 관리 등 템플릿으로 빠르게 시작하세요.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // 템플릿 아이콘
                    HStack(spacing: 8) {
                        ForEach(templateIcons, id: \.1) { icon, label in
                            VStack(spacing: 2) {
                                Image(systemName: icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28, height: 28)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Circle())
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // 우측: 워크스페이스
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 24))
                            .foregroundStyle(.purple)
                        Text("워크스페이스")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    Text("프로젝트별로 독립된 공간을 만들 수 있습니다. 각 워크스페이스에 별도 메모리와 에이전트를 설정합니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // 워크스페이스 전환 모의
                    HStack(spacing: 6) {
                        ForEach(["기본", "프로젝트 A"], id: \.self) { name in
                            Text(name)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(name == "기본" ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple.opacity(0.6))
                    }

                    keycapHint(keys: ["\u{2318}", "\u{21E7}", "W"], label: "로 빠르게 전환")
                }
                .padding(12)
                .background(Color.purple.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func keycapHint(keys: [String], label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - T4: 빠른 조작법

struct TourShortcutsView: View {
    private let shortcuts: [(keys: String, action: String, description: String)] = [
        ("\u{2318}K", "커맨드 팔레트", "무엇이든 빠르게 찾고 실행"),
        ("\u{2318}N", "새 대화", "새 대화 시작"),
        ("\u{2318}I", "메모리 패널", "AI가 기억하는 정보 확인/편집"),
        ("\u{2318}\u{21E7}A", "에이전트 전환", "다른 에이전트로 빠르게 전환"),
        ("\u{2318}/", "단축키 도움말", "전체 단축키 목록 보기"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text("빠른 조작법")
                .font(.title2)
                .fontWeight(.semibold)

            Text("자주 쓰는 기능을 단축키로 빠르게 실행할 수 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    HStack(spacing: 12) {
                        // 키캡
                        Text(shortcut.keys)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .frame(width: 60)

                        // 동작명
                        Text(shortcut.action)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 100, alignment: .leading)

                        // 설명
                        Text(shortcut.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)

                    if index < shortcuts.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("전체 단축키는 \u{2318}/ 로 언제든 볼 수 있습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
