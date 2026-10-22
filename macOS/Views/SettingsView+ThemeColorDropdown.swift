import SwiftUI

// MARK: - Custom Theme Color Dropdown

struct ThemeColorDropdown: View {
    @Binding var selection: ThemeColor
    @Binding var isShowing: Bool
    @State private var hoveredColor: ThemeColor? = nil

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(selection.previewColor)
                    .frame(width: 12, height: 12)
                Text(selection.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ThemeColor.allCases, id: \.self) { color in
                    Button {
                        selection = color
                        isShowing = false
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color.previewColor)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                            Spacer()
                            if color == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(color.color)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredColor == color ? color.color.opacity(0.2) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredColor = hovering ? color : nil
                    }
                }
            }
            .padding(6)
            .frame(width: 160)
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
