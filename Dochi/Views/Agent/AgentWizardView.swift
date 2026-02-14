import SwiftUI

/// 5단계 에이전트 생성 위저드
struct AgentWizardView: View {
    @Bindable var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0

    // Step 0: 템플릿 선택
    @State private var selectedTemplate: AgentTemplate?

    // Step 1: 기본 정보
    @State private var agentName = ""
    @State private var wakeWord = ""
    @State private var agentDescription = ""
    @State private var nameError: String?

    // Step 2: 페르소나
    @State private var personaText = ""

    // Step 3: 모델 + 권한
    @State private var selectedModel = ""
    @State private var permSafe = true
    @State private var permSensitive = true
    @State private var permRestricted = false

    // Step 4: 요약 + 템플릿 저장
    @State private var saveAsTemplate = false

    private let totalSteps = 5

    private var workspaceId: UUID { viewModel.sessionContext.workspaceId }

    private var customTemplates: [AgentTemplate] {
        viewModel.contextService.loadCustomTemplates()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Progress bar
            progressBar

            // Step content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            navigationButtons
        }
        .frame(width: 560, height: 520)
        .onExitCommand {
            dismiss()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("에이전트 생성")
                .font(.headline)
            Spacer()
            Text("단계 \(currentStep + 1)/\(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: templateSelectionStep
        case 1: basicInfoStep
        case 2: personaStep
        case 3: modelPermissionsStep
        case 4: summaryStep
        default: EmptyView()
        }
    }

    // MARK: - Step 0: Template Selection

    private var templateSelectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("템플릿 선택")
                    .font(.title3.bold())
                Text("미리 준비된 템플릿으로 빠르게 시작하거나, 처음부터 직접 만들 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    // Blank template first
                    templateCard(AgentTemplate.blank)

                    // Built-in templates
                    ForEach(AgentTemplate.builtInTemplates) { template in
                        templateCard(template)
                    }
                }

                // Custom templates section
                if !customTemplates.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    Text("내 템플릿")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ], spacing: 12) {
                        ForEach(customTemplates) { template in
                            templateCard(template)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func templateCard(_ template: AgentTemplate) -> some View {
        let isSelected = selectedTemplate?.id == template.id
        return Button {
            selectedTemplate = template
            applyTemplate(template)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title3)
                        .foregroundStyle(templateColor(template.accentColor))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 1: Basic Info

    private var basicInfoStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("기본 정보")
                    .font(.title3.bold())

                VStack(alignment: .leading, spacing: 6) {
                    Text("이름 (필수)")
                        .font(.subheadline.bold())
                    TextField("에이전트 이름", text: $agentName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: agentName) { _, _ in
                            nameError = nil
                        }

                    if let error = nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("웨이크워드 (선택)")
                        .font(.subheadline.bold())
                    TextField("음성으로 부를 이름", text: $wakeWord)
                        .textFieldStyle(.roundedBorder)
                    Text("음성 모드에서 이 단어로 에이전트를 활성화합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("설명 (선택)")
                        .font(.subheadline.bold())
                    TextField("이 에이전트의 역할을 간단히 설명하세요", text: $agentDescription)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        }
    }

    // MARK: - Step 2: Persona

    private var personaStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("페르소나")
                    .font(.title3.bold())
                Text("에이전트의 성격, 말투, 전문 분야를 정의합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Suggestion chips
                if let template = selectedTemplate, !template.personaChips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(template.personaChips, id: \.self) { chip in
                            Button {
                                if !personaText.isEmpty {
                                    personaText += "\n- \(chip)"
                                } else {
                                    personaText = "- \(chip)"
                                }
                            } label: {
                                Text(chip)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextEditor(text: $personaText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                if personaText.isEmpty {
                    Text("비워두면 기본 페르소나가 사용됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Step 3: Model & Permissions

    private var modelPermissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("모델 & 권한")
                    .font(.title3.bold())

                // Model selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("기본 모델")
                        .font(.subheadline.bold())
                    Picker("모델", selection: $selectedModel) {
                        Text("앱 기본값 사용").tag("")
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            ForEach(provider.models, id: \.self) { model in
                                Text("\(provider.displayName) / \(model)").tag(model)
                            }
                        }
                    }
                    .labelsHidden()
                }

                // Permissions
                VStack(alignment: .leading, spacing: 8) {
                    Text("권한")
                        .font(.subheadline.bold())
                    Text("에이전트가 사용할 수 있는 도구의 범위를 설정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $permSafe) {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("safe")
                                    .font(.system(size: 13, weight: .medium))
                                Text("기본 도구 (검색, 파일 읽기 등)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(true) // safe는 항상 활성

                    Toggle(isOn: $permSensitive) {
                        HStack {
                            Image(systemName: "exclamationmark.shield")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text("sensitive")
                                    .font(.system(size: 13, weight: .medium))
                                Text("확인이 필요한 도구 (파일 수정, 일정 생성 등)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $permRestricted) {
                        HStack {
                            Image(systemName: "xmark.shield")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading) {
                                Text("restricted")
                                    .font(.system(size: 13, weight: .medium))
                                Text("위험 도구 (셸 명령, 시스템 설정 등)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Step 4: Summary

    private var summaryStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("요약")
                    .font(.title3.bold())

                // Summary card
                VStack(alignment: .leading, spacing: 10) {
                    // Name & template
                    HStack {
                        if let template = selectedTemplate {
                            Image(systemName: template.icon)
                                .font(.title2)
                                .foregroundStyle(templateColor(template.accentColor))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agentName)
                                .font(.headline)
                            if let template = selectedTemplate, template.id != "blank" {
                                Text("템플릿: \(template.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Details grid
                    summaryRow(label: "웨이크워드", value: wakeWord.isEmpty ? "(없음)" : wakeWord)
                    summaryRow(label: "설명", value: agentDescription.isEmpty ? "(없음)" : agentDescription)
                    summaryRow(label: "모델", value: selectedModel.isEmpty ? "앱 기본값" : selectedModel)
                    summaryRow(label: "권한", value: permissionsSummary)
                    summaryRow(label: "페르소나", value: personaText.isEmpty ? "(기본)" : String(personaText.prefix(80)) + (personaText.count > 80 ? "..." : ""))
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Save as template checkbox
                Toggle("커스텀 템플릿으로 저장", isOn: $saveAsTemplate)
                    .font(.subheadline)

                if saveAsTemplate {
                    Text("이 설정을 템플릿으로 저장하면 나중에 비슷한 에이전트를 빠르게 만들 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionsSummary: String {
        var perms: [String] = ["safe"]
        if permSensitive { perms.append("sensitive") }
        if permRestricted { perms.append("restricted") }
        return perms.joined(separator: ", ")
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("이전") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep -= 1
                    }
                }
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("다음") {
                    if validateCurrentStep() {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("생성") {
                    createAgent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(agentName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return selectedTemplate != nil
        case 1:
            return !agentName.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    // MARK: - Validation

    private func validateCurrentStep() -> Bool {
        switch currentStep {
        case 0:
            return selectedTemplate != nil
        case 1:
            let name = agentName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                nameError = "이름을 입력해주세요."
                return false
            }
            let existing = viewModel.contextService.listAgents(workspaceId: workspaceId)
            if existing.contains(name) {
                nameError = "이미 같은 이름의 에이전트가 있습니다."
                return false
            }
            return true
        default:
            return true
        }
    }

    // MARK: - Template Application

    private func applyTemplate(_ template: AgentTemplate) {
        agentDescription = template.description == "처음부터 직접 설정합니다" ? "" : template.description
        personaText = template.suggestedPersona
        selectedModel = template.suggestedModel ?? ""
        let perms = template.suggestedPermissions
        permSafe = true
        permSensitive = perms.contains("sensitive")
        permRestricted = perms.contains("restricted")
    }

    // MARK: - Create

    private func createAgent() {
        let name = agentName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let existing = viewModel.contextService.listAgents(workspaceId: workspaceId)
        if existing.contains(name) {
            nameError = "이미 같은 이름의 에이전트가 있습니다."
            currentStep = 1
            return
        }

        let wake = wakeWord.trimmingCharacters(in: .whitespaces)
        let desc = agentDescription.trimmingCharacters(in: .whitespaces)

        // Build permissions
        var permissions: [String] = ["safe"]
        if permSensitive { permissions.append("sensitive") }
        if permRestricted { permissions.append("restricted") }

        let config = AgentConfig(
            name: name,
            wakeWord: wake.isEmpty ? nil : wake,
            description: desc.isEmpty ? nil : desc,
            defaultModel: selectedModel.isEmpty ? nil : selectedModel,
            permissions: permissions
        )

        viewModel.contextService.saveAgentConfig(workspaceId: workspaceId, config: config)

        // Save persona if provided
        let persona = personaText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persona.isEmpty {
            viewModel.contextService.saveAgentPersona(
                workspaceId: workspaceId,
                agentName: name,
                content: persona
            )
        }

        // Save as custom template if checked
        if saveAsTemplate {
            saveCustomTemplate(name: name, description: desc)
        }

        viewModel.switchAgent(name: name)
        Log.app.info("Agent created via wizard: \(name)")
        dismiss()
    }

    private func saveCustomTemplate(name: String, description: String) {
        var permissions: [String] = ["safe"]
        if permSensitive { permissions.append("sensitive") }
        if permRestricted { permissions.append("restricted") }

        let template = AgentTemplate(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name,
            icon: selectedTemplate?.icon ?? "person.fill",
            description: description.isEmpty ? name : description,
            detailedDescription: description,
            suggestedPersona: personaText,
            suggestedModel: selectedModel.isEmpty ? nil : selectedModel,
            suggestedPermissions: permissions,
            suggestedTools: selectedTemplate?.suggestedTools ?? [],
            isBuiltIn: false,
            accentColor: selectedTemplate?.accentColor ?? "gray"
        )

        var templates = viewModel.contextService.loadCustomTemplates()
        templates.append(template)
        viewModel.contextService.saveCustomTemplates(templates)
        Log.app.info("Custom template saved: \(template.name)")
    }

    // MARK: - Helpers

    private func templateColor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        case "teal": return .teal
        case "red": return .red
        case "pink": return .pink
        default: return .gray
        }
    }
}
