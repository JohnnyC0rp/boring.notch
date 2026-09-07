//
//  CodexAvatarStyle.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum CodexAvatarStyle: String, CaseIterable, Identifiable {
    case smile
    case orbit
    case lines
    case colorfulOrbit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smile: return "Smile"
        case .orbit: return "Orbit"
        case .lines: return "Lines"
        case .colorfulOrbit: return "Colorful orbit"
        }
    }
}
