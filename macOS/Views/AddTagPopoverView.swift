import SwiftUI
import CoreData

// MARK: - Add Tag Popover View
internal struct AddTagPopoverView: View {
    @ObservedObject var note: Note
    @Binding var showPopover: Bool
    @Binding var newTagText: String
    @Binding var currentTags: [String]
    @Binding var isEditingTags: Bool
    var saveContext: () -> Void

    @Environment(\.managedObjectContext) private var viewContext

    // Helper to get the canonical form of a tag (lowercase, alphanumeric only) for de-duplication
    private func getCanonicalTag(_ tag: String) -> String {
        return tag.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    // Helper to format a newly entered tag for display and potential storage (mirrors PersistenceController.getFormattedTag)
    private func getFormattedTagForDisplay(_ tag: String) -> String {
        let spacesToDashes = tag.replacingOccurrences(of: " ", with: "-")
        let validCharacters = CharacterSet.letters.union(CharacterSet(charactersIn: "-0123456789"))
        return spacesToDashes.components(separatedBy: validCharacters.inverted).joined()
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Add New Tag")
                .font(.headline)
                .padding(.top, 5)

            ThemedTextField(
                text: $newTagText,
                placeholder: "Enter tag name (letters, numbers, dashes)",
                font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                textColor: NSColor(Color.themeTextPrimary)
            )
            .padding(8)
            .background(Color.themeContentBackground)
            .cornerRadius(6)
            .frame(minWidth: 200)
                .onChange(of: newTagText) { _, newValue in
                    // Sanitize input live: preserve case and dashes, convert spaces, remove invalid chars
                    let formattedForDisplay = getFormattedTagForDisplay(newValue)
                    if newTagText != formattedForDisplay {
                        newTagText = formattedForDisplay
                    }
                }

            HStack(spacing: 12) {
                Button("Add Tag") {
                    let trimmedTag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let formattedTag = getFormattedTagForDisplay(trimmedTag) // Format for display/storage
                    let canonicalTag = getCanonicalTag(trimmedTag) // Use canonical for de-duplication

                    if !canonicalTag.isEmpty { // De-duplicate based on canonical form
                        // Check if we already have 10 tags
                        if note.tagSet.count >= 10 {

                        } else {
                            // Check against canonical forms of existing tags
                            let existingCanonicalTags = Set(note.tagSet.compactMap { $0.canonicalName })
                            if !existingCanonicalTags.contains(canonicalTag) {
                                // Add tag using the new Tag entity system
                                do {
                                    try note.addTagByName(formattedTag, in: viewContext)
                                    // Update currentTags binding to reflect the change
                                    currentTags = note.tagNames
                                    saveContext()
                                } catch {

                                }
                            } else {

                            }
                        }
                    }
                    newTagText = ""
                    isEditingTags = false
                    showPopover = false
                }
                .keyboardShortcut(.defaultAction) // This is now the primary action
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding([.horizontal, .bottom], 15)
        .padding(.top, 10)
        .frame(minWidth: 250, idealWidth: 280)
        .background(Color.themeContentBackground) // Consistent with other popovers
        .cornerRadius(8) // Consistent with other popovers
    }
}
