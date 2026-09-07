//
//  CodexActivityTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI

@main
enum CodexActivityTests {
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 100)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func phase(service: String = "boringnotch-codex-activity", version: Int = 1,
                   updated: Double = 100, count: Int = 1, status: CodexActivityPhase = .active) -> CodexActivityPhase {
            CodexActivitySnapshot(service: service, version: version, phase: status,
                                  updatedAt: updated, activeCount: count).validatedPhase(at: now)
        }
        expect(phase() == .active, "Fresh active metadata animates")
        expect(phase(service: "unrelated-service") == .offline, "Another service is not trusted")
        expect(phase(version: 2) == .offline, "Unknown schemas remain still")
        expect(phase(updated: 90) == .offline, "Stale data remains still")
        expect(phase(updated: 110) == .offline, "Future data remains still")
        expect(phase(count: -1) == .offline, "Negative counts are invalid")
        expect(phase(count: 0) == .offline, "Active status requires an unfinished task")
        expect(phase(status: .idle) == .offline, "Idle status cannot contain active tasks")
        let data = Data("{\"service\":\"boringnotch-codex-activity\",\"version\":1,\"phase\":\"waiting\",\"updatedAt\":100,\"activeCount\":1}".utf8)
        let decoded = try JSONDecoder().decode(CodexActivitySnapshot.self, from: data)
        expect(decoded.validatedPhase(at: now) == .waiting, "Waiting tasks remain in progress")
        for state in [CodexActivityPhase.active, .waiting] {
            expect(state.isInProgress, "Running and waiting tasks animate")
        }
        for state in [CodexActivityPhase.idle, .offline, .error] {
            expect(!state.isInProgress, "Completed, disconnected and error states remain still")
        }

        for style in [CodexAvatarStyle.orbit, .lines, .colorfulOrbit] {
            let idle = try pixels(CodexAvatarAnimation(style: style, isActive: false, reduceMotion: false))
            let reduced = try pixels(CodexAvatarAnimation(style: style, isActive: true, reduceMotion: true))
            expect(idle == reduced, "Reduce Motion and idle must render identical artwork")
            let start = try pixels(CodexActivityGlyph(style: style))
            let rotated = try pixels(CodexActivityGlyph(style: style, turns: 0.25))
            let startBrightness = brightness(start)
            let rotatedBrightness = brightness(rotated)
            expect(startBrightness > 0.04, "Every glyph must have a visible resting frame")
            expect(abs(startBrightness - rotatedBrightness) / startBrightness < 0.06,
                   "Rotation must preserve the visible amount of ink")
            expect(start != rotated, "Active motion must change the glyph's orientation")
        }
        print("\(checks) Codex activity and original artwork checks passed")
    }

    @MainActor private static func pixels(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: 30, height: 24).background(.black))
        renderer.scale = 4
        guard let image = renderer.cgImage else { throw RenderError.noImage }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw RenderError.noContext }
        return bytes
    }

    private static func brightness(_ pixels: [UInt8]) -> Double {
        let sum = stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { value, index in
            value + 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return sum / Double(pixels.count / 4) / 255
    }

    private enum RenderError: Error { case noImage, noContext }
}
