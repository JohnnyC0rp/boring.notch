import AppKit

/// Synthetic fixtures and a named pasteboard keep the user's clipboard untouched.
@main
@MainActor
struct ClipboardDragPayloadTests {
    private static var assertions = 0
    private static let source = ClipboardSourceApplication(name: "Synthetic App", bundleIdentifier: nil)

    static func main() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-drag-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let text = "First original line\nSecond original line"
        let url = "https://example.com/a?query=synthetic#section"
        let png = imageData(type: .png)
        let tiff = imageData(type: .tiff)
        let items = [
            ClipboardHistoryItem(content: .text(text, isURL: false), source: source),
            ClipboardHistoryItem(content: .text(url, isURL: true), source: source),
            imageItem(png, type: .png),
            imageItem(tiff, type: .tiff)
        ]
        let writers = items.map { ClipboardDragPayload.pasteboardWriter(for: $0) }
        expect(writers.count == items.count, "Each selected history entry gets its own native drag item")
        expect(board.writeObjects(writers), "Write a mixed selection to an isolated drag pasteboard")
        guard let output = board.pasteboardItems, output.count == 4 else {
            fatalError("Expected four pasteboard items in selection order")
        }
        expect(output[0].string(forType: .string) == text, "Text preserves whitespace and order")
        expect(output[0].string(forType: .URL) == nil, "Plain text does not claim URL semantics")
        expect(output[1].string(forType: .string) == url, "URLs retain a plain text representation")
        expect(output[1].string(forType: .URL) == url, "URLs retain their native URL representation")
        expect(output[2].data(forType: .png) == png, "PNG drag provides original encoded bytes")
        expect(output[3].data(forType: .tiff) == tiff, "TIFF drag provides original encoded bytes")
        expect(output[2].string(forType: .fileURL) == nil, "Images do not point to temporary exported files")
        expect(output[3].string(forType: .fileURL) == nil, "TIFF images do not point to temporary exported files")
        try expect(FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty, "Starting a drag does not write promised files")

        try checkPromise(writers[2], original: png, extension: "png", directory: directory)
        try checkPromise(writers[3], original: tiff, extension: "tiff", directory: directory)

        let duplicate = ClipboardDragPayload.pasteboardWriter(for: imageItem(png, type: .png))
        expect(promiseName(duplicate) != promiseName(writers[2]), "Different entries receive distinct promised filenames")
        let beforeCancellation = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        do {
            let canceled = ClipboardDragPayload.pasteboardWriter(for: imageItem(png, type: .png))
            expect(canceled is NSFilePromiseProvider, "A canceled image drag retains promise semantics")
        }
        try expect(FileManager.default.contentsOfDirectory(atPath: directory.path) == beforeCancellation, "Discarding a drag without a receiver creates no promised files")
        print("Clipboard drag payloads: \(assertions) assertions passed using original synthetic image data and an isolated pasteboard.")
    }

    private static func checkPromise(_ writer: any NSPasteboardWriting, original: Data, extension fileExtension: String, directory: URL) throws {
        guard let provider = writer as? NSFilePromiseProvider, let delegate = provider.delegate else {
            fatalError("Image writer must retain its file-promise delegate")
        }
        let filename = delegate.filePromiseProvider(provider, fileNameForType: provider.fileType)
        expect(filename.hasSuffix(".\(fileExtension)"), "Promised filename preserves the encoded image format")
        expect(!filename.contains("/"), "Promised name is a filename, not a path")
        let destination = directory.appendingPathComponent(filename)
        expect(!FileManager.default.fileExists(atPath: destination.path), "Promised file is absent before a receiver requests it")
        var completed = false
        var writeError: Error?
        delegate.filePromiseProvider(provider, writePromiseTo: destination) { error in
            completed = true
            writeError = error
        }
        expect(completed && writeError == nil, "Receiver-requested image export completes successfully")
        try expect(Data(contentsOf: destination) == original, "Promised file contains original bytes, never the display thumbnail")
    }

    private static func promiseName(_ writer: any NSPasteboardWriting) -> String {
        guard let provider = writer as? NSFilePromiseProvider, let delegate = provider.delegate else {
            fatalError("Expected a retained image file-promise delegate")
        }
        return delegate.filePromiseProvider(provider, fileNameForType: provider.fileType)
    }

    private static func imageItem(_ data: Data, type: NSPasteboard.PasteboardType) -> ClipboardHistoryItem {
        ClipboardHistoryItem(content: .image(data, type: type, thumbnail: NSImage(size: NSSize(width: 1, height: 1))), source: source)
    }

    private static func imageData(type: NSBitmapImageRep.FileType) -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { fatalError("Could not create synthetic image") }
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        for x in 0..<16 {
            for y in 0..<8 {
                bitmap.setColor(x.isMultiple(of: 2) ? white : black, atX: x, y: y)
            }
        }
        guard let data = bitmap.representation(using: type, properties: [:]) else {
            fatalError("Could not encode synthetic image")
        }
        return data
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
        assertions += 1
        let passed = try condition()
        precondition(passed, label)
    }
}
