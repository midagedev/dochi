import SwiftUI

// MARK: - Image Attachment Bar

/// Displays a horizontal scrollable bar of image thumbnails with remove buttons.
/// Shown above the input bar when the user has pending image attachments.
struct ImageAttachmentBarView: View {
    let attachments: [ImageAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ImageThumbnailView(
                        attachment: attachment,
                        onRemove: { onRemove(attachment.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Image Thumbnail

/// A single 80x80pt image thumbnail with an X button to remove.
struct ImageThumbnailView: View {
    let attachment: ImageAttachment
    let onRemove: () -> Void
    @State private var isHovering = false
    @State private var showPreview = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: attachment.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .onTapGesture {
                    showPreview = true
                }
                .popover(isPresented: $showPreview) {
                    ImagePreviewPopoverView(attachment: attachment)
                }
                .help(attachment.fileName)

            // Remove button (always visible on hover)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .opacity(isHovering ? 1 : 0.7)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
    }
}

// MARK: - Image Preview Popover

/// Shows the original-size image in a popover when a thumbnail is clicked.
struct ImagePreviewPopoverView: View {
    let attachment: ImageAttachment

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: attachment.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 500, maxHeight: 500)

            HStack(spacing: 12) {
                Text(attachment.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(Int(attachment.originalSize.width)) x \(Int(attachment.originalSize.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(formatFileSize(attachment.data.count))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Vision Warning Banner

/// Orange warning banner shown when the current model does not support Vision.
struct VisionWarningBannerView: View {
    let modelName: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text("현재 모델(\(modelName))은 이미지 입력을 지원하지 않습니다. 텍스트만 전송됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}
