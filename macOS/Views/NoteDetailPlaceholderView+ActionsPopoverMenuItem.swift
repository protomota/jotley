import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {
    struct MenuItemView: View {
        let icon: String
        let title: String
        var assetIconName: String? = nil
        var subtitle: String? = nil
        var iconColor: Color? = nil
        var hasSubmenu: Bool = false
        var submenuExpanded: Bool = false
        var shortcut: String? = nil
        var badge: String? = nil
        var disabled: Bool = false
        var onHover: ((Bool) -> Void)? = nil
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button {
                if !disabled {
                    action()
                }
            } label: {
                HStack(spacing: 12) {
                    if let assetIconName {
                        Image(assetIconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .opacity(iconColor == nil ? 0.8 : 1.0)
                            .frame(width: 20)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(iconColor ?? Color.primary.opacity(0.7))
                            .frame(width: 20)
                    }

                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Spacer()

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    if hasSubmenu {
                        Image(systemName: submenuExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if let shortcut = shortcut {
                        Text(shortcut)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isHovered ? Color.themePrimaryAccent.opacity(0.15) : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(disabled ? 0.5 : 1.0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
                onHover?(hovering)
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }
}
