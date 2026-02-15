import SwiftUI

/// Detail sheet for a single plugin, showing capabilities, permissions, and controls.
struct PluginDetailSheet: View {
    let plugin: PluginInfo
    let pluginManager: PluginManagerProtocol

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.title3.bold())
                    HStack(spacing: 8) {
                        Text("v\(plugin.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let author = plugin.author {
                            Text("by \(author)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    if let desc = plugin.pluginDescription {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Error message
                    if let error = plugin.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Capabilities
                    capabilitiesSection

                    // Permissions
                    permissionsSection

                    Divider()

                    // Controls
                    controlsSection
                }
                .padding()
            }
        }
        .frame(width: 420, height: 480)
        .alert("플러그인 삭제", isPresented: $showDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                do {
                    try pluginManager.removePlugin(id: plugin.id)
                    dismiss()
                } catch {
                    Log.app.error("Plugin removal failed: \(error.localizedDescription)")
                }
            }
        } message: {
            Text("\"\(plugin.name)\" 플러그인을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: - Capabilities

    @ViewBuilder
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("제공 기능")
                .font(.headline)

            if plugin.toolCount == 0 && plugin.providerCount == 0 && plugin.ttsEngineCount == 0 {
                Text("제공하는 기능이 없습니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                if let tools = plugin.manifest.capabilities.tools, !tools.isEmpty {
                    capabilityGroup(icon: "wrench.and.screwdriver", label: "도구 \(tools.count)개", items: tools)
                }
                if let providers = plugin.manifest.capabilities.providers, !providers.isEmpty {
                    capabilityGroup(icon: "cpu", label: "프로바이더 \(providers.count)개", items: providers)
                }
                if let engines = plugin.manifest.capabilities.ttsEngines, !engines.isEmpty {
                    capabilityGroup(icon: "speaker.wave.2", label: "TTS 엔진 \(engines.count)개", items: engines)
                }
            }
        }
    }

    @ViewBuilder
    private func capabilityGroup(icon: String, label: String, items: [PluginCapabilityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.subheadline.bold())
            }

            ForEach(items) { item in
                HStack(spacing: 4) {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(item.name)
                        .font(.caption)
                    if let desc = item.description {
                        Text("— \(desc)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("요청 권한")
                .font(.headline)

            let perms = plugin.manifest.permissions
            if perms.network != true && perms.fileRead != true && perms.fileWrite != true {
                Text("요청된 권한이 없습니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                if perms.network == true {
                    permissionRow(icon: "network", label: "네트워크")
                }
                if perms.fileRead == true {
                    permissionRow(icon: "doc", label: "파일 읽기")
                }
                if perms.fileWrite == true {
                    permissionRow(icon: "doc.badge.plus", label: "파일 쓰기")
                }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if plugin.status != .error {
                Toggle("활성화", isOn: Binding(
                    get: { plugin.isActive },
                    set: { enabled in
                        if enabled {
                            pluginManager.enablePlugin(id: plugin.id)
                        } else {
                            pluginManager.disablePlugin(id: plugin.id)
                        }
                    }
                ))
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("플러그인 삭제")
                }
            }
            .buttonStyle(.bordered)
        }
    }
}
