//
//  CodexActivityPhase.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum CodexActivityPhase: String, Decodable {
    case offline, idle, active, waiting, error

    var isInProgress: Bool { self == .active || self == .waiting }

    var statusText: String {
        switch self {
        case .offline: return "Codex is disconnected"
        case .idle: return "Codex is ready"
        case .active: return "Codex is working"
        case .waiting: return "Codex needs your attention"
        case .error: return "Codex reported an error"
        }
    }
}

struct CodexActivitySnapshot: Decodable {
    let service: String
    let version: Int
    let phase: CodexActivityPhase
    let updatedAt: TimeInterval
    let activeCount: Int

    func validatedPhase(at now: Date) -> CodexActivityPhase {
        let age = now.timeIntervalSince1970 - updatedAt
        guard service == "boringnotch-codex-activity", version == 1,
              age >= -2, age <= 8, activeCount >= 0,
              phase.isInProgress == (activeCount > 0) else { return .offline }
        return phase
    }
}
