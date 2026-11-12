import SwiftUI
extension SettingsView {
    @ViewBuilder var contentView: some View {
        switch selectedSection { case .general: generalView; case .templates: SummaryTemplatesView(); case .obsidian: obsidianView; case .mcp: mcpView }
    }
}
