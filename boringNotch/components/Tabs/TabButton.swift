//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                if selected && (label == "Calendar" || label == "Clipboard") {
                    Text(label).font(.system(size: 11, weight: .semibold))
                }
            }
                .padding(.horizontal, 5)
                .frame(height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
