//
//  ButtonStyles.swift
//  Jotley
//
//  Button styles extracted from NoteDetailPlaceholderView+Body.swift
//

import SwiftUI
import AppKit


// MARK: - Create Note Button Style

struct CreateNoteButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(isHovering ? (isPrimary ? 0.08 : 0.05) : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}
