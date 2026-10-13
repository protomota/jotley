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
    @EnvironmentObject var persistenceController: SharedPersistenceController

    @AppStorage("showTags") var showTags: Bool = false
    @AppStorage("showLiveCaptions") var showLiveCaptions: Bool = true

    // Original properties to maintain app functionality
    @State var showActionsPopover: Bool = false
    @State var showingAskAI = false
    @State var showingTranscriptEditor = false
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
    @State var animatingSparkleRotation: Double = 0

    // Animation state for transcript loading spinner
    @State var animatingTranscriptRotation: Double = 0

    // State for toolbar button positions
    @State var hasSimulatedStoppedRecordingFlowForUITests = false

    // Timers for debounced saving
    @State var summarySaveTimer: Timer?
    @State var transcriptSaveTimer: Timer?
    // Scroll-follow state for live transcription
    @State var shouldShowScrollToLatestControl: Bool = false
    @State var detailScrollProxy: ScrollViewProxy?
    @State var detailScrollObserverToken: NSObjectProtocol?
    @State var detailScrollEndObserverToken: NSObjectProtocol?
    @State var observedDetailScrollView: NSScrollView?

    var body: some View {
        contentWithAlerts
    }
}
