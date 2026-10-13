import SwiftUI
import AppKit

// MARK: - Tooltip Content View
struct TooltipContentView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: - Floating Tooltip Modifier
struct FloatingTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverWorkItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering

                // Cancel any pending show/hide operations
                hoverWorkItem?.cancel()

                if hovering {
                    // Create a new work item to show tooltip after delay
                    let workItem = DispatchWorkItem {
                        if isHovering {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                showTooltip = true
                            }
                        }
                    }
                    hoverWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
                } else {
                    // Hide immediately on mouse leave
                    withAnimation(.easeInOut(duration: 0.08)) {
                        showTooltip = false
                    }
                }
            }
            .overlay {
                if showTooltip {
                    TooltipContentView(text: text)
                        .fixedSize()
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                        )
                        .offset(y: -34)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }
}

extension View {
    func floatingTooltip(_ text: String) -> some View {
        self.modifier(FloatingTooltip(text: text))
    }
}

// Add this extension to disable clipping
