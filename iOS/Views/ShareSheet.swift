import SwiftUI
import UIKit
import CoreData

struct LocalSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Retains the original local file export formats used by the note share menu.
@MainActor enum LocalNoteExport {
    enum Format { case plainText, markdown, summary, transcript }
    /// Call once at launch, before any share sheet can own a temporary export.
    /// Completed user exports live outside this temporary namespace.
    static func cleanupStaleExports(temporaryRoot: URL = FileManager.default.temporaryDirectory) throws {
        let prefix = "JotleyExport-"
        for directory in try FileManager.default.contentsOfDirectory(at: temporaryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            guard directory.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(directory.lastPathComponent.dropFirst(prefix.count))) != nil else { continue }
            let kind = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard kind.isDirectory == true, kind.isSymbolicLink != true else { continue }
            try FileManager.default.removeItem(at: directory)
        }
    }
    static func content(note: Note, format: Format) -> String {
        let trimmedTitle = (note.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Untitled Note" : trimmedTitle
        let summary = (note.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = (note.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter(); formatter.dateStyle = .long; formatter.timeStyle = .short
        let date = note.timestamp.map { formatter.string(from: $0) }
        if format == .summary || format == .transcript {
            let section = format == .summary ? "Summary" : "Transcript"
            let body = format == .summary ? summary : transcript
            return "# \(title) - \(section)\n\n" + (date.map { "*Exported: \($0)*\n\n" } ?? "") + (body.isEmpty ? "*No \(section.lowercased()) available*\n" : "\(body)\n")
        }
        if format == .plainText {
            var output = "\(title)\n" + String(repeating: "=", count: title.count) + "\n\n"
            if let date { output += "Created: \(date)\n\n" }
            if !note.tagNames.isEmpty { output += "Tags: \(note.tagNames.joined(separator: ", "))\n\n" }
            if !summary.isEmpty { output += "SUMMARY\n-------\n\(summary)\n\n" }
            if !transcript.isEmpty { output += "TRANSCRIPT\n----------\n\(transcript)\n" }
            return output
        }
        var output = "# \(title)\n\n"
        if let date { output += "*Created: \(date)*\n\n" }
        if !note.tagNames.isEmpty { output += "**Tags:** \(note.tagNames.map { "#\($0)" }.joined(separator: " "))\n\n" }
        if !summary.isEmpty { output += "## Summary\n\n\(summary)\n\n" }
        if !transcript.isEmpty { output += "## Transcript\n\n\(transcript)\n" }
        return output
    }
    static func file(note: Note, format: Format, temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let suffix = format == .summary ? " - Summary" : format == .transcript ? " - Transcript" : ""
        let url = try exportURL(note: note, suffix: suffix, extension: format == .plainText ? "txt" : "md", temporaryRoot: temporaryRoot)
        do { try content(note: note, format: format).write(to: url, atomically: true, encoding: .utf8); return url }
        catch { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); throw error }
    }
    /// The summary rendered in Jotley's structured layout, ready to share.
    static func summaryPDF(note: Note, temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let url = try exportURL(note: note, suffix: " - Summary", extension: "pdf", temporaryRoot: temporaryRoot)
        let title = (note.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do { try SummaryPDF.write(title: title.isEmpty ? "Untitled Note" : title, date: note.timestamp, markdown: note.summary ?? "", to: url); return url }
        catch { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); throw error }
    }
    private static func exportURL(note: Note, suffix: String, extension ext: String, temporaryRoot: URL) throws -> URL {
        guard note.managedObjectContext != nil, !note.isDeleted else { throw LocalError.message("This note is unavailable.") }
        let title = (note.title ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.controlCharacters)
        // Keep names bounded while preserving Unicode; a unique directory avoids collisions.
        var safe = ""; var bytes = 0
        for scalar in title.components(separatedBy: invalid).joined(separator: "-").unicodeScalars {
            let size = String(scalar).utf8.count
            if bytes + size > 160 { break }
            safe.unicodeScalars.append(scalar); bytes += size
        }
        let name = safe.isEmpty || safe == "." || safe == ".." ? "Untitled" : safe
        let directory = temporaryRoot.appendingPathComponent("JotleyExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name + suffix + "." + ext)
    }
}

/// A SwiftUI wrapper for UIActivityViewController to present the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
