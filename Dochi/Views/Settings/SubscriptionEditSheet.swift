import SwiftUI

/// 구독 등록/편집 시트
struct SubscriptionEditSheet: View {
    let subscription: SubscriptionPlan?
    let onSave: (SubscriptionPlan) -> Void
    let onCancel: () -> Void

    @State private var providerName: String = ""
    @State private var planName: String = ""
    @State private var usageSource: SubscriptionUsageSource = .externalToolLogs
    @State private var isUnlimited: Bool = false
    @State private var monthlyTokenLimit: String = ""
    @State private var resetDay: Int = 1
    @State private var monthlyCost: String = ""

    private let providerPresets = ["Codex", "Claude", "Gemini", "OpenAI", "Anthropic", "Z.AI"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(subscription != nil ? "구독 편집" : "구독 추가")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("프로바이더 이름", text: $providerName)
                        .textFieldStyle(.roundedBorder)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(providerPresets, id: \.self) { preset in
                                Button(preset) {
                                    providerName = preset
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }

                    if usageSource == .externalToolLogs && !isKnownExternalProvider {
                        Text("알림: 현재 입력한 프로바이더는 외부 로그/API 수집 대상과 매칭되지 않을 수 있습니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }

                // Plan name
                TextField("플랜명", text: $planName)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Picker("사용량 소스", selection: $usageSource) {
                        ForEach(SubscriptionUsageSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(usageSource.detailText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceGuidanceTitle)
                        .font(.system(size: 11, weight: .semibold))
                    Text(sourceGuidanceDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if usageSource == .externalToolLogs && isGeminiProvider {
                        Text("Gemini는 oauth-personal 인증에서 모니터링 정확도가 가장 높습니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
                .background(.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Token limit
                Toggle("무제한", isOn: $isUnlimited)
                if !isUnlimited {
                    HStack {
                        Text("월간 토큰 한도")
                        Spacer()
                        TextField("1000000", text: $monthlyTokenLimit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                // Reset day
                Stepper("리셋일: 매월 \(resetDay)일", value: $resetDay, in: 1...28)

                // Monthly cost
                HStack {
                    Text("월간 비용")
                    Spacer()
                    HStack(spacing: 2) {
                        Text("$")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("20.00", text: $monthlyCost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            // Buttons
            HStack {
                Button("취소") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("저장") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(providerName.isEmpty || planName.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 430)
        .onAppear {
            if let sub = subscription {
                providerName = sub.providerName
                planName = sub.planName
                usageSource = sub.usageSource
                isUnlimited = sub.monthlyTokenLimit == nil
                monthlyTokenLimit = sub.monthlyTokenLimit.map(String.init) ?? ""
                resetDay = sub.resetDayOfMonth
                monthlyCost = String(format: "%.2f", sub.monthlyCostUSD)
            } else {
                providerName = providerPresets[0]
                usageSource = .externalToolLogs
            }
        }
    }

    private var normalizedProviderName: String {
        providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isGeminiProvider: Bool {
        normalizedProviderName.contains("gemini")
    }

    private var isKnownExternalProvider: Bool {
        let normalized = normalizedProviderName
        if normalized.contains("gemini") { return true }
        if normalized.contains("claude") || normalized.contains("anthropic") { return true }
        if normalized.contains("codex") || normalized.contains("chatgpt") || normalized.contains("openai") { return true }
        return false
    }

    private var sourceGuidanceTitle: String {
        switch usageSource {
        case .externalToolLogs:
            return "외부 로그/API 수집 안내"
        case .dochiUsageStore:
            return "UsageStore 수집 안내"
        }
    }

    private var sourceGuidanceDetail: String {
        switch usageSource {
        case .externalToolLogs:
            return "Codex(~/.codex/sessions), Claude(~/.claude/projects), Gemini(~/.gemini) 경로를 자동 탐색해 사용량을 집계합니다."
        case .dochiUsageStore:
            return "Dochi 대화 기록의 provider/model 토큰 로그를 기준으로 집계합니다. 외부 CLI 상태와는 분리됩니다."
        }
    }

    private func save() {
        let plan = Self.makePlan(
            subscription: subscription,
            providerName: providerName,
            planName: planName,
            usageSource: usageSource,
            isUnlimited: isUnlimited,
            monthlyTokenLimit: monthlyTokenLimit,
            resetDay: resetDay,
            monthlyCost: monthlyCost
        )
        onSave(plan)
    }

    static func makePlan(
        subscription: SubscriptionPlan?,
        providerName: String,
        planName: String,
        usageSource: SubscriptionUsageSource,
        isUnlimited: Bool,
        monthlyTokenLimit: String,
        resetDay: Int,
        monthlyCost: String
    ) -> SubscriptionPlan {
        let tokenLimit: Int? = isUnlimited ? nil : Int(monthlyTokenLimit)
        let cost = Double(monthlyCost) ?? 0

        return SubscriptionPlan(
            id: subscription?.id ?? UUID(),
            providerName: providerName,
            planName: planName,
            usageSource: usageSource,
            monthlyTokenLimit: tokenLimit,
            resetDayOfMonth: resetDay,
            monthlyCostUSD: cost,
            createdAt: subscription?.createdAt ?? Date()
        )
    }
}
