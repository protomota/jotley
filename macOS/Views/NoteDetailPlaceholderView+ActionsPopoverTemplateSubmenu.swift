import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {
    // Template submenu view
    struct TemplateSubmenu: View {
        let note: Note
        let availableTemplates: [Template]
        let onSelectTemplate: (String) -> Void
        var onManageTemplates: (Bool) -> Void = { _ in }
        @State private var hoveredItem: String? = nil

        // Get the current template key from note
        private var currentTemplateKey: String {
            (try? SummaryTemplateStore.shared.resolve(note.summaryType).key) ?? note.summaryType ?? "default-summary"
        }

        private func updateHoverCursor(_ hovering: Bool) {
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }

        var body: some View {
            ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
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
                    ForEach(availableTemplates.filter { $0.key != "default-summary" && !$0.key.hasPrefix("custom/") }, id: \.key) { template in
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
                    if availableTemplates.contains(where: { $0.key.hasPrefix("custom/") }) {
                        Divider().padding(.vertical, 5)
                        Text("My Templates").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 12)
                        ForEach(availableTemplates.filter { $0.key.hasPrefix("custom/") }, id: \.key) { template in
                            Button { onSelectTemplate(template.key) } label: {
                                HStack {
                                    Text(template.title).lineLimit(1)
                                    Spacer()
                                    if currentTemplateKey == template.key { Image(systemName: "checkmark").foregroundStyle(Color.themePrimaryAccent) }
                                }.padding(.vertical, 5).padding(.horizontal, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    Divider().padding(.vertical, 5)
                    Button("New Template…") { onManageTemplates(true) }.buttonStyle(.plain).padding(8)
                    Button("Manage Templates…") { onManageTemplates(false) }.buttonStyle(.plain).padding(8)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            }
            .frame(width: 260, height: 500)
            .modifier(MacNoteMenuSurface())
        }
    }
}
