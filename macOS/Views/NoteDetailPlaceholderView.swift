import SwiftUI
import CoreData // For Note, NSManagedObjectID
import AppKit // For NSImage, NSSavePanel
import UniformTypeIdentifiers // For UTType in export

// This file now serves as the entry point for the view
// Split the view into smaller parts to reduce complexity
struct NoteDetailPlaceholderView: View {
    // Keep the Note as ObservedObject to track its changes
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var note: Note
    @Environment(\.managedObjectContext) var viewContext
    var isGeneratingThisSummary: Bool { viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID }
    @AppStorage(kJotleyObsidianSyncFolderBookmarkDefaultsKey) var obsidianSyncFolderBookmarkData: Data?
    @AppStorage("preferCleanedTranscript") var preferCleanedTranscript: Bool = false // Make transcript view preference persistent
    @Binding var selectedTab: Int // Raw value of DetailTab
    @ObservedObject var viewModel: NotesListViewModel
    var showNotesAction: (() -> Void)? = nil
    @EnvironmentObject var persistenceController: SharedPersistenceController

    @AppStorage("showTags") var showTags: Bool = false

    // Original properties to maintain app functionality
    @Namespace var transcriptionFooterNamespace
    @State var transcriptFollow = MacTranscriptFollowState()
    @State var showActionsPopover: Bool = false
    @State var showingAskAI = false
    @State var isEditingTranscript = false
    @State var showObsidianSaveAlert = false
    @State var obsidianAlertTitle = ""
    @State var obsidianAlertMessage = ""
    @State var manualTitle: String = ""
    @State var summaryGenerationError: String? = nil

    // New state for template selection
    @State var availableTemplates: [Template] = []

    // New state to hold the template key selected from the popover
    @State var selectedTemplateKeyForAction: String = "default-summary" // Default to auto/default
    // Track the currently selected template for display
    @State var currentSelectedTemplate: Template? = nil

    // New state variables for editable summary and transcript
    @State var editableSummary: String = ""
    @FocusState var isSummaryEditorFocused: Bool
    @State var summaryInlineEditRequestCounter: Int = 0
    @State var editableTranscript: String = ""
    @FocusState var isTranscriptEditorFocused: Bool
    // Tracks which note `editableTranscript` currently reflects. Used to tell a
    // genuine note switch apart from a loading placeholder resurfacing over a
    // real transcript on the SAME note (a CloudKit store-trump merge echo), so
    // the resurface guard never copies one note's transcript onto another.
    @State var editableTranscriptNoteID: NSManagedObjectID? = nil

    // State for Tags
    @State var currentTags: [String] = []
    @State var isEditingTags: Bool = false
    @State var isTagsExpanded: Bool = false
    @State var newTagText: String = ""
    @State var showAddTagPopover: Bool = false

    // Add a refresh ID to force view updates when needed
    @State var viewRefreshID = UUID()

    // State for Markdown view mode
    @State var showRawMarkdown: Bool = false
    // Per-tab markdown/rendered state
    @State var showRawMarkdownSummary: Bool = false // Default: Rendered

    // Animation state for sparkle spinner

    // Animation state for transcript loading spinner

    // State for toolbar button positions
    @State var hasSimulatedStoppedRecordingFlowForUITests = false

    // Timers for debounced saving
    @State var summarySaveTimer: Timer?
    @State var transcriptSaveTimer: Timer?
    var body: some View {
        contentWithAlerts
    }

    var noteSwipesEnabled: Bool {
        !isEditingTranscript && !isTranscriptEditorFocused && !isSummaryEditorFocused &&
        !showRawMarkdownSummary && !showActionsPopover && !showingAskAI && !isEditingTags && !showAddTagPopover
    }
    func navigateNoteSwipe(_ direction: NoteContentSwipeDirection) {
        switch direction {
        case .right:
            if selectedTab == DetailTab.transcript.rawValue,
               note.hasMeaningfulSummaryText || isGeneratingThisSummary {
                selectedTab = DetailTab.summary.rawValue
            } else { showNotesAction?() }
        case .left:
            if selectedTab == DetailTab.summary.rawValue, hasContentToSummarize || isRecordingThisNote {
                selectedTab = DetailTab.transcript.rawValue
            }
        }
    }
}
