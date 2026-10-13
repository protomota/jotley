import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {
    // Template submenu view
    struct TemplateSubmenu: View {
        let note: Note
        let availableTemplates: [Template]
        let onSelectTemplate: (String) -> Void
        @State private var hoveredItem: String? = nil

        // Get the current template key from note
        private var currentTemplateKey: String {
            LocalSummaryTemplate.resolve(note.summaryType).key
        }

        // Get the current template name
        private var currentTemplateName: String {
            if currentTemplateKey == "default-summary" {
                return "Auto"
            }
            return availableTemplates.first { $0.key == currentTemplateKey }?.title ?? "Auto"
        }

        private func updateHoverCursor(_ hovering: Bool) {
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Regenerate option - uses current template
                    Button {
                        onSelectTemplate(currentTemplateKey)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Color.themePrimaryAccent)
                                .frame(width: 16)
                                .font(.system(size: 12))

                            VStack(alignment: .leading, spacing: 0) {
                                Text("Regenerate")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("Using \(currentTemplateName) template")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(hoveredItem == "regenerate" ? Color.themePrimaryAccent.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredItem = hovering ? "regenerate" : nil
                        updateHoverCursor(hovering)
                    }

                    Divider()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)

                    // Change Template header
                    Text("Change Template")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                    // Auto/Default template
                    Button {
                        onSelectTemplate("default-summary")
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(Color.themePrimaryAccent)
                                .frame(width: 16)
                                .font(.system(size: 12))

                            Text("Auto")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            if currentTemplateKey == "default-summary" {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.themePrimaryAccent)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(hoveredItem == "default-summary" ? Color.themePrimaryAccent.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredItem = hovering ? "default-summary" : nil
                        updateHoverCursor(hovering)
                    }

                    // Other templates
                    ForEach(availableTemplates.filter { $0.key != "default-summary" }, id: \.key) { template in
                        Button {
                            onSelectTemplate(template.key)
                        } label: {
                            HStack(spacing: 8) {
                                // Empty space to align with Auto template
                                Color.clear
                                    .frame(width: 16)

                                Text(template.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                if currentTemplateKey == template.key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Color.themePrimaryAccent)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .background(hoveredItem == template.key ? Color.themePrimaryAccent.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredItem = hovering ? template.key : nil
                            updateHoverCursor(hovering)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .frame(width: 260)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
            .compositingGroup() // Ensures the view renders as a single unit
        }
    }
}
