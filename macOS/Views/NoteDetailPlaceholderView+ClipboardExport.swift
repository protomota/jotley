import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension NoteDetailPlaceholderView {
    // Helper function to copy content based on current tab
    func copyCurrentTabContent() {
        let contentToCopy: String
        switch DetailTab(rawValue: selectedTab) {
        case .summary: contentToCopy = note.summary ?? ""
        case .transcript: contentToCopy = editableTranscript
        case .none: contentToCopy = ""
        }
        if !contentToCopy.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(contentToCopy, forType: .string)
        }
    }

    // MARK: - Export Functions

    func exportAsMarkdown() {
        let content = generateMarkdownContent()
        saveExportFile(content: content, extension: "md")
    }

    func exportAsPlainText() {
        let content = generatePlainTextContent()
        saveExportFile(content: content, extension: "txt")
    }

    func exportSummary() {
        let content = generateSectionContent(section: "Summary", text: note.summary)
        saveExportFile(content: content, extension: "md", filenameSuffix: " - Summary")
    }

    /// Saves the summary in Jotley's structured layout as a PDF.
    func exportSummaryPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(safeFilename) - Summary.pdf"
        savePanel.title = "Export Summary as PDF"
        savePanel.canCreateDirectories = true
        let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let date = note.timestamp, markdown = note.summary ?? ""
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do { try SummaryPDF.write(title: title.isEmpty ? "Untitled Note" : title, date: date, markdown: markdown, to: url) }
            catch {
                obsidianAlertTitle = "Export Failed"
                obsidianAlertMessage = "The PDF could not be created: \(error.localizedDescription). Your note remains saved in Jotley."
                showObsidianSaveAlert = true
            }
        }
    }

    func exportTranscript() {
        let content = generateSectionContent(section: "Transcript", text: note.transcription)
        saveExportFile(content: content, extension: "md", filenameSuffix: " - Transcript")
    }

    private func generateSectionContent(section: String, text: String?) -> String {
        var content = ""

        // Title
        let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Note"
        content += "# \(title) - \(section)\n\n"

        // Metadata
        if let timestamp = note.timestamp {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            content += "*Exported: \(formatter.string(from: timestamp))*\n\n"
        }

        // Section content
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            content += "\(text)\n"
        } else {
            content += "*No \(section.lowercased()) available*\n"
        }

        return content
    }

    private var safeFilename: String {
        let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
        // Remove characters that are invalid in filenames
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return title.components(separatedBy: invalidChars).joined(separator: "-")
    }

    private func generateMarkdownContent() -> String {
        var content = ""

        // Title
        let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Note"
        content += "# \(title)\n\n"

        // Metadata
        if let timestamp = note.timestamp {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            content += "*Created: \(formatter.string(from: timestamp))*\n\n"
        }

        // Tags
        let tags = note.tagNames
        if !tags.isEmpty {
            content += "**Tags:** \(tags.map { "#\($0)" }.joined(separator: " "))\n\n"
        }

        // Summary
        if let summary = note.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            content += "## Summary\n\n\(summary)\n\n"
        }

        // Transcript
        if let transcription = note.transcription?.trimmingCharacters(in: .whitespacesAndNewlines), !transcription.isEmpty {
            content += "## Transcript\n\n\(transcription)\n"
        }

        return content
    }

    private func generatePlainTextContent() -> String {
        var content = ""

        // Title
        let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Note"
        content += "\(title)\n"
        content += String(repeating: "=", count: title.count) + "\n\n"

        // Metadata
        if let timestamp = note.timestamp {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            content += "Created: \(formatter.string(from: timestamp))\n\n"
        }

        // Tags
        let tags = note.tagNames
        if !tags.isEmpty {
            content += "Tags: \(tags.joined(separator: ", "))\n\n"
        }

        // Summary
        if let summary = note.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            content += "SUMMARY\n-------\n\(summary)\n\n"
        }

        // Transcript
        if let transcription = note.transcription?.trimmingCharacters(in: .whitespacesAndNewlines), !transcription.isEmpty {
            content += "TRANSCRIPT\n----------\n\(transcription)\n"
        }

        return content
    }

    private func saveExportFile(content: String, extension fileExtension: String, filenameSuffix: String = "") {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = fileExtension == "md" ? [.init(filenameExtension: "md")!] : [.plainText]
        savePanel.nameFieldStringValue = "\(safeFilename)\(filenameSuffix).\(fileExtension)"
        savePanel.title = "Export Note"
        savePanel.message = "Choose where to save your note"
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    obsidianAlertTitle = "Export Failed"
                    obsidianAlertMessage = "The note could not be exported: \(error.localizedDescription). Your note remains saved in Jotley."
                    showObsidianSaveAlert = true
                }
            }
        }
    }

}
