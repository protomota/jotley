//
//  CustomOverlays.swift
//  Jotley
//
//  Custom overlay components extracted from NoteDetailPlaceholderView+Body.swift
//

import SwiftUI

/// Custom overlay for the more menu
struct CustomMoreMenuOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content

    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.92

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Invisible background to capture clicks outside
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }
                .ignoresSafeArea()

            // Position menu at top-right, below the button
            content
                .fixedSize()
                .scaleEffect(scale, anchor: .topTrailing)
                .opacity(opacity)
                .padding(.top, 50)  // Below the toolbar button
                .padding(.trailing, 16)  // Align with right edge
        }
        .zIndex(1000)
        .onExitCommand { dismiss() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.14)) {
                opacity = 1
                scale = 1
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            opacity = 0
            scale = 0.92
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }
}

// MARK: - Transcript Button Indicator Wrapper
