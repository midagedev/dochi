import SwiftUI

/// K-3: 관심사 발굴 설정 뷰
struct InterestSettingsView: View {
    var settings: AppSettings
    var interestService: InterestDiscoveryServiceProtocol?
    var contextService: ContextServiceProtocol?
    var userId: String?

    @State private var showAddForm = false
    @State private var newTopic = ""
    @State private var newTags = ""
    @State private var editingId: UUID?
    @State private var editTopic = ""
    @State private var editTags = ""

    var body: some View {
        Form {
            // MARK: - Master Toggle
            Section {
                Toggle("관심사 발굴 활성화", isOn: Binding(
                    get: { settings.interestDiscoveryEnabled },
                    set: { settings.interestDiscoveryEnabled = $0 }
                ))

                Text("대화를 통해 사용자의 관심사를 파악하여 맞춤 도움을 제공합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(
                    title: "관심사 발굴",
                    helpContent: "대화 중 관심사를 자동으로 감지하고, 시스템 프롬프트에 반영하여 맞춤형 응답을 제공합니다. 관심사가 적을수록 더 적극적으로 파악합니다."
                )
            }

            // MARK: - Mode
            Section("발굴 모드") {
                Picker("적극성 모드", selection: Binding(
                    get: { settings.interestDiscoveryMode },
                    set: { settings.interestDiscoveryMode = $0 }
                )) {
                    ForEach(DiscoveryMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let service = interestService {
                    HStack(spacing: 6) {
                        Text("현재 적극성:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(aggressivenessColor(service.currentAggressiveness))
                            .frame(width: 8, height: 8)
                        Text(service.currentAggressiveness.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let confirmedCount = service.profile.interests.filter { $0.status == .confirmed }.count
                        Text("(확인 \(confirmedCount)개)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!settings.interestDiscoveryEnabled)

            // MARK: - Interest List
            Section("수집된 관심사") {
                if let service = interestService, !service.profile.interests.isEmpty {
                    ForEach(service.profile.interests) { entry in
                        if editingId == entry.id {
                            editRow(entry: entry)
                        } else {
                            interestRow(entry: entry)
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("아직 수집된 관심사가 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("대화를 통해 자동으로 관심사가 수집되거나, 아래에서 직접 추가할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                // Add button
                if showAddForm {
                    addInterestForm
                } else {
                    Button {
                        showAddForm = true
                    } label: {
                        Label("관심사 직접 추가", systemImage: "plus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }

            // MARK: - Advanced
            Section("고급") {
                HStack {
                    Text("만료 기간: \(settings.interestExpirationDays)일")
                    Slider(
                        value: Binding(
                            get: { Double(settings.interestExpirationDays) },
                            set: { settings.interestExpirationDays = Int($0.rounded()) }
                        ),
                        in: 7...90,
                        step: 1
                    )
                }

                HStack {
                    Text("최소 감지 횟수: \(settings.interestMinDetectionCount)회")
                    Slider(
                        value: Binding(
                            get: { Double(settings.interestMinDetectionCount) },
                            set: { settings.interestMinDetectionCount = Int($0.rounded()) }
                        ),
                        in: 2...10,
                        step: 1
                    )
                }

                Text("키워드가 이 횟수 이상 등장하면 추정 관심사로 등록됩니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("시스템 프롬프트에 관심사 포함", isOn: Binding(
                    get: { settings.interestIncludeInPrompt },
                    set: { settings.interestIncludeInPrompt = $0 }
                ))

                Text("비활성화하면 관심사가 AI 응답에 반영되지 않습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.interestDiscoveryEnabled)
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Interest Row

    @ViewBuilder
    private func interestRow(entry: InterestEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon(entry.status)
                    .font(.system(size: 10))

                Text(entry.topic)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                statusBadge(entry)
            }

            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    Text("태그:")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(entry.tags.joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text("소스: \(sourceLabel(entry.source))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text("최초: \(dateLabel(entry.firstSeen))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text("최근: \(dateLabel(entry.lastSeen))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                if entry.status == .inferred {
                    Button("확인으로 승격") {
                        interestService?.confirmInterest(id: entry.id)
                        saveIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if entry.status == .expired {
                    Button("복원") {
                        interestService?.restoreInterest(id: entry.id)
                        saveIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Button("편집") {
                    editingId = entry.id
                    editTopic = entry.topic
                    editTags = entry.tags.joined(separator: ", ")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("삭제") {
                    interestService?.removeInterest(id: entry.id)
                    saveIfNeeded()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Edit Row

    @ViewBuilder
    private func editRow(entry: InterestEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("주제", text: $editTopic)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("태그 (쉼표로 구분)", text: $editTags)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 8) {
                Button("취소") {
                    editingId = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("저장") {
                    let tags = editTags.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    interestService?.updateInterest(id: entry.id, topic: editTopic, tags: tags)
                    editingId = nil
                    saveIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Form

    private var addInterestForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("주제 (예: Python 데이터 분석)", text: $newTopic)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("태그 (예: 데이터, 머신러닝)", text: $newTags)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 8) {
                Button("취소") {
                    showAddForm = false
                    newTopic = ""
                    newTags = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("추가") {
                    let tags = newTags.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let entry = InterestEntry(
                        topic: newTopic.trimmingCharacters(in: .whitespaces),
                        status: .confirmed,
                        confidence: 1.0,
                        source: "manual",
                        tags: tags
                    )
                    interestService?.addInterest(entry)
                    showAddForm = false
                    newTopic = ""
                    newTags = ""
                    saveIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var modeDescription: String {
        switch settings.interestDiscoveryMode {
        case DiscoveryMode.auto.rawValue:
            return "자동: 관심사 수에 따라 적극성이 자동 조절됩니다"
        case DiscoveryMode.eager.rawValue:
            return "적극: 항상 적극적으로 관심사를 발굴합니다"
        case DiscoveryMode.passive.rawValue:
            return "수동: 유휴 시에만 제안, 사용자 요청 시 심화"
        case DiscoveryMode.manual.rawValue:
            return "비활성: 자동 발굴 비활성, 수동 추가만 가능"
        default:
            return ""
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: InterestStatus) -> some View {
        switch status {
        case .confirmed:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
        case .inferred:
            Image(systemName: "circle")
                .foregroundStyle(.orange)
        case .expired:
            Image(systemName: "diamond")
                .foregroundStyle(.gray)
        }
    }

    @ViewBuilder
    private func statusBadge(_ entry: InterestEntry) -> some View {
        let (text, color): (String, Color) = {
            switch entry.status {
            case .confirmed: return ("확인됨", .green)
            case .inferred: return ("추정 \(Int(entry.confidence * 100))%", .orange)
            case .expired: return ("만료", .gray)
            }
        }()

        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func aggressivenessColor(_ level: DiscoveryAggressiveness) -> Color {
        switch level {
        case .eager: return .orange
        case .active: return .blue
        case .passive: return .green
        }
    }

    private func sourceLabel(_ source: String) -> String {
        if source.hasPrefix("conversation:") { return "대화" }
        if source == "manual" { return "수동" }
        if source == "onboarding" { return "온보딩" }
        if source == "proactive" { return "프로액티브" }
        return source
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func saveIfNeeded() {
        guard let userId else { return }
        interestService?.saveProfile(userId: userId)
        if let contextService, let interestService {
            interestService.syncToMemory(contextService: contextService, userId: userId)
        }
    }
}
