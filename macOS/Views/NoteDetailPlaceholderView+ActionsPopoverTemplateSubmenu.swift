import SwiftUI

extension NoteDetailPlaceholderView {
    struct TemplateSubmenu: View {
        static let width: CGFloat = 300

        let note: Note
        let availableTemplates: [Template]
        let onSelectTemplate: (String) -> Void
        var onManageTemplates: (Bool) -> Void = { _ in }

        @Environment(\.colorScheme) private var colorScheme
        @ObservedObject private var theme = ThemeManager.shared
        @State private var hoveredItem: String?

        private var accent: Color { theme.currentThemeColor.color(in: colorScheme) }
        private var currentTemplateKey: String {
            (try? SummaryTemplateStore.shared.resolve(note.summaryType).key) ?? note.summaryType ?? LocalSummaryTemplate.auto.key
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Summary Template")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 8)

                templateRow(
                    key: LocalSummaryTemplate.auto.key,
                    title: LocalSummaryTemplate.auto.title,
                    icon: "sparkles",
                    detail: "Choose a format based on this note."
                )

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        section("My Templates", icon: "person.crop.circle", templates: availableTemplates.filter { $0.key.hasPrefix("custom/") })
                        section("Notes & Study", icon: "text.alignleft", templates: availableTemplates.filter {
                            $0.key != LocalSummaryTemplate.auto.key && !$0.key.hasPrefix("custom/") && $0.category == nil
                        })
                        section("Meetings & Projects", icon: "person.2", templates: availableTemplates.filter { $0.category != nil && !$0.key.hasPrefix("custom/") })
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: 286)

                Divider()

                HStack(spacing: 8) {
                    Button { onManageTemplates(true) } label: {
                        Label("New Template", systemImage: "plus")
                    }
                    Spacer(minLength: 0)
                    Button { onManageTemplates(false) } label: {
                        Label("Manage", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Manage Templates")
                }
                .font(.callout.weight(.medium))
                .tint(accent)
                .padding(.horizontal, 4)
            }
            .padding(12)
            .frame(width: Self.width)
        }

        @ViewBuilder private func section(_ title: String, icon: String, templates: [Template]) -> some View {
            if !templates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 3)
                    ForEach(templates, id: \.key) { template in
                        templateRow(key: template.key, title: template.title)
                    }
                }
            }
        }

        private func templateRow(key: String, title: String, icon: String? = nil, detail: String? = nil) -> some View {
            let selected = currentTemplateKey == key
            let shape = RoundedRectangle(cornerRadius: 8)
            return Button { onSelectTemplate(key) } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.callout.weight(selected || icon != nil ? .semibold : .regular))
                        if let detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, icon == nil ? 5 : 8)
                .frame(minHeight: 28)
                .background(hoveredItem == key || selected ? Color.primary.opacity(0.06) : .clear, in: shape)
                .overlay { shape.strokeBorder(selected ? accent.opacity(0.65) : .clear, lineWidth: 1).allowsHitTesting(false) }
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { hoveredItem = key }
                else if hoveredItem == key { hoveredItem = nil }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("noteTemplate-\(key)")
        }
    }
}
