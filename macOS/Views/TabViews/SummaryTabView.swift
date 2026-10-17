import SwiftUI
import AppKit

// View for the Summary tab content
struct SummaryTabView: View {
    @ObservedObject var note: Note
    @Binding var editableSummary: String
    @FocusState.Binding var isSummaryEditorFocused: Bool
    @Binding var inlineEditRequestCounter: Int
    @Binding var isGeneratingSummary: Bool
    @Binding var summaryGenerationError: String?
    @Binding var showRawMarkdown: Bool
    let summaryLoadingStartedAt: Date?
    @ObservedObject var streamingSummaryViewModel: StreamingSummaryViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var inlineEditRequested = false
    @State private var previousRawMarkdownMode = false
    @State private var inlineEditorHeight: CGFloat = ContentLayoutConstants.standardMinHeight

    // Optional callback for generating summary
    private let compactContentPadding = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

    private var isPlaceholderSummaryText: Bool {
        let editable = editableSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let persisted = (note.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return editable == "Generating summary..." || persisted == "Generating summary..."
    }

    private var isInlineEditing: Bool {
        !isGeneratingSummary && (showRawMarkdown || inlineEditRequested || isSummaryEditorFocused)
    }

    private var doneButtonForegroundColor: Color {
        .white
    }

    private var summaryTextToRender: String {
        if isGeneratingSummary {
            return streamingSummaryViewModel.displayedText
        }
        // Stale "Generating summary..." placeholder is not real content — render nothing
        // so the tab falls through to its empty state instead of showing placeholder text.
        if isPlaceholderSummaryText {
            return ""
        }
        return editableSummary
    }

    private var hasSummaryTextToRender: Bool {
        !summaryTextToRender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowSummaryLoader: Bool {
        isGeneratingSummary && !hasSummaryTextToRender
    }

    private func beginInlineEditing() {
        guard !isInlineEditing else { return }

        previousRawMarkdownMode = showRawMarkdown
        inlineEditRequested = true
        showRawMarkdown = true

        DispatchQueue.main.async {
            isSummaryEditorFocused = true
        }
    }

    private func finishInlineEditing() {
        isSummaryEditorFocused = false

        if inlineEditRequested {
            inlineEditRequested = false
            showRawMarkdown = previousRawMarkdownMode
        }
    }

    private func handleInlineEditRequest(_ newValue: Int) {
        guard newValue > 0, !isGeneratingSummary else { return }
        // Consume the request so recreating this view cannot reopen the editor.
        inlineEditRequestCounter = 0
        beginInlineEditing()
    }

    private func endInlineEditingIfNeeded(oldValue: Bool, newValue: Bool) {
        guard oldValue, !newValue, inlineEditRequested else { return }
        inlineEditRequested = false
        showRawMarkdown = previousRawMarkdownMode
    }

    var body: some View {
        Group {
            if shouldShowSummaryLoader {
                Text("Long transcripts are reviewed in sections on this device. Your summary will appear here as it is written.")
                    .font(.system(size: 15)).foregroundColor(.themeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .accessibilityIdentifier("noteDetailSummaryLoading")
            } else if isGeneratingSummary || hasSummaryTextToRender || isSummaryEditorFocused {
                // Use our controlled displaySummary instead of directly accessing note.summary
                VStack(alignment: .leading, spacing: 8) {
                    if let summaryGenerationError, !summaryGenerationError.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange.opacity(0.9))
                            Text(summaryGenerationError)
                                .font(.system(size: 13))
                                .foregroundColor(Color.themeTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                    }

                    ZStack(alignment: .topLeading) {
                    if isInlineEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Spacer()

                                Button {
                                    finishInlineEditing()
                                } label: {
                                    Label("Done", systemImage: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(doneButtonForegroundColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .fill(Color.themePrimaryAccent)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("noteDetailSummaryDoneButton")
                            }
                            .padding(.horizontal, 8)

                            ZStack(alignment: .topLeading) {
                                InlineEditableSummaryTextView(
                                    text: $editableSummary,
                                    isFocused: $isSummaryEditorFocused,
                                    accentColor: NSColor(themeManager.currentThemeColor.color),
                                    textColor: NSColor(Color.themeTextPrimary),
                                    measuredHeight: $inlineEditorHeight
                                )
                                .padding(compactContentPadding)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: max(inlineEditorHeight, ContentLayoutConstants.standardMinHeight),
                                    alignment: .topLeading
                                )
                                .onAppear {
                                    if inlineEditRequested {
                                        DispatchQueue.main.async {
                                            isSummaryEditorFocused = true
                                        }
                                    }
                                }
                                .accessibilityIdentifier("noteDetailSummaryEditor")

                            if editableSummary.isEmpty && !note.isFault && !isSummaryEditorFocused {
                                Text("No summary available")
                                    .font(.body)
                                    .foregroundColor(Color.themeTextSecondary.opacity(0.7))
                                    .italic()
                                    .padding(.leading, 24)
                                    .padding(.top, 24)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            }
                        }
                    } else {
                        if !hasSummaryTextToRender {
                            Text("No summary available")
                                .font(.body)
                                .foregroundColor(Color.themeTextSecondary.opacity(0.7))
                                .italic()
                                .padding(compactContentPadding)
                                .frame(maxWidth: .infinity, minHeight: ContentLayoutConstants.standardMinHeight, alignment: .center)
                        } else {
                            StructuredSummaryView(content: summaryTextToRender)
                                .padding(compactContentPadding)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2, perform: beginInlineEditing)
                                .accessibilityIdentifier("noteDetailSummaryContent")
                                .help("Double-click to edit summary")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onExitCommand {
                    if isInlineEditing {
                        finishInlineEditing()
                    }
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: isGeneratingSummary) { _, generating in
            if generating {
                inlineEditRequested = false
                inlineEditRequestCounter = 0
                isSummaryEditorFocused = false
                showRawMarkdown = false
                previousRawMarkdownMode = false
            }
        }
        .onChange(of: isSummaryEditorFocused) { oldValue, newValue in
            endInlineEditingIfNeeded(oldValue: oldValue, newValue: newValue)
        }
        .onAppear {
            handleInlineEditRequest(inlineEditRequestCounter)
        }
        .onChange(of: inlineEditRequestCounter) { _, newValue in
            handleInlineEditRequest(newValue)
        }
    }
}
