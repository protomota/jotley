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
    @State private var renderedSummaryHeight: CGFloat = ContentLayoutConstants.standardMinHeight
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

    // Render markdown as one styled attributed text block so macOS selection can span the entire summary.
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

    private var effectiveLoadingStartedAt: Date? {
        if isGeneratingSummary {
            return summaryLoadingStartedAt
        }
        return summaryLoadingStartedAt
    }

    private var renderedSummary: NSAttributedString {
        // Memoize. Parsing markdown into an NSAttributedString plus the inline/block
        // regex styling passes is expensive, and this property was recomputed on EVERY
        // SwiftUI body evaluation (scroll, hover, theme, selection) — the summary
        // main-thread hangs (JOTLEY-MACOS-16/17/19). Key by the inputs that determine
        // the output so an unchanged re-render is a dictionary lookup, and return a
        // stable instance so the text view's updateNSView can skip re-typesetting too.
        let cacheKey = "\(isGeneratingSummary)|\(Color.shouldUseDarkTheme())|\(themeManager.currentThemeColor.rawValue)|\(summaryTextToRender)" as NSString
        if let cached = Self.renderedSummaryCache.object(forKey: cacheKey) {
            return cached
        }

        let sanitizedSummary = sanitizeMarkdownForRendering(summaryTextToRender)
        let data = Data(sanitizedSummary.utf8)
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textColor = NSColor(Color.themeTextPrimary)

        let parsedBase = (try? NSAttributedString(
            markdown: data,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
            baseURL: nil
        )) ?? NSAttributedString(string: sanitizedSummary)

        let styled = NSMutableAttributedString(attributedString: parsedBase)
        let fullRange = NSRange(location: 0, length: styled.length)
        styled.addAttributes(
            [
                .font: bodyFont,
                .foregroundColor: textColor
            ],
            range: fullRange
        )

        applyInlineMarkdownStyles(to: styled, baseFont: bodyFont)
        // Skip expensive regex-based block styling during streaming for smooth animation;
        // full styling applies automatically once streaming completes.
        if !isGeneratingSummary {
            applyBlockMarkdownStyles(to: styled, bodyFont: bodyFont, textColor: textColor)
        }
        applyParagraphSpacing(to: styled)

        let result = NSAttributedString(attributedString: styled)
        Self.renderedSummaryCache.setObject(result, forKey: cacheKey)
        return result
    }

    /// Cache of rendered summary attributed strings, keyed by the inputs that determine
    /// the output. Bounded so it can't grow without limit as content streams in.
    private static let renderedSummaryCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 50
        return cache
    }()

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
                // Use same component as TranscriptTabView for consistent vertical alignment
                TranscriptLoadingView(
                    message: "Generating Summary...",
                    detailMessage: "You'll be notified when the summary is ready. Longer recordings can take a few minutes.",
                    startedAt: effectiveLoadingStartedAt,
                    timeoutInterval: streamingSummaryViewModel.streamInactivityTimeoutInterval
                )
                    .accessibilityIdentifier("noteDetailSummaryLoading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            VStack(alignment: .leading, spacing: 2) {
                                SelectableSummaryTextView(
                                    attributedString: renderedSummary,
                                    accentColor: NSColor(themeManager.currentThemeColor.color),
                                    textColor: NSColor(Color.themeTextPrimary),
                                    measuredHeight: $renderedSummaryHeight,
                                    onDoubleClick: beginInlineEditing
                                )
                                .padding(compactContentPadding)
                                .frame(maxWidth: .infinity, minHeight: renderedSummaryHeight, alignment: .topLeading)
                                .accessibilityIdentifier("noteDetailSummaryContent")
                                .help("Double-click to edit summary")

                            }
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
