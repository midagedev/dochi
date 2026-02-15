import SwiftUI

// MARK: - ScheduleTemplateSheet

struct ScheduleTemplateSheet: View {
    var schedulerService: SchedulerServiceProtocol
    var onSelectTemplate: (ScheduleTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("템플릿에서 추가")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ScheduleTemplate.builtIn) { template in
                        TemplateRowView(
                            template: template,
                            onAdd: {
                                onSelectTemplate(template)
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - TemplateRowView

struct TemplateRowView: View {
    let template: ScheduleTemplate
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(template.icon)
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 13, weight: .medium))
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("추가") {
                onAdd()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.3))
        )
    }
}
