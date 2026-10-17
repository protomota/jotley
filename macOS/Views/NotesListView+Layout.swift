import SwiftUI

extension NotesListView {
    var navigationView: some View {
        NavigationSplitView {
            mainContent
                .frame(minWidth: 280)
                .background(Color.themeContentBackground.ignoresSafeArea())
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.themeTextSecondary.opacity(0.3))
                        .frame(width: 1)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } detail: {
            detailContent
                .background(Color.themeContentBackground.ignoresSafeArea())
                .frame(maxWidth: .infinity)
        }
        .navigationSplitViewStyle(.automatic)
        .background(Color.themeContentBackground)
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
            // Search field at the top of the sidebar
            HStack(spacing: 8) {
                ThemedTextField(
                    text: $searchText,
                    placeholder: "Search..",
                    font: NSFont.systemFont(ofSize: 14),
                    textColor: NSColor(Color.themeTextPrimary),
                    minimumHeight: 36
                )
                .frame(height: 36)
                .accessibilityIdentifier("notesListSearchField")
                    .padding(.horizontal, 8)
                    .padding(.leading, 24)
                    .padding(.trailing, 24)
                    .background(Color.themeAccent.opacity(0.5))
                    .cornerRadius(8)
                    .foregroundColor(Color.themeTextPrimary)
                    .overlay(alignment: .leading) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(Color.themeTextSecondary)
                            .padding(.leading, 10)
                    }
                    .overlay(alignment: .trailing) {
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.themeTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                            .accessibilityIdentifier("clearSearchButton")
                        }
                    }

                // Filter & sort button and anchored dropdown
                Button(action: {
                    showingTagFilter.toggle()
                }) {
                    Image(systemName: filterState.hasTagFilter || filterState.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18))
                        .foregroundColor(filterState.isActive ? Color.themePrimaryAccent : Color.themeTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Color.themeAccent.opacity(0.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Filter & sort")
                .accessibilityAddTraits(.isButton)
                .help("Filter & sort")
                .accessibilityIdentifier("notesListTagFilterButton")
            }
            .padding(.leading, 12)
            // Match the native sidebar toggle's trailing inset.
            .padding(.trailing, 8)
            .padding(.top, 0)
            .padding(.bottom, 8)

            folderSidebarSection()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if let recordingNote = activeRecordingNote {
                activeRecordingBanner(for: recordingNote)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            switch currentEmptyState {
            case .noSearchResults:
                ContentUnavailableView {
                    Label {
                        Text("No Results for \"\(searchText)\"")
                            .foregroundColor(Color.themeTextPrimary)
                    } icon: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color.themePrimaryAccent)
                    }
                } description: {
                    Text("Try searching with different keywords")
                        .foregroundColor(Color.themeTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.themeContentBackground.ignoresSafeArea())
                .accessibilityIdentifier("notesListNoSearchResults")
            case .noNotesYet:
                ContentUnavailableView {
                    Label {
                        Text("No Notes Yet")
                            .foregroundColor(Color.themeTextPrimary)
                    } icon: {
                        Image(systemName: "note.text")
                            .foregroundColor(Color.themePrimaryAccent)
                    }
                } description: {
                    Text("Use Create Your First Note to start your first note.")
                        .foregroundColor(Color.themeTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.themeContentBackground.ignoresSafeArea())
                .accessibilityIdentifier("notesListNoNotesYet")
            case .noNotesInFolder:
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 22))
                        .foregroundColor(Color.themePrimaryAccent)
                    Text("No notes in this folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.themeTextPrimary)
                    Text("Create a note here, or pick another folder from the sidebar.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.themeTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.themeContentBackground.ignoresSafeArea())
                .accessibilityIdentifier("notesListNoNotesInFolder")
            case .filtersHidingNotes:
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22))
                        .foregroundColor(Color.themePrimaryAccent)
                    Text("Filters are hiding notes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.themeTextPrimary)
                    Text("Your current filters match no notes in this view.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.themeTextSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        filterState.clearAll()
                    } label: {
                        Text("Clear Filters")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.themePrimaryAccent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notesListClearFiltersButton")
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.themeContentBackground.ignoresSafeArea())
                .accessibilityIdentifier("notesListFiltersHidingNotes")
            case .none:
                noteList()
            }

            }

        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .center) {
                Button { showingSettingsSheet = true } label: {
                    ZStack {
                        Circle().fill(Color.themePrimaryAccent).frame(width: 36, height: 36)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("notesListSettingsButton")
                Spacer()
                Button { Task { await viewModel.startNewNote() } } label: {
                    ZStack {
                        Circle().fill(Color.themePrimaryAccent).frame(width: 48, height: 48)
                        Image(systemName: "plus")
                            .font(.system(size: 25, weight: .semibold)).foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canCreateNewNote)
                .help("New Transcription")
                .accessibilityLabel("New Transcription")
                .accessibilityIdentifier("notesListNewNoteButton")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .overlay {
            ZStack(alignment: .top) {
                if showingTagFilter {
                    Color.black.opacity(0.25)
                        .onTapGesture {
                            showingTagFilter = false
                        }
                        .transition(.opacity)

                    FilterAndSortPopoverView(
                        state: filterState,
                        allTags: getAllUniqueTags(),
                        tagCounts: getTagCountsForVisibleResults(),
                        onDone: { showingTagFilter = false }
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
                    .padding(.top, 36)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showingTagFilter)
            .allowsHitTesting(showingTagFilter)
        }
    }

    @ViewBuilder
    private func noteList() -> some View {
        // Snapshot the (expensive, recomputed) grouped list ONCE per body pass,
        // and pre-compute cumulative row offsets per group. Without these locals
        // the inner ForEach was rebuilding the Dictionary grouping and running
        // an O(n) prefix/map/reduce per row, making list rendering O(n²) and
        // tripping App Hanging alerts on lists with hundreds of notes.
        let groups = groupedNotes
        let enumeratedGroups = Array(groups.enumerated())
        let groupRowOffsets: [Int] = {
            var offsets: [Int] = []
            offsets.reserveCapacity(groups.count)
            var running = 0
            for g in groups {
                offsets.append(running)
                running += g.1.count
            }
            return offsets
        }()

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                ForEach(enumeratedGroups, id: \.element.0) { group in
                    let groupIndex = group.offset
                    let date = group.element.0
                    let notesInGroup = group.element.1
                    let enumeratedNotes = Array(notesInGroup.enumerated())

                    Section {
                        ForEach(enumeratedNotes, id: \.element.objectID) { noteItem in
                            let noteIndex = noteItem.offset
                            let currentNote = noteItem.element

                            // Break into simpler expressions to fix compiler type-checking
                            let isRowSelected = viewModel.selectedNoteIDs.contains(currentNote.objectID)
                            let topPadding = groupIndex == 0 && noteIndex == 0 ? 15.0 : 0.0
                            let globalRowIndex = groupRowOffsets[groupIndex] + noteIndex
                            let isRecordingNote = viewModel.activeRecordingNote?.objectID == currentNote.objectID

                            NoteRowView(
                                note: currentNote,
                                isSelected: isRowSelected,
                                toggleSelection: { note, isCommandPressed in
                                    viewModel.toggleSelection(for: note, isCommandKeyPressed: isCommandPressed)
                                },
                                prepareDelete: viewModel.performContextualDelete,
                                topPadding: topPadding,
                                rowIndex: globalRowIndex,
                                isRecordingNote: isRecordingNote
                            )
                            // Add swipe to delete on Mac
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteNotes(inGroup: notesInGroup, atOffsets: IndexSet([noteIndex]))
                                    }
                                }
                                label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.themePrimaryAccent)
                            }
                        }
                    } header: {
                        if let headerText = formatDateSectionHeader(for: date) {
                            Text(headerText)
                                .font(.headline)
                                .fontWeight(.bold)
                                .padding(.vertical, 6)
                                .padding(.leading, 16)
                                .padding(.trailing, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.themeContentBackground)
                                .foregroundColor(.secondary)
                        } else {
                            EmptyView()
                        }
                    }
                }

                // Tappable empty space below the last row so users can always
                // click-away to clear a stuck selection.
                Color.themeContentBackground
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.clearSelection()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Color.themeContentBackground
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.clearSelection()
                }
        )
    }

    private func formatDateSectionHeader(for date: Date) -> String? {
        // Sentinel used by non-date sort modes to collapse everything into a single unlabeled group.
        if date == .distantFuture { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "E, MMM d" // "Tue, Jan 23"
            return dateFormatter.string(from: date)
        }
    }

    // MARK: - Folder Sidebar Section

    @ViewBuilder
    func folderSidebarSection() -> some View {
        FolderSidebarView(
            filterState: filterState,
            isExpanded: $foldersExpanded,
            showingFolderManagement: $showingFolderManagement
        )
        .sheet(isPresented: $showingFolderManagement) {
            FolderManagementSheet()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    @ViewBuilder
    private func activeRecordingBanner(for note: Note) -> some View {
        let isSelected = viewModel.selectedNoteIDs.contains(note.objectID)

        Button {
            viewModel.jumpToActiveRecordingNote()
        } label: {
            HStack(spacing: 10) {
                ActiveRecordingIcon()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcription in progress")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.themeTextPrimary)
                    Text(isSelected ? note.titleOrUntitled : "Click to jump back")
                        .font(.system(size: 11))
                        .foregroundColor(Color.themeTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !isSelected {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.themePrimaryAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.themePrimaryAccent.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.themePrimaryAccent.opacity(0.38), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Transcription is active on this note" : "Jump back to active transcription")
        .accessibilityIdentifier("activeRecordingJumpBanner")
    }

    private struct ActiveRecordingIcon: View {
        @ObservedObject private var themeManager = ThemeManager.shared
        @State private var isPulsing = false
        @State private var themeUpdateId = UUID()

        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.themePrimaryAccent.opacity(0.35))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.6)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isPulsing ? 1.7 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.95)

                Circle()
                    .stroke(Color.themePrimaryAccent.opacity(0.95), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isPulsing ? 1.95 : 1.05)
                    .opacity(isPulsing ? 0.0 : 0.55)

                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
            }
            .id(themeUpdateId)
            .shadow(color: Color.themePrimaryAccent.opacity(0.75), radius: 8, x: 0, y: 0)
            .onAppear {
                isPulsing = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
            .onChange(of: themeManager.currentThemeColor) { _, _ in
                // Recreate the animated icon so the pulsing layers immediately adopt the new accent.
                themeUpdateId = UUID()
            }
            .onDisappear {
                isPulsing = false
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selectedID = viewModel.selectedNoteIDs.first,
           let selectedNote = notes.first(where: { $0.objectID == selectedID }) {
            NoteDetailPlaceholderView(note: selectedNote, selectedTab: $viewModel.selectedDetailTab, viewModel: viewModel)
                .id(selectedNote.objectID)
                .onAppear {
                }
                .onDisappear {
                }
                .frame(minWidth: 340)
                .background(Color.themeContentBackground.ignoresSafeArea())
                .accessibilityIdentifier("noteDetailContainer")
        } else {
            // Show welcome view for both empty and no selection states
            WelcomeView(
                hasNotes: !notes.isEmpty,
                canCreateNewNote: canCreateNewNote,
                viewModel: viewModel
            )
                .onAppear {
                }
                .frame(minWidth: 340)
                .background(Color.themeContentBackground.ignoresSafeArea())
        }
    }

    // MARK: - Helper Functions
}
