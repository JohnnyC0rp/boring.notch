import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var manager: ClipboardHistoryManager
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var copiedID: UUID?
    @State private var copyFailed = false
    @FocusState private var searchIsFocused: Bool

    init(manager: ClipboardHistoryManager? = nil) {
        self.manager = manager ?? .shared
    }

    private var results: [ClipboardHistoryItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.items.filter { $0.matches(search) }
    }

    var body: some View {
        VStack(spacing: 9) {
            controls
            if results.isEmpty {
                emptyState
            } else {
                history
            }
            footer
        }
        .onChange(of: query) { selectedID = results.first?.id }
        .onChange(of: manager.items.map(\.id)) {
            if !results.contains(where: { $0.id == selectedID }) {
                selectedID = results.first?.id
            }
        }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onDisappear {
            searchIsFocused = false
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
                LazyVStack(spacing: 4) {
                    ForEach(results) { item in
                        ClipboardHistoryRow(
                            item: item,
                            isSelected: selectedID == item.id,
                            isCopied: copiedID == item.id,
                            copy: { copy(item) },
                            delete: { manager.delete(item) }
                        )
                        .id(item.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
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
            Text(copyFailed ? "Copy failed. Try again." : (copiedID != nil ? "Copied · paste with ⌘V" : "Click to copy · then ⌘V"))
                .foregroundStyle(copyFailed ? .orange : .white.opacity(0.4))
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.4))
        .accessibilityElement(children: .combine)
        .help("History stays in memory. Copies marked sensitive and supported password-manager apps are skipped. Unmarked secrets can still appear; pause capture before copying them.")
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : results.count)
        selectedID = results[min(max(current + offset, 0), results.count - 1)].id
    }

    private func copySelected() {
        guard let item = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        copy(item)
    }

    private func copy(_ item: ClipboardHistoryItem) {
        selectedID = item.id
        copyFailed = !manager.copy(item)
        copiedID = copyFailed ? nil : item.id
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let isCopied: Bool
    let copy: () -> Void
    let delete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: copy) {
                HStack(spacing: 8) {
                    sourceIcon
                        .frame(width: 17, height: 17)
                    if case .image(_, _, let thumbnail) = item.content {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(item.content.preview)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: 4)
                    if isCopied {
                        Text("Copied")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green.opacity(0.9))
                    } else {
                        Text(item.capturedAt, style: .time)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.leading, 7)
                .padding(.trailing, 5)
                .frame(height: 27)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy from \(item.source.name)")
            .accessibilityLabel("\(item.content.preview), from \(item.source.name). Copy")

            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 22, height: 27)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .help("Delete this copy from history")
            .accessibilityLabel("Delete copy from history")
        }
        .background(.white.opacity(isSelected ? 0.13 : (isHovered ? 0.1 : 0.06)), in: RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy", action: copy)
            Button("Delete from History", role: .destructive, action: delete)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let bundleIdentifier = item.source.bundleIdentifier {
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
