import SwiftUI

/// 구독 등록/편집 시트
struct SubscriptionEditSheet: View {
    let subscription: SubscriptionPlan?
    let onSave: (SubscriptionPlan) -> Void
    let onCancel: () -> Void

    @State private var providerName: String = ""
    @State private var planName: String = ""
    @State private var isUnlimited: Bool = false
    @State private var monthlyTokenLimit: String = ""
    @State private var resetDay: Int = 1
    @State private var monthlyCost: String = ""

    private let providerOptions = ["OpenAI", "Anthropic", "Z.AI", "기타"]

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
                // Provider
                Picker("프로바이더", selection: $providerName) {
                    ForEach(providerOptions, id: \.self) { provider in
                        Text(provider).tag(provider)
                    }
                }

                // Plan name
                TextField("플랜명", text: $planName)
                    .textFieldStyle(.roundedBorder)

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
        .frame(width: 420, height: 380)
        .onAppear {
            if let sub = subscription {
                providerName = sub.providerName
                planName = sub.planName
                isUnlimited = sub.monthlyTokenLimit == nil
                monthlyTokenLimit = sub.monthlyTokenLimit.map(String.init) ?? ""
                resetDay = sub.resetDayOfMonth
                monthlyCost = String(format: "%.2f", sub.monthlyCostUSD)
            } else {
                providerName = providerOptions[0]
            }
        }
    }

    private func save() {
        let tokenLimit: Int? = isUnlimited ? nil : Int(monthlyTokenLimit)
        let cost = Double(monthlyCost) ?? 0

        let plan = SubscriptionPlan(
            id: subscription?.id ?? UUID(),
            providerName: providerName,
            planName: planName,
            monthlyTokenLimit: tokenLimit,
            resetDayOfMonth: resetDay,
            monthlyCostUSD: cost,
            createdAt: subscription?.createdAt ?? Date()
        )
        onSave(plan)
    }
}
