import SwiftUI

extension NoteDetailPlaceholderView {

    // More menu button
    var moreMenuButton: some View {
        Button {
            showActionsPopover = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.themePrimaryAccent)
        }
        .buttonStyle(JotleyGlassButtonStyle(circular: true))
        .floatingTooltip("More Actions")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("More Actions")
        .accessibilityIdentifier("noteDetailMoreMenuButton")

    }

    @ViewBuilder
    var summarizeFloatingButton: some View {
        // Use ViewModel state so the tab reflects manual summary generation progress.
        let isGenerating = (
            viewModel.isGeneratingSummary &&
            viewModel.generatingSummaryNoteID == note.objectID
        ) ||
            note.summary?.trimmingCharacters(in: .whitespacesAndNewlines) == "Generating summary..."
        let isViewingSummary = selectedTab == DetailTab.summary.rawValue
        // Determine colors based on whether this tab is selected
        let iconColor = isViewingSummary ? Color.white : Color.themePrimaryAccent
        let trackColor = isViewingSummary ? Color.white.opacity(0.3) : Color.themePrimaryAccent.opacity(0.3)

        Button {
            // Switch to summary tab
            selectedTab = DetailTab.summary.rawValue
        } label: {
            HStack(spacing: 6) {
                if isGenerating {
                    ZStack {
                        Circle()
                            .stroke(trackColor, lineWidth: 2)
                            .frame(width: 16, height: 16)

                        Circle()
                            .trim(from: 0, to: 0.2)
                            .stroke(iconColor, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .rotationEffect(Angle(degrees: animatingSparkleRotation))
                    }
                    .onAppear {
                        animatingSparkleRotation = 0
                        withAnimation(Animation.linear(duration: TabLoadingAnimation.spinnerRotationDuration).repeatForever(autoreverses: false)) {
                            animatingSparkleRotation = 360
                        }
                    }
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconColor)
                        .onAppear {
                            animatingSparkleRotation = 0
                        }
                }

                Text("Summary")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isViewingSummary ? Color.themePrimaryAccent : Color.themePrimaryAccent.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .floatingTooltip("View Summary")
        .accessibilityIdentifier("noteDetailSummaryTab")
        .onChange(of: isGenerating) { _, newValue in
            if newValue {
                animatingSparkleRotation = 0
                withAnimation(Animation.linear(duration: TabLoadingAnimation.spinnerRotationDuration).repeatForever(autoreverses: false)) {
                    animatingSparkleRotation = 360
                }
            } else {
                animatingSparkleRotation = 0
            }
        }
    }

    func loadTemplates() {
        availableTemplates = LocalSummaryTemplate.allCases.map {
            Template(key: $0.key, title: $0.title, description: $0.prompt, category: $0.category)
        }
    }
}
