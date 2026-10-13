import SwiftUI
import AppKit

struct TagView: View {
    let tag: String
    var isEditing: Bool
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                Button(action: {
                    onRemove?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.themeTextSecondary)
                        .font(.caption) // Make the X mark smaller
                }
                .buttonStyle(.plain)
                .background(
                    Color.clear
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                )
                .padding(.leading, 2) // Adjust padding if needed
            }

            Text(tag)
                .font(.caption)
                .foregroundColor(Color.themeTextPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.themeAccent.opacity(0.3))
                )
        }
    }
}
