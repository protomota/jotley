import SwiftUI

/// Unified filter + sort popover used by both macOS and iOS notes list views.
/// The caller owns a `FilterAndSortState` and provides the currently-known
/// set of tag names plus a count lookup for display.
struct FilterAndSortPopoverView: View {
    @ObservedObject var state: FilterAndSortState
    let allTags: [String]
    let tagCounts: [String: Int]
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Divider()
                    sortSection
                    Divider()
                    matchModeSection
                    Divider()
                    tagSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(macOS)
            .frame(maxHeight: 480)
            #endif

            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.themeContentBackground)
        }
        .background(Color.themeContentBackground)
        #if os(macOS)
        .frame(width: 280)
        .cornerRadius(8)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Filter & Sort")
                .font(.headline)
                .foregroundColor(Color.themeTextPrimary)
            Spacer()
            Button("Reset") {
                state.clearAll()
            }
            .font(.subheadline)
            .foregroundColor(Color.themePrimaryAccent)
            .buttonStyle(.plain)
            .opacity(state.isActive ? 1 : 0)
            .disabled(!state.isActive)
            .accessibilityHidden(!state.isActive)
        }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sort by")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.themeTextSecondary)
                .textCase(.uppercase)

            Picker("Sort by", selection: $state.sortOption) {
                ForEach(NotesSortOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.themePrimaryAccent)
        }
    }

    private var matchModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tag match")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.themeTextSecondary)
                .textCase(.uppercase)

            Picker("Match", selection: $state.tagMatchMode) {
                ForEach(TagMatchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(state.tagMatchMode.helpText)
                .font(.caption)
                .foregroundColor(Color.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.themeTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Button("Clear") {
                    state.selectedTags.removeAll()
                }
                .font(.subheadline)
                .foregroundColor(Color.themePrimaryAccent)
                .buttonStyle(.plain)
                .opacity(state.selectedTags.isEmpty ? 0 : 1)
                .disabled(state.selectedTags.isEmpty)
                .accessibilityHidden(state.selectedTags.isEmpty)
            }

            if allTags.isEmpty {
                Text("No tags available")
                    .font(.caption)
                    .foregroundColor(Color.themeTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(allTags, id: \.self) { tag in
                        tagRow(tag)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func tagRow(_ tag: String) -> some View {
        let isSelected = state.selectedTags.contains(tag)
        return Button {
            state.toggleTag(tag)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.themePrimaryAccent : Color.themeTextSecondary)
                Text(tag)
                    .font(.subheadline)
                    .foregroundColor(Color.themeTextPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(tagCounts[tag, default: 0])")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Color.themeTextSecondary)
            }
            .padding(.horizontal, 6)
            #if os(iOS)
            .frame(minHeight: 38)
            #else
            .padding(.vertical, 3)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.themePrimaryAccent)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }
}
