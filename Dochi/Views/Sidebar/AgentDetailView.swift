import SwiftUI

struct AgentDetailView: View {
    let agentName: String
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    var availableToolGroups: [String] = []
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case config = "설정"
        case persona = "페르소나"
        case memory = "메모리"
    }

    @State private var selectedTab: Tab = .config

    // Config
    @State private var wakeWord: String = ""
    @State private var agentDescription: String = ""
    @State private var defaultModel: String = ""
    @State private var permSafe: Bool = true
    @State private var permSensitive: Bool = true
    @State private var permRestricted: Bool = true
    @State private var preferredToolGroups: [String] = []
    @State private var configSaved: Bool = false

    // Shell permissions
    @State private var shellBlockedText: String = ""
    @State private var shellConfirmText: String = ""
    @State private var shellAllowedText: String = ""

    // Delegation policy
    @State private var canDelegate: Bool = true
    @State private var canReceiveDelegation: Bool = true
    @State private var delegationAllowedTargetsText: String = ""
    @State private var delegationBlockedTargetsText: String = ""
    @State private var delegationMaxChainDepth: Int = 3

    // Persona
    @State private var personaText: String = ""
    @State private var personaSaved: Bool = false

    // Memory
    @State private var memoryText: String = ""
    @State private var memorySaved: Bool = false

    // Delete
    @State private var showDeleteConfirmation: Bool = false

    private var workspaceId: UUID { sessionContext.workspaceId }

    private var preferredToolGroupOptions: [String] {
        ToolGroupCatalog.orderedGroups(
            from: ToolGroupCatalog.defaultGroups + availableToolGroups + preferredToolGroups
        )
    }

    private var preferredToolGroupsSummary: String {
        if preferredToolGroups.isEmpty {
            return "선호 없음 (자동)"
        }
        return preferredToolGroups
            .map { ToolGroupCatalog.displayName(for: $0) }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("에이전트: \(agentName)")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            // Tab content
            switch selectedTab {
            case .config:
                configTab
            case .persona:
                personaTab
            case .memory:
                memoryTab
            }
        }
        .frame(width: 550, height: 620)
        .onAppear {
            loadContent()
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        ScrollView {
            Form {
                Section("기본 정보") {
                    TextField("호출어 (선택)", text: $wakeWord)
                        .textFieldStyle(.roundedBorder)
                    TextField("설명 (선택)", text: $agentDescription)
                        .textFieldStyle(.roundedBorder)
                }

                Section("기본 모델") {
                    Picker("모델", selection: $defaultModel) {
                        Text("앱 기본값 사용").tag("")
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            ForEach(provider.models, id: \.self) { model in
                                Text("\(provider.displayName) / \(model)").tag(model)
                            }
                        }
                    }
                }

                Section("권한") {
                    Toggle("safe (기본 도구)", isOn: $permSafe)
                        .disabled(true)
                    Toggle("sensitive (확인 필요)", isOn: $permSensitive)
                    Toggle("restricted (위험 도구)", isOn: $permRestricted)
                }

                Section("선호 도구 카테고리") {
                    Text("선택한 순서대로 도구 노출 우선순위에 반영됩니다. 비워두면 자동으로 판단합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if preferredToolGroupOptions.isEmpty {
                        Text("표시 가능한 도구 카테고리가 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(preferredToolGroupOptions, id: \.self) { group in
                                preferredToolGroupChip(group)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    HStack(spacing: 8) {
                        Button("자동으로 두기") {
                            preferredToolGroups.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(preferredToolGroups.isEmpty)

                        Spacer()

                        Text(preferredToolGroupsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("셸 명령 권한")
                            .font(.subheadline.bold())
                        Text("쉼표로 구분하여 명령 패턴을 입력하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("차단 명령")
                            .font(.caption)
                            .foregroundStyle(.red)
                        TextField("rm -rf /, sudo , shutdown ...", text: $shellBlockedText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Text("확인 필요 명령")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        TextField("rm , mv , kill ...", text: $shellConfirmText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Text("허용 명령")
                            .font(.caption)
                            .foregroundStyle(.green)
                        TextField("ls, cat , git status ...", text: $shellAllowedText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }

                Section("위임 정책") {
                    Toggle("다른 에이전트에게 위임 가능", isOn: $canDelegate)
                    Toggle("다른 에이전트로부터 위임 수신", isOn: $canReceiveDelegation)

                    Stepper("최대 체인 깊이: \(delegationMaxChainDepth)", value: $delegationMaxChainDepth, in: 1...10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("허용 대상 (비어있으면 전체 허용)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("에이전트1, 에이전트2 ...", text: $delegationAllowedTargetsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("차단 대상")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("에이전트3, 에이전트4 ...", text: $delegationBlockedTargetsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        if configSaved {
                            Text("저장됨")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Button("저장") {
                            saveConfig()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("에이전트 삭제", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)
        }
        .confirmationDialog(
            "'\(agentName)' 에이전트를 삭제하시겠습니까?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("에이전트의 설정, 페르소나, 메모리가 모두 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: - Persona Tab

    private var personaTab: some View {
        VStack {
            SectionEditorView(
                title: "페르소나",
                subtitle: "persona.md",
                text: $personaText,
                placeholder: "에이전트 페르소나를 입력하세요...",
                saved: $personaSaved,
                onSave: {
                    contextService.saveAgentPersona(
                        workspaceId: workspaceId,
                        agentName: agentName,
                        content: personaText
                    )
                    personaSaved = true
                    Log.storage.info("Agent persona saved from detail view")
                }
            )
        }
        .padding()
    }

    // MARK: - Memory Tab

    private var memoryTab: some View {
        VStack {
            SectionEditorView(
                title: "에이전트 메모리",
                subtitle: "memory.md",
                text: $memoryText,
                placeholder: "에이전트 메모리가 비어 있습니다.",
                saved: $memorySaved,
                onSave: {
                    contextService.saveAgentMemory(
                        workspaceId: workspaceId,
                        agentName: agentName,
                        content: memoryText
                    )
                    memorySaved = true
                    Log.storage.info("Agent memory saved from detail view")
                }
            )
        }
        .padding()
    }

    // MARK: - Preferred Tool Groups

    private func preferredToolGroupChip(_ group: String) -> some View {
        let isSelected = preferredToolGroups.contains(group)
        let selectedIndex = preferredToolGroups.firstIndex(of: group)
        return Button {
            togglePreferredToolGroup(group)
        } label: {
            HStack(spacing: 6) {
                Group {
                    if let selectedIndex {
                        Text("\(selectedIndex + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Circle())
                    } else {
                        Image(systemName: ToolGroupCatalog.icon(for: group))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                }

                Text(ToolGroupCatalog.displayName(for: group))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func togglePreferredToolGroup(_ group: String) {
        if let index = preferredToolGroups.firstIndex(of: group) {
            preferredToolGroups.remove(at: index)
            return
        }
        preferredToolGroups.append(group)
    }

    // MARK: - Data

    private func loadContent() {
        if let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: agentName) {
            wakeWord = config.wakeWord ?? ""
            agentDescription = config.description ?? ""
            defaultModel = config.defaultModel ?? ""
            let perms = config.effectivePermissions
            permSafe = perms.contains("safe")
            permSensitive = perms.contains("sensitive")
            permRestricted = perms.contains("restricted")
            preferredToolGroups = config.effectivePreferredToolGroups

            let shell = config.effectiveShellPermissions
            shellBlockedText = shell.blockedCommands.joined(separator: ", ")
            shellConfirmText = shell.confirmCommands.joined(separator: ", ")
            shellAllowedText = shell.allowedCommands.joined(separator: ", ")

            let delegation = config.effectiveDelegationPolicy
            canDelegate = delegation.canDelegate
            canReceiveDelegation = delegation.canReceiveDelegation
            delegationAllowedTargetsText = delegation.allowedTargets?.joined(separator: ", ") ?? ""
            delegationBlockedTargetsText = delegation.blockedTargets?.joined(separator: ", ") ?? ""
            delegationMaxChainDepth = delegation.maxChainDepth
        } else {
            let shell = ShellPermissionConfig.default
            shellBlockedText = shell.blockedCommands.joined(separator: ", ")
            shellConfirmText = shell.confirmCommands.joined(separator: ", ")
            shellAllowedText = shell.allowedCommands.joined(separator: ", ")
            preferredToolGroups = []
        }

        personaText = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentName) ?? ""
        memoryText = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName) ?? ""
    }

    private func saveConfig() {
        var permissions: [String] = ["safe"]
        if permSensitive { permissions.append("sensitive") }
        if permRestricted { permissions.append("restricted") }

        let shellPermissions = ShellPermissionConfig(
            blockedCommands: parseCommaSeparated(shellBlockedText),
            confirmCommands: parseCommaSeparated(shellConfirmText),
            allowedCommands: parseCommaSeparated(shellAllowedText)
        )

        let allowedTargets = parseCommaSeparated(delegationAllowedTargetsText)
        let blockedTargets = parseCommaSeparated(delegationBlockedTargetsText)

        let delegationPolicy = DelegationPolicy(
            canDelegate: canDelegate,
            canReceiveDelegation: canReceiveDelegation,
            allowedTargets: allowedTargets.isEmpty ? nil : allowedTargets,
            blockedTargets: blockedTargets.isEmpty ? nil : blockedTargets,
            maxChainDepth: delegationMaxChainDepth
        )

        let config = AgentConfig(
            name: agentName,
            wakeWord: wakeWord.isEmpty ? nil : wakeWord,
            description: agentDescription.isEmpty ? nil : agentDescription,
            defaultModel: defaultModel.isEmpty ? nil : defaultModel,
            permissions: permissions,
            preferredToolGroups: preferredToolGroups.isEmpty ? nil : preferredToolGroups,
            shellPermissions: shellPermissions,
            delegationPolicy: delegationPolicy
        )

        contextService.saveAgentConfig(workspaceId: workspaceId, config: config)
        configSaved = true
        Log.storage.info("Agent config saved from detail view: \(agentName)")

        // Reset saved indicator after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            configSaved = false
        }
    }

    private func parseCommaSeparated(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
