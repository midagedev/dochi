import SwiftUI

struct MCPServerEditView: View {
    var mcpService: MCPServiceProtocol?
    var editingServer: MCPServerConfig?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var arguments: [String] = [""]
    @State private var envKeys: [String] = [""]
    @State private var envValues: [String] = [""]
    @State private var isEnabled = true
    @State private var errorMessage: String?
    @State private var isConnecting = false

    private var isEditing: Bool { editingServer != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "MCP 서버 편집" : "MCP 서버 추가")
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

            Divider()

            Form {
                Section("서버 정보") {
                    TextField("이름", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("실행 명령어", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    Toggle("활성화", isOn: $isEnabled)
                }

                Section("인자") {
                    ForEach(arguments.indices, id: \.self) { i in
                        HStack {
                            TextField("인자 \(i + 1)", text: $arguments[i])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            if arguments.count > 1 {
                                Button {
                                    arguments.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        arguments.append("")
                    } label: {
                        Label("인자 추가", systemImage: "plus")
                            .font(.caption)
                    }
                }

                Section("환경 변수") {
                    ForEach(envKeys.indices, id: \.self) { i in
                        HStack {
                            TextField("키", text: $envKeys[i])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: 140)
                            Text("=")
                                .foregroundStyle(.secondary)
                            SecureField("값", text: $envValues[i])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            if envKeys.count > 1 {
                                Button {
                                    envKeys.remove(at: i)
                                    envValues.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        envKeys.append("")
                        envValues.append("")
                    } label: {
                        Label("환경 변수 추가", systemImage: "plus")
                            .font(.caption)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("취소") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button {
                            saveServer()
                        } label: {
                            HStack(spacing: 4) {
                                if isConnecting {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                }
                                Text("저장")
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || command.trimmingCharacters(in: .whitespaces).isEmpty
                                  || isConnecting)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 480)
        .onAppear {
            if let server = editingServer {
                name = server.name
                command = server.command
                arguments = server.arguments.isEmpty ? [""] : server.arguments
                isEnabled = server.isEnabled

                envKeys = server.environment.isEmpty ? [""] : Array(server.environment.keys)
                envValues = server.environment.isEmpty ? [""] : envKeys.map { server.environment[$0] ?? "" }
            }
        }
    }

    private func saveServer() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else { return }

        let args = arguments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var env: [String: String] = [:]
        for (i, key) in envKeys.enumerated() {
            let k = key.trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, i < envValues.count {
                env[k] = envValues[i]
            }
        }

        let config: MCPServerConfig
        if let existing = editingServer {
            config = MCPServerConfig(
                id: existing.id,
                name: trimmedName,
                command: trimmedCommand,
                arguments: args,
                environment: env,
                isEnabled: isEnabled
            )
            mcpService?.removeServer(id: existing.id)
        } else {
            config = MCPServerConfig(
                name: trimmedName,
                command: trimmedCommand,
                arguments: args,
                environment: env,
                isEnabled: isEnabled
            )
        }

        mcpService?.addServer(config: config)

        // Persist to AppStorage
        persistMCPServers()

        // Auto-connect if enabled
        if isEnabled {
            isConnecting = true
            Task {
                do {
                    try await mcpService?.connect(serverId: config.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isConnecting = false
                if errorMessage == nil {
                    onSave()
                    dismiss()
                }
            }
        } else {
            onSave()
            dismiss()
        }
    }

    private func persistMCPServers() {
        let servers = mcpService?.listServers() ?? []
        if let data = try? JSONEncoder().encode(servers),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "mcpServersJSON")
        }
    }
}
