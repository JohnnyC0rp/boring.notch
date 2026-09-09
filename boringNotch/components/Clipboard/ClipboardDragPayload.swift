//
//  ClipboardDragPayload.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit

enum ClipboardDragPayload {
    static func pasteboardWriter(for item: ClipboardHistoryItem) -> any NSPasteboardWriting {
        switch item.content {
        case .text(let value, let isURL):
            let writer = NSPasteboardItem()
            writer.setString(value, forType: .string)
            if isURL { writer.setString(value, forType: .URL) }
            return writer
        case .image(let data, let type, _):
            return ClipboardImagePromiseProvider(data: data, type: type, id: item.id)
        }
    }
}

/// Offers original image bytes to editors and a file promise to Finder and upload targets.
private final class ClipboardImagePromiseProvider: NSFilePromiseProvider {
    private let imageData: Data
    private let imageType: NSPasteboard.PasteboardType
    // NSFilePromiseProvider keeps its delegate weak, so the provider owns the writer.
    private let fileWriter: ClipboardImagePromiseWriter

    init(data: Data, type: NSPasteboard.PasteboardType, id: UUID) {
        imageData = data
        imageType = type
        let fileExtension = type == .png ? "png" : "tiff"
        fileWriter = ClipboardImagePromiseWriter(data: data, filename: "Clipboard-\(id.uuidString).\(fileExtension)")
        super.init()
        fileType = type.rawValue
        delegate = fileWriter
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [imageType] + super.writableTypes(for: pasteboard)
    }

    override func writingOptions(
        forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        type == imageType ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == imageType ? imageData : super.pasteboardPropertyList(forType: type)
    }
}

private final class ClipboardImagePromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    private static let writeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Clipboard image file promises"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let data: Data
    private let filename: String

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        filename
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.writeQueue
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            // A canceled drag leaves no souvenirs: only the receiver requests this write.
            try data.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
