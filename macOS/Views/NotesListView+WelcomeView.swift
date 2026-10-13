import SwiftUI

    struct WelcomeView: View {
        let hasNotes: Bool
        let canCreateNewNote: Bool
        @ObservedObject var viewModel: NotesListViewModel



        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 24) {
                        Spacer()

                        // App icon or logo
                        Image(systemName: "note.text")
                            .font(.system(size: 64))
                            .foregroundColor(Color.themePrimaryAccent)
                            .padding(.bottom, 8)

                        // Welcome text
                        VStack(spacing: 8) {
                            Text(hasNotes ? "Select a note" : "Welcome to Jotley")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(Color.themeTextPrimary)

                            Text(hasNotes ? "Choose a note from the list to view or edit" : "Show up. Leave the notes to us.")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(Color.themeTextSecondary)
                        }

                        // Quick start guide - only show when no notes exist
                        if !hasNotes {
                            VStack(alignment: .leading, spacing: 16) {
                            Text("Get Started:")
                                .font(.headline)
                                .foregroundColor(Color.themeTextPrimary)

                            VStack(alignment: .leading, spacing: 12) {
                                Label {
                                    Text("Create your first note to get started")
                                        .foregroundColor(Color.themeTextSecondary)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(Color.themeTextSecondary)
                                }

                                Label {
                                    Text("Record audio with AI transcription")
                                        .foregroundColor(Color.themeTextSecondary)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(Color.themeTextSecondary)
                                }

                                Label {
                                    Text("Generate a summary from your transcript")
                                        .foregroundColor(Color.themeTextSecondary)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(Color.themeTextSecondary)
                                }
                            }
                            .font(.body)
                            }
                            .padding(.horizontal, 60)
                            .padding(.vertical, 24)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.themeAccent.opacity(0.1))
                            )
                        }

                        Button {
                            handleCreateNewNoteTapped()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(hasNotes ? "New Note" : "Create Your First Note")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.themePrimaryAccent,
                                                Color.themePrimaryAccent.opacity(0.85)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: Color.themePrimaryAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(CreateNoteButtonStyle(isPrimary: true))
                        .disabled(!canCreateNewNote)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)


                }
                .coordinateSpace(name: "welcomeViewSpace")
            }
        }

    private func handleCreateNewNoteTapped() {
        guard canCreateNewNote else { return }
        viewModel.createBlankNote()
    }
}
