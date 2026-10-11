import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var store: Store
    let conversationId: String

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    @State private var sending = false

    // 待发送附件
    @State private var pickedImages: [UIImage] = []
    @State private var pickedFiles: [OutgoingFile] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    private var conversation: Conversation? {
        store.conversations.first { $0.id == conversationId }
    }

    private var msgs: [AgentMessage] {
        store.messages(for: conversationId).sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(msgs) { m in
                            MessageBubble(message: m)
                                .id(m.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .animation(.easeOut(duration: 0.18), value: msgs.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = msgs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            composer
        }
        .navigationTitle(conversation?.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(conversation?.title ?? "会话").font(.headline)
                    if let conv = conversation {
                        Text(conv.isOnline ? "在线" : "离线")
                            .font(.caption2)
                            .foregroundStyle(conv.isOnline ? Color.green : Color.secondary)
                    }
                }
            }
        }
        .onAppear { store.markRead(conversationId) }
        .onChange(of: conversationId) { _ in store.markRead(conversationId) }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
    }

    // MARK: - 输入区

    private var composer: some View {
        VStack(spacing: 8) {
            if !pickedImages.isEmpty || !pickedFiles.isEmpty {
                pendingAttachmentsRow
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $photoPickerItems,
                             maxSelectionCount: 9,
                             matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .onChange(of: photoPickerItems) { items in
                    Task { await loadImages(items) }
                }

                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }

                TextField("回复智能体…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Palette.accent : Color(.systemGray3))
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private var pendingAttachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pickedImages.indices, id: \.self) { i in
                    Image(uiImage: pickedImages[i])
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                pickedImages.remove(at: i)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                        }
                }
                ForEach(pickedFiles.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Image(systemName: "doc").foregroundStyle(Palette.accent)
                        Text(pickedFiles[i].name).font(.caption).lineLimit(1)
                        Button {
                            pickedFiles.remove(at: i)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 逻辑

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pickedImages.isEmpty || !pickedFiles.isEmpty) && !sending
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        await MainActor.run {
            pickedImages.append(contentsOf: loaded)
            photoPickerItems = []
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pickedFiles.append(OutgoingFile(
                    name: url.lastPathComponent,
                    mimeType: AttachmentHelper.mime(forFilename: url.lastPathComponent),
                    data: data
                ))
            }
        }
    }

    private func send() async {
        let text = draft
        let images = pickedImages
        let files = pickedFiles
        draft = ""
        pickedImages = []
        pickedFiles = []
        sending = true
        await store.sendMessage(text: text, images: images, files: files)
        sending = false
    }
}
