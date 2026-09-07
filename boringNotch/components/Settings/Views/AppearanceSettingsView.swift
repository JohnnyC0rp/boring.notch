//
//  AppearanceSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct Appearance: View {
    @Default(.sliderColor) var sliderColor
    @Default(.codexAvatarStyle) private var codexAvatarStyle
    @Default(.showNotHumanFace) private var showIdleAvatar
    @ObservedObject private var codexActivity = CodexActivityManager.shared
    @State private var previewAvatar = false

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

    private var realtimeAudioWaveformSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults.Toggle(key: .realtimeAudioWaveform) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real-time audio waveform")
                        Group {
                            if realtimeAudioWaveformSupported {
                                Text("Uses Accelerate FFT on the playing app's audio. Requires audio capture permission and uses slightly more CPU.")
                            } else {
                                Text("Requires macOS 14.2 or later. Update macOS to enable real-time audio waveform.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .disabled(!realtimeAudioWaveformSupported)
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Player tinting")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
            } header: {
                Text("Media")
            }
            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show avatar when music is idle or paused")
                }
                Picker("Avatar", selection: $codexAvatarStyle) {
                    ForEach(CodexAvatarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!showIdleAvatar)
                if codexAvatarStyle != .smile {
                    HStack(spacing: 12) {
                        CodexAvatarView(style: codexAvatarStyle, isActive: previewAvatar || codexActivity.isActive)
                            .padding(6)
                            .background(.black, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(codexActivity.statusText).font(.caption)
                            Text("Moves during Codex work. A still amber dot means input is needed.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Preview") { previewAvatar = true }
                            .disabled(previewAvatar)
                    }
                    .task(id: previewAvatar) {
                        guard previewAvatar else { return }
                        try? await Task.sleep(for: .seconds(3))
                        previewAvatar = false
                    }
                }
            } header: {
                HStack {
                    Text("Idle avatar")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }
}
