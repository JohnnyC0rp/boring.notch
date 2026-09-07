import ImageIO
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var manager: ClipboardHistoryManager
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var copiedID: UUID?
    @State private var previewID: UUID?
    @State private var copyFailed = false
    @FocusState private var searchIsFocused: Bool
    @FocusState private var gridIsFocused: Bool

    init(manager: ClipboardHistoryManager? = nil) {
        self.manager = manager ?? .shared
    }

    private var results: [ClipboardHistoryItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.items.filter { $0.matches(search) }
    }

    private var previewItem: ClipboardHistoryItem? {
        manager.items.first { $0.id == previewID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = previewItem {
                ClipboardHistoryPreview(
                    item: item,
                    isCopied: copiedID == item.id,
                    copyFailed: copyFailed,
                    back: { previewID = nil },
                    copy: { copy(item) },
                    delete: {
                        manager.delete(item)
                        previewID = nil
                    }
                )
                .id(item.id)
            } else {
                VStack(spacing: 9) {
                    controls
                    if results.isEmpty {
                        emptyState
                    } else {
                        history
                    }
                    footer
                }
            }
        }
        .frame(height: 236)
        .onChange(of: query) { selectedID = results.first?.id }
        .onChange(of: manager.items.map(\.id)) {
            if !results.contains(where: { $0.id == selectedID }) {
                selectedID = results.first?.id
            }
            if previewItem == nil { previewID = nil }
        }
        .onKeyPress(.downArrow) {
            guard previewID == nil else { return .ignored }
            if searchIsFocused {
                searchIsFocused = false
                gridIsFocused = true
                selectedID = selectedID ?? results.first?.id
            } else {
                moveSelection(by: 4)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard previewID == nil else { return .ignored }
            moveSelection(by: -4)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard gridIsFocused, previewID == nil else { return .ignored }
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard gridIsFocused, previewID == nil else { return .ignored }
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard gridIsFocused, previewID == nil else { return .ignored }
            copySelected()
            return .handled
        }
        .onKeyPress(.space) {
            guard gridIsFocused, let item = results.first(where: { $0.id == selectedID }) else { return .ignored }
            preview(item)
            return .handled
        }
        .onExitCommand { previewID = nil }
        .onDisappear {
            searchIsFocused = false
            gridIsFocused = false
            if let window = NSApp.keyWindow as? BoringNotchSkyLightWindow {
                window.makeFirstResponder(nil)
                window.resignKey()
            }
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copiedID = nil
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search, or type an app name", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                    .onSubmit { copySelected() }
                    .accessibilityLabel("Search clipboard history")
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.07), in: Capsule())

            Button {
                manager.setPaused(!manager.isPaused)
            } label: {
                Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(manager.isPaused ? .orange : .white.opacity(0.65))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help(manager.isPaused ? "Resume clipboard capture" : "Pause clipboard capture")
            .accessibilityLabel(manager.isPaused ? "Resume clipboard capture" : "Pause clipboard capture")

            Button("Clear") {
                manager.clearHistory()
                copiedID = nil
                copyFailed = false
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(manager.items.isEmpty ? 0.25 : 0.7))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.07), in: Capsule())
            .disabled(manager.items.isEmpty)
            .help("Delete all clipboard history; the current clipboard stays available")
        }
    }

    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 4), spacing: 8) {
                    ForEach(results) { item in
                        ClipboardHistoryTile(
                            item: item,
                            isSelected: selectedID == item.id,
                            isCopied: copiedID == item.id,
                            preview: { preview(item) },
                            copy: { copy(item) },
                            delete: { manager.delete(item) }
                        )
                        .id(item.id)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($gridIsFocused)
            .focusEffectDisabled()
            .onAppear {
                if let selectedID { proxy.scrollTo(selectedID) }
            }
            .onChange(of: selectedID) {
                if let selectedID { proxy.scrollTo(selectedID) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: manager.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(manager.items.isEmpty ? (manager.isPaused ? "Clipboard capture is paused" : "Your next copy starts here") : "No matching copies")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(manager.items.isEmpty ? "Text, links and images appear as you copy them." : "Try a different word or app name.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(manager.isPaused ? .orange : .white.opacity(0.35))
                .frame(width: 4, height: 4)
            Text(manager.isPaused ? "Capture paused" : "Stored until quit")
            Spacer()
            Text(copyFailed ? "Copy failed. Try again." : (copiedID != nil ? "Copied · paste with ⌘V" : "Click a tile to copy · Preview to expand"))
                .foregroundStyle(copyFailed ? .orange : .white.opacity(0.4))
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.4))
        .accessibilityElement(children: .combine)
        .help("History stays in memory. Copies marked sensitive and supported password-manager apps are skipped. Unmarked secrets can still appear; pause capture before copying them.")
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -offset : results.count - offset - 1)
        selectedID = results[min(max(current + offset, 0), results.count - 1)].id
    }

    private func copySelected() {
        guard let item = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        copy(item)
    }

    private func preview(_ item: ClipboardHistoryItem) {
        selectedID = item.id
        previewID = item.id
        searchIsFocused = false
        gridIsFocused = false
        copyFailed = false
    }

    private func copy(_ item: ClipboardHistoryItem) {
        selectedID = item.id
        copyFailed = !manager.copy(item)
        copiedID = copyFailed ? nil : item.id
    }
}

private struct ClipboardHistoryTile: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let isCopied: Bool
    let preview: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(.white.opacity(isHovered ? 0.18 : 0.13))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        Button(action: copy) {
                            tileContent(size: geometry.size)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy from \(item.source.name)")
                        .accessibilityLabel("\(item.content.preview), from \(item.source.name). Copy")

                        VStack(spacing: 0) {
                            metadata
                            Spacer(minLength: 0)
                            actions
                        }
                        .padding(7)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.white.opacity(isSelected ? 0.55 : 0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Preview", action: preview)
                Button("Copy", action: copy)
                Button("Delete from History", role: .destructive, action: delete)
            }
    }

    @ViewBuilder
    private func tileContent(size: CGSize) -> some View {
        switch item.content {
        case .image(_, _, let thumbnail):
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.7), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.65),
                        .init(color: .black.opacity(0.65), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        case .text(let value, _):
            Text(String(value.prefix(600)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 30)
                .padding(.bottom, 35)
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            ClipboardSourceIcon(source: item.source)
                .frame(width: 13, height: 13)
            Text(item.source.name)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(item.capturedAt, style: .time)
                .font(.system(size: 7, design: .monospaced))
                .fixedSize()
        }
        .foregroundStyle(.white.opacity(0.75))
        .allowsHitTesting(false)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: preview) {
                Label("Preview", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .help("Preview the complete copy")
            Button(action: copy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .white)
                    .frame(width: 22)
            }
            .accessibilityLabel(isCopied ? "Copied" : "Copy")
            .help(isCopied ? "Copied · paste with ⌘V" : "Copy")
            Button(action: delete) {
                Image(systemName: "trash")
                    .frame(width: 22)
            }
            .accessibilityLabel("Delete copy from history")
            .help("Delete copy from history")
        }
        .font(.system(size: 10))
        .buttonStyle(ClipboardTileActionStyle())
    }
}

private struct ClipboardTileActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 24)
            .foregroundStyle(.white.opacity(0.9))
            .background(.black.opacity(configuration.isPressed ? 0.7 : 0.4), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ClipboardHistoryPreview: View {
    let item: ClipboardHistoryItem
    let isCopied: Bool
    let copyFailed: Bool
    let back: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Back to clipboard grid")
                ClipboardSourceIcon(source: item.source)
                    .frame(width: 15, height: 15)
                Text(item.source.name)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button(action: copy) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(isCopied ? .green : .white)
                }
                Button(action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .frame(height: 28)

            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Text(item.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Spacer()
                Text(copyFailed ? "Copy failed. Try again." : (isCopied ? "Copied · paste with ⌘V" : "Copy, then paste with ⌘V"))
                    .foregroundStyle(copyFailed ? .orange : .white.opacity(0.4))
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
        }
        .task(id: item.id) { loadPreviewImage() }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.content {
        case .image(_, _, let thumbnail):
            Image(nsImage: image ?? thumbnail)
                .resizable()
                .scaledToFit()
                .padding(4)
                .accessibilityLabel("Full image preview")
        case .text(let value, _):
            ScrollView(.vertical) {
                Text(value)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
    }

    private func loadPreviewImage() {
        guard case .image(let data, _, _) = item.content,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return }
        // Retina-sized preview; the original bytes stay ready for Copy.
        image = NSImage(cgImage: preview, size: .zero)
    }
}

private struct ClipboardSourceIcon: View {
    let source: ClipboardSourceApplication

    var body: some View {
        if let bundleIdentifier = source.bundleIdentifier {
            AppIcon(for: bundleIdentifier)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "doc.on.clipboard")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.5))
                .padding(2)
        }
    }
}
