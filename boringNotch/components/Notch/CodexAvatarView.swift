//
//  CodexAvatarView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

/// Original geometric artwork. No OpenAI logo paths, images or animation assets are used.
struct CodexAvatarView: View {
    let style: CodexAvatarStyle
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CodexAvatarAnimation(style: style, isActive: isActive, reduceMotion: reduceMotion)
    }
}

struct CodexAvatarAnimation: View {
    let style: CodexAvatarStyle
    let isActive: Bool
    let reduceMotion: Bool
    @State private var animationStart = Date()

    private var shouldAnimate: Bool { isActive && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldAnimate)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(animationStart))
            CodexActivityGlyph(style: style, turns: shouldAnimate ? elapsed / 6 : 0)
        }
        .frame(width: 30, height: 24)
        .onChange(of: shouldAnimate, initial: true) { _, _ in animationStart = Date() }
        .accessibilityHidden(true)
    }
}

/// A deterministic frame also used by offscreen rendering tests.
struct CodexActivityGlyph: View {
    let style: CodexAvatarStyle
    var turns: Double = 0

    private var ink: AnyShapeStyle {
        if style == .colorfulOrbit {
            AnyShapeStyle(AngularGradient(colors: [.cyan, .mint, .yellow, .pink, .cyan], center: .center))
        } else {
            AnyShapeStyle(Color.white)
        }
    }

    var body: some View {
        Group {
            if style == .lines {
                HStack(spacing: 3) {
                    Capsule().frame(width: 2.4, height: 9)
                    Capsule().frame(width: 2.4, height: 17)
                    Capsule().frame(width: 2.4, height: 12)
                }
                .foregroundStyle(ink)
            } else {
                ZStack {
                    Circle().trim(from: 0.02, to: 0.37)
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    Circle().trim(from: 0.52, to: 0.87)
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    Circle().fill(ink).frame(width: 4, height: 4)
                }
                .frame(width: 18, height: 18)
            }
        }
        .frame(width: 30, height: 24)
        // Motion rotates the same ink at full opacity; idle never changes its brightness.
        .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
    }
}
