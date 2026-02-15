import SwiftUI

/// Settings view for managing plugins (J-4).
struct PluginSettingsView: View {
    var pluginManager: PluginManagerProtocol?

    @State private var selectedPlugin: PluginInfo?

    var body: some View {
        if let pluginManager {
            pluginContent(pluginManager)
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("플러그인")
                    .font(.headline)
                Text("플러그인 관리자가 초기화되지 않았습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func pluginContent(_ manager: PluginManagerProtocol) -> some View {
        Form {
            // Plugin directory
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("플러그인 디렉토리")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(manager.pluginDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("폴더 열기") {
                        NSWorkspace.shared.open(manager.pluginDirectory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                SettingsSectionHeader(
                    title: "플러그인 관리",
                    helpContent: "플러그인 디렉토리에 매니페스트(manifest.json)를 포함한 폴더를 추가하면 자동으로 인식됩니다. 각 플러그인은 도구, 프로바이더, TTS 엔진을 제공할 수 있습니다."
                )
            }

            // Plugin list
            if manager.plugins.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text("설치된 플러그인이 없습니다")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("플러그인 폴더에 매니페스트를 추가하세요")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Button("플러그인 폴더 열기") {
                            NSWorkspace.shared.open(manager.pluginDirectory)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("설치된 플러그인") {
                    ForEach(manager.plugins) { plugin in
                        PluginRowView(
                            plugin: plugin,
                            onToggle: { enabled in
                                if enabled {
                                    manager.enablePlugin(id: plugin.id)
                                } else {
                                    manager.disablePlugin(id: plugin.id)
                                }
                            },
                            onSelect: {
                                selectedPlugin = plugin
                            }
                        )
                    }
                }
            }

            // Refresh button
            Section {
                Button {
                    manager.scanPlugins()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("플러그인 새로고침")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $selectedPlugin) { plugin in
            if let manager = pluginManager {
                PluginDetailSheet(pluginId: plugin.id, pluginManager: manager)
            }
        }
    }
}

// MARK: - PluginRowView

struct PluginRowView: View {
    let plugin: PluginInfo
    let onToggle: (Bool) -> Void
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(plugin.status == .error ? .red : .secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(plugin.name)
                            .font(.system(size: 13, weight: .medium))
                        Text("v\(plugin.version)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let desc = plugin.pluginDescription {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let error = plugin.errorMessage {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if plugin.status != .error {
                    Toggle("", isOn: Binding(
                        get: { plugin.isActive },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
