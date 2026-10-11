import SwiftUI
import UIKit
import QuickLook
import Photos

// MARK: - 空状态（iOS 16.4 无 ContentUnavailableView）

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(Palette.textTertiary)
            Text(title).font(.headline).foregroundStyle(Palette.textSecondary)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 附件保存

enum AttachmentSaver {
    static func saveImage(_ img: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: img)
        }
    }

    /// 把附件写入临时文件，返回 URL（供预览/分享）
    static func tempURL(for att: Attachment) -> URL? {
        if let d = att.data {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + att.name)
            do { try d.write(to: url); return url } catch { return nil }
        }
        return att.url.flatMap(URL.init)
    }
}

// MARK: - QuickLook 预览

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - 连接状态徽标

struct ConnectionBadge: View {
    let state: RelayTransport.State

    var color: Color {
        switch state {
        case .connected: return Palette.success
        case .connecting: return Palette.warning
        case .error: return Palette.danger
        case .idle: return Palette.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(state.display).font(.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - 头像

struct AvatarView: View {
    let emoji: String
    let online: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 42, height: 42)
                .background(Palette.bgElevated)
                .clipShape(Circle())
            Circle()
                .fill(online ? Palette.success : Palette.textTertiary)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Palette.bgBase, lineWidth: 2))
        }
    }
}

// MARK: - 状态标签

struct StatusPill: View {
    let status: TaskStatus

    var color: Color {
        switch status {
        case .pending: return Palette.textTertiary
        case .running: return Palette.info
        case .blocked: return Palette.warning
        case .done: return Palette.success
        case .failed: return Palette.danger
        }
    }

    var body: some View {
        Text(status.display)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

// MARK: - 进度条

struct ProgressBar: View {
    let progress: Double
    var color: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.bgPanel)
                Capsule().fill(color).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - 消息气泡

struct MessageBubble: View {
    let message: AgentMessage
    var avatarEmoji: String = "🤖"

    var isIncoming: Bool { message.direction == .incoming }

    private var bubbleShape: UnevenRoundedRectangle {
        if isIncoming {
            return UnevenRoundedRectangle(
                topLeadingRadius: 5, bottomLeadingRadius: 18,
                bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18,
                bottomTrailingRadius: 18, topTrailingRadius: 5, style: .continuous)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isIncoming {
                agentAvatar
                bubbleContent
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                bubbleContent
                userAvatar
            }
        }
    }

    private var agentAvatar: some View {
        Text(avatarEmoji)
            .font(.system(size: 17))
            .frame(width: 30, height: 30)
            .background(Palette.bgElevated)
            .clipShape(Circle())
    }

    private var userAvatar: some View {
        ZStack {
            Circle().fill(Palette.accent)
                .frame(width: 30, height: 30)
            Image(systemName: "person.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 6) {
            switch message.kind {
            case .task:
                InlineTaskCard(message: message)
            case .tool:
                ToolCard(message: message)
                default:
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.body)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(isIncoming ? Palette.textPrimary : Color.white)
                            .background(isIncoming ? Palette.bgElevated : Palette.accent)
                            .clipShape(bubbleShape)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = message.text
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }

            if !message.attachments.isEmpty {
                AttachmentGridView(attachments: message.attachments)
            }

            HStack(spacing: 6) {
                if !message.senderName.isEmpty {
                    Text(message.senderName).font(.caption2).foregroundStyle(Palette.textSecondary)
                }
                Text(message.timestamp, style: .time).font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

// MARK: - 工具调用卡片（edit 消息：running → done/failed）

struct ToolCard: View {
    let message: AgentMessage

    private var state: String { message.toolState ?? "running" }
    private var toolName: String { message.toolName ?? "工具" }

    private var tint: Color {
        switch state {
        case "done": return Palette.success
        case "failed": return Palette.danger
        default: return Palette.accent
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
                .font(.system(size: 18))
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Palette.danger)
                .font(.system(size: 18))
        default:
            ProgressView()
                .controlSize(.small)
                .tint(Palette.accent)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(toolName)
                    .font(.subheadline.weight(.semibold))
                    .monospaced()
                    .foregroundStyle(tint)
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}


// MARK: - 附件网格

struct AttachmentGridView: View {
    let attachments: [Attachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(attachments) { att in
                if att.kind == .image {
                    ImageAttachmentCell(attachment: att)
                } else {
                    FileAttachmentCell(attachment: att)
                }
            }
        }
    }
}

// MARK: - 图片附件

struct ImageAttachmentCell: View {
    let attachment: Attachment
    @State private var showFull = false

    var body: some View {
        thumbnail
            .frame(maxWidth: 240, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { showFull = true }
            .contextMenu {
                if let img = image {
                    Button {
                        AttachmentSaver.saveImage(img)
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }
                }
                if let u = AttachmentSaver.tempURL(for: attachment) {
                    ShareLink(item: u) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .fullScreenCover(isPresented: $showFull) {
                FullImagePreview(attachment: attachment)
            }
    }

    private var image: UIImage? {
        attachment.data.flatMap(UIImage.init(data:))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let img = image {
            Image(uiImage: img).resizable().scaledToFit()
        } else if let urlStr = attachment.url, let u = URL(string: urlStr) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                case .failure:
                    placeholder("图片加载失败")
                case .empty:
                    ZStack { Palette.bgElevated; ProgressView() }
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            placeholder("无数据")
        }
    }

    private func placeholder(_ s: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Palette.bgElevated)
            Text(s).font(.caption).foregroundStyle(Palette.textSecondary)
        }
        .frame(width: 200, height: 120)
    }
}

/// 全屏图片预览
struct FullImagePreview: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            content
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let img = attachment.data.flatMap(UIImage.init(data:)) {
            Image(uiImage: img).resizable()
        } else if let urlStr = attachment.url, let u = URL(string: urlStr) {
            AsyncImage(url: u) { phase in
                if case .success(let img) = phase { img.resizable() }
            }
        }
    }
}

// MARK: - 文件附件

struct FileAttachmentCell: View {
    let attachment: Attachment
    @State private var previewURL: URL?
    @State private var showingPreview = false

    private var icon: String {
        switch (attachment.name as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "zip": return "doc.zipper"
        case "txt", "md": return "doc.plaintext"
        case "mp4", "mov": return "play.rectangle"
        case "mp3": return "music.note"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .background(Palette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                Text(AttachmentHelper.readableSize(attachment.sizeBytes))
                    .font(.caption2).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "eye").foregroundStyle(Palette.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: 260)
        .background(Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { open() }
        .contextMenu {
            if let u = AttachmentSaver.tempURL(for: attachment) {
                ShareLink(item: u) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let u = previewURL {
                NavigationStack {
                    QuickLookPreview(url: u)
                        .navigationTitle(attachment.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showingPreview = false }
                            }
                        }
                }
            }
        }
    }

    private func open() {
        previewURL = AttachmentSaver.tempURL(for: attachment)
        showingPreview = true
    }
}

/// 聊天里的任务卡片
struct InlineTaskCard: View {
    let message: AgentMessage

    var status: TaskStatus {
        TaskStatus(rawValue: message.taskStatus ?? "pending") ?? .pending
    }
    var progress: Double { message.progress ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📋 任务").font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                Spacer()
                StatusPill(status: status)
            }
            Text(message.text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ProgressBar(progress: progress,
                            color: status == .done ? Palette.success : Palette.accent)
                Text("\(Int(progress * 100))%")
                    .font(.caption2).foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 任务行（任务列表页）

struct TaskRow: View {
    let task: DevTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.title).font(.body.weight(.semibold))
                Spacer()
                StatusPill(status: task.status)
            }
            if !task.detail.isEmpty {
                Text(task.detail).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                ProgressBar(progress: task.progress,
                            color: task.status == .done ? Palette.success : Palette.accent)
                Text("\(Int(task.progress * 100))%")
                    .font(.caption).foregroundStyle(Palette.textSecondary).monospacedDigit()
            }
            HStack {
                if !task.assignedAgent.isEmpty {
                    Label(task.assignedAgent, systemImage: "person.crop.circle")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Text(task.updatedAt, style: .relative).font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(14)
        .background(Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
