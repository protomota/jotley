import SwiftUI
import CoreData
import UIKit

struct NotesListView: View {
    @Binding var navigationPath: NavigationPath
    let usesSplitView: Bool
    @Binding var showingSettings: Bool
    @Binding var selectedNoteId: UUID?
    @Binding var showingTranscriptionModal: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @EnvironmentObject var persistenceController: SharedPersistenceController
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @ObservedObject var themeManager = ThemeManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)],
        animation: .default
    )
    var notes: FetchedResults<Note>

    @State var searchText = ""
    @State var isSearchFocused = false
    @State var showingTagFilter = false
    @StateObject var filterState = FilterAndSortState()
    @State var showingFolderManagement = false
    @State var showingFolderDrawer = false
    @Binding var newTranscriptionNote: Note?
    @Environment(\.colorScheme) var colorScheme


    var body: some View {
        let isSearching = isSearchFocused || !searchText.isEmpty
        ZStack {
            VStack(spacing: 0) {
                // iPad keeps Settings in the footer, clear of system window controls.
                HStack(spacing: 12) {
                    if !isSearching && !usesIPadLayout {
                        settingsButton.transition(.opacity.combined(with: .scale))
                    }

                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color(white: 0.5))
                        LocalSearchField(text: $searchText, focused: $isSearchFocused)
                            .frame(height: 44)

                        // Clear button
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(white: 0.5))
                            }
                            .accessibilityIdentifier("clearSearchButton")
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.themeContentBackground)
                    .cornerRadius(10)

                    // Cancel button — only while searching
                    if isSearching {
                        Button("Cancel") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchText = ""
                                isSearchFocused = false
                            }
                        }
                        .foregroundColor(Color.themeActionText)
                        .accessibilityIdentifier("cancelSearchButton")
                        .transition(.opacity.combined(with: .scale))
                    }

                    // Folder drawer button
                    if !isSearching {
                        Button(action: { showingFolderDrawer = true }) {
                            Image(systemName: filterState.selectedFolder == .all ? "folder" : "folder.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Color.themePrimaryAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.themeBackground)
                                .contentShape(Rectangle())
                        }
                        .frame(width: 44, height: 44)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notesListFolderDrawerButton")
                        .transition(.opacity.combined(with: .scale))
                    }

                    // Filter & sort button
                    if !isSearching {
                        Button(action: { showingTagFilter = true }) {
                            Image(systemName: filterState.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Color.themePrimaryAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.themeBackground)
                                .contentShape(Rectangle())
                        }
                        .frame(width: 44, height: 44)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filter and sort notes")
                        .accessibilityIdentifier("notesListTagFilterButton")
                        .transition(.opacity.combined(with: .scale))
                        .sheet(isPresented: $showingTagFilter) {
                            FilterAndSortPopoverView(
                                state: filterState,
                                allTags: getAllUniqueTags(),
                                tagCounts: getTagCountsForVisibleResults(),
                                onDone: { showingTagFilter = false }
                            )
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                            .presentationBackground(Color.themeContentBackground)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isSearching)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .padding(.horizontal, 16)
                .background(Color.themeBackground)
                // Keep the iPhone gear shadow above the list's opaque scroll surface.
                .zIndex(usesIPadLayout ? 0 : 1)

                // Combined folder + tag scope indicator (single scrollable row,
                // folder pill first when present, then one pill per selected tag).
                if filterState.selectedFolder != .all || !filterState.selectedTags.isEmpty {
                    iOSCurrentScopeIndicator(
                        filterState: filterState,
                        onFolderTap: { showingFolderDrawer = true },
                        onTagTap: { showingTagFilter = true }
                    )
                    .padding(.bottom, 8)
                    .background(Color.themeBackground)
                }

                List {
                    // Title (scrolls with list)
                    Section {
                        Text("Notes")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Color.themeTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                            .accessibilityIdentifier("notesListTitle")
                    }
                    .listRowBackground(Color.themeBackground)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    if transcriptionManager.transcriptionState != .idle {
                        Section {
                            Button {
                                showingTranscriptionModal = true
                            } label: {
                                ActiveTranscriptionJumpRowView(
                                    recorder: transcriptionManager
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("activeRecordingJumpRow")
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                    }

                    switch currentEmptyState {
                    case .noSearchResults:
                        Section {
                            ContentUnavailableView {
                                Label("No Results for \"\(searchText)\"", systemImage: "magnifyingglass")
                            } description: {
                                Text("Try searching with different keywords")
                            }
                            .foregroundColor(Color.themeTextPrimary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 36)
                        }
                        .listRowBackground(Color.themeBackground)
                        .listRowSeparator(.hidden)
                    case .noNotesYet:
                        Section {
                            iOSNotesListEmptyStateView()
                        }
                        .listRowBackground(Color.themeBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    case .noNotesInFolder:
                        Section {
                            iOSNoNotesInFolderView()
                        }
                        .listRowBackground(Color.themeBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    case .filtersHidingNotes:
                        Section {
                            iOSFiltersHidingNotesView(filterState: filterState)
                        }
                        .listRowBackground(Color.themeBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    case .none:
                        ForEach(groupedItems, id: \.0) { date, itemsInGroup in
                        Section {
                            if usesInlineDateHeaders {
                                dateSectionHeader(date)
                                    .listRowBackground(Color.themeBackground)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                            }
                            ForEach(itemsInGroup) { item in
                                switch item {
                                case .note(let note):
                                    let rowIsSelected = usesSplitView && note.id != nil && selectedNoteId == note.id
                                    Button {
                                        // A note synced from another device (or a legacy note) can
                                        // arrive without an `id`. Guaranteeing one here is what makes
                                        // the row openable — the old `if let note.id` silently dropped
                                        // the tap, so the note looked unselectable.
                                        let noteId = ensureStableNoteID(for: note)
                                        selectedNoteId = noteId

                                        // Use the container’s mode: the sidebar can report a
                                        // compact size class even while the app is split.
                                        if !usesSplitView {
                                            navigationPath.append(noteId)
                                        }
                                    } label: {
                                        NoteRowView(note: note, isSelected: rowIsSelected)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(rowIsSelected ? .isSelected : [])
                                    .accessibilityIdentifier("notesListNoteRow-\(note.id?.uuidString ?? "unknown")")
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            if let index = itemsInGroup.firstIndex(of: item) {
                                                deleteItemsInGroup(at: IndexSet(integer: index), from: itemsInGroup)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }


                                }
                            }
                        } header: {
                            if !usesInlineDateHeaders {
                                dateSectionHeader(date)
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.themeBackground)
            .navigationBarHidden(!usesIPadLayout)
            .navigationBarTitleDisplayMode(.inline)
            } // End of VStack

            // Floating bottom controls
            VStack {
                Spacer()
                HStack(alignment: .center) {
                    if usesIPadLayout {
                        settingsButton.padding(.leading, 20).padding(.bottom, 8)
                    }
                    Spacer()
                    Button(action: {
                        handleCreateNewNoteTapped()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.themePrimaryAccent)
                                .frame(width: 56, height: 56)

                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .accessibilityIdentifier("notesListNewNoteButton")
                    .accessibilityLabel("New live transcription")
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .sheet(isPresented: $showingFolderManagement) {
            FolderManagementSheet()
        }
        .sheet(isPresented: $showingFolderDrawer) {
            iOSFolderDrawer(filterState: filterState, showingFolderManagement: $showingFolderManagement,
                            onDone: { showingFolderDrawer = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.themeBackground)
        }
        .observeThemeChanges()
        .tint(.themeActionText)
    }
    // UIKit's pinned List section-header material can remain over earlier rows
    // in Designed for iPad on Mac. Plain date rows avoid that material layer;
    // keep native sticky headers on iPhone and iPad.
    private var usesInlineDateHeaders: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["JOTLEY_TEST_INLINE_NOTE_HEADERS"] == "1" { return true }
        #endif
        return ProcessInfo.processInfo.isiOSAppOnMac
    }

    private func dateSectionHeader(_ date: Date) -> some View {
        HStack {
            Text(formatDateSectionHeader(date))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Color(white: 0.5))
                .textCase(nil)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.themeBackground)
        .listRowInsets(EdgeInsets())
    }

    // Hardware idiom is intentional: a narrow iPad window still has window
    // controls, even when its horizontal size class becomes compact.
    private var usesIPadLayout: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var settingsButton: some View {
        Button(action: { showingSettings = true }) {
            ZStack {
                Circle().fill(Color.themePrimaryAccent).frame(width: 44, height: 44)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: usesIPadLayout ? 56 : 44, height: usesIPadLayout ? 56 : 44)
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("notesListSettingsButton")
    }

    func ensureStableNoteID(for note: Note) -> UUID {
        if let id = note.id { return id }
        let id = UUID(); note.id = id; transcriptionManager.saveEdits(); return id
    }
}


private struct LocalSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    final class Field: UITextField {
        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width, height: max(44, size.height))
        }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var owner: LocalSearchField
        init(_ owner: LocalSearchField) { self.owner = owner }
        @objc func changed(_ field: UITextField) { owner.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ field: UITextField) { if !owner.focused { owner.focused = true } }
        func textFieldDidEndEditing(_ field: UITextField) { if owner.focused { owner.focused = false } }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder(); return true }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.placeholder = "Search notes"
        field.accessibilityIdentifier = "notesListSearchField"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.owner = self
        if field.text != text { field.text = text }
        field.textColor = UIColor(Color.themeTextPrimary)
        if !focused && field.isFirstResponder { field.resignFirstResponder() }
    }
}
