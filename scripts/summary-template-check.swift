// Real-model check: every summary template must render as a Summary card and
// visual sections with no raw Markdown. Run with scripts/check-summary-templates.sh.
import SwiftUI
import AppKit
@testable import Jotley

let meeting = """
Okay, let's get started. This is the product sync for the Jotley 2.1 launch. Maya, you had the onboarding update?
Yes. The new onboarding screens are almost done. I need two more days, so I'll finish them by Wednesday.
Great. Alex, the release checklist?
I'll review the release checklist tomorrow and send the App Store screenshots to Brad for approval by Thursday.
Sam, testing?
I'm testing live transcription on iPhone and iPad. One risk is long meetings on older iPads; summaries can take a while.
Okay, we decided to keep themes and templates in this release and move the new widgets to 2.2.
We also agreed the launch date is Friday, October 23, at 10 a.m.
Open question: should Ask AI suggestions change with each template? Nobody owns that yet.
Revenue isn't relevant since the app is free, but we expect around 2,000 downloads in the first week.
Let's meet Friday at ten to sign off. Thanks, everyone.
"""
let lecture = """
Today we're covering working memory. Working memory is the system that holds information while we use it, for a few seconds at a time.
Baddeley and Hitch proposed a model in 1974 with several parts. The phonological loop stores sounds and words. The visuospatial sketchpad holds images and locations. The central executive directs attention between them.
Capacity is limited. Miller suggested about seven items, plus or minus two, but newer research suggests closer to four chunks.
Chunking increases capacity: grouping digits like a phone number lets us remember more.
For example, remembering 1-9-8-4 as a single year is one chunk instead of four digits.
For next week, review the episodic buffer, which Baddeley added in 2000, and be ready to explain how it links working memory to long-term memory.
"""
let standUp = """
Morning standup. Priya: yesterday I finished the search filters. Today I'm fixing the iPad sidebar crash. No blockers.
Leo: yesterday I worked on the summary renderer. Today I'm adding tests for templates. I'm blocked on the new simulator image; I need Priya to share it.
Jun: yesterday I reviewed pull requests. Today I'm updating the App Store screenshots. Blocked waiting on design approval from Brad.
"""
let networking = """
Great meeting you at the developer meetup. I'm Dana, I run a small podcast studio in Austin.
We both care about privacy-first tools. You mentioned Jotley keeps transcripts on the device, which matters for our interview guests.
I can introduce you to two other podcasters who might test it. In return, you offered to share the transcript export workflow.
Let's follow up next Tuesday over email. My email is on the card I gave you.
"""
let brainstorm = """
Let's brainstorm ways to grow Jotley without paid ads. Idea one: a short tutorial series on YouTube. Idea two: partner with student organizations for lecture notes.
Idea three: a shareable summary card people can post. Idea four: integrate with Obsidian more deeply.
The students idea feels strongest because lectures are a natural fit. The share card is risky because of privacy.
We picked students and the tutorial series. Next step: Maya drafts the tutorial outline, and Sam contacts two student groups this month.
"""

let oneToOne = """
Thanks for making time, Jordan. How are things going since the onboarding redesign shipped?
Pretty well. I'd like to lead the onboarding research next quarter, and I want more time with customers.
That makes sense. My feedback is that your research summaries are strong, but share them earlier so design can react.
Good point. I'll send a short weekly digest. I also want to grow in presenting to leadership.
Let's get you the next roadmap review. Decision: you'll own onboarding research starting in January.
Next steps: you draft the research plan by November 6, and I'll set up three customer calls.
"""
let allHands = """
Good morning everyone. Big news first: Jotley 2.1 ships on Friday, October 23.
Downloads grew 18 percent last month, and the Mac app now has 4,000 weekly active users.
We decided to keep every feature free and to focus Q4 on reliability.
A question from the team: will we hire for support? Answer: yes, one role opens in November.
Next steps: each team shares Q4 goals by next Friday.
"""
let sprint = """
Sprint 14 planning. Goal: ship structured summaries for 2.1.
Committed work: the summary renderer, template prompt updates, and App Store screenshots.
Leo estimates the renderer at three days. Priya says the prompt updates are two days.
We have four engineers this sprint, but Jun is out on Thursday.
Risk: the simulator image for UI tests may not be ready.
Next step: Priya shares the simulator image today, and we demo on Friday.
"""
let kickoff = """
Welcome to the kickoff for the Jotley Windows exploration. Objective: decide by December whether a Windows version is feasible.
Scope: research only, no production code. Roles: Maya leads research, Sam evaluates speech engines, Alex owns the budget.
Milestones: engine comparison by November 15, recommendation by December 10.
Risk: on-device speech quality on Windows may not match Apple's.
Next step: Sam sends the engine shortlist by Monday.
"""
let status = """
Weekly status for the 2.1 release. Progress: the summary renderer is merged and screenshots are approved.
Blocker: TestFlight build processing was slow on Tuesday.
Metrics: 42 TestFlight testers, crash-free sessions at 99.8 percent.
Decision: we ship Mac and iPhone on the same day.
Next steps: submit for review on Monday and update the website download.
"""

func source(for template: LocalSummaryTemplate) -> String {
    switch template {
    case .lecture, .study: return lecture
    case .standUp: return standUp
    case .networking: return networking
    case .brainstorming: return brainstorm
    case .oneToOne: return oneToOne
    case .allHands: return allHands
    case .sprintPlanning: return sprint
    case .projectKickoff: return kickoff
    case .weeklyStatus: return status
    default: return meeting
    }
}

struct Result: Codable { let template: String; let seconds: Double; let markdown: String; let overview: Bool; let sections: [String]; let items: Int; let leaks: [String]; let error: String? }

@MainActor func render(_ text: String, to file: String) {
    ThemeManager.shared.setAppearanceMode(.light)
    let view = StructuredSummaryView(content: text).padding(24).frame(width: 640).background(Color.themeBackground)
    let host = NSHostingView(rootView: view)
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

@MainActor func analyze(_ markdown: String) -> (Bool, [String], Int, [String]) {
    let summary = StructuredSummary(ParsedNoteMarkdown.rendering(markdown))
    var texts: [String] = []
    for section in ([summary.overview].compactMap { $0 } + summary.sections) {
        texts += section.paragraphs.map { String($0.text.characters) }
        for item in section.items {
            texts.append(String(item.body.characters)); if let l = item.label { texts.append(String(l.characters)) }
        }
        if let t = section.title { texts.append(t) }
    }
    let placeholders = ["not discussed", "not mentioned", "not specified", "not provided", "n/a", "none mentioned", "no details"]
    var leaks = texts.filter { $0.contains("**") || $0.contains("##") || $0.contains("```") || $0.hasPrefix("#") || $0.contains("__") }
    leaks += texts.filter { text in placeholders.contains { text.lowercased().contains($0) } || StructuredSummary.isPlaceholder(text) }.map { "placeholder: " + $0 }
    leaks += markdown.components(separatedBy: "\n").filter { ["-", "*", "+"].contains($0.trimmingCharacters(in: .whitespaces)) }.map { _ in "empty list item" }
    return (summary.overview != nil, summary.sections.compactMap(\.title), summary.sections.reduce(0) { $0 + $1.items.count }, leaks)
}

@main struct Check {
    static func main() async {
        _ = await MainActor.run { NSApplication.shared }
        var results: [Result] = []
        let only = CommandLine.arguments.dropFirst().first
        for template in LocalSummaryTemplate.allCases where only == nil || template.key == only {
            let start = Date()
            do {
                let md = try await LocalSummary.generate(source(for: template), template: template, locale: Locale(identifier: "en-US")) { _ in }
                let (overview, sections, items, leaks) = await MainActor.run { analyze(md) }
                await MainActor.run { render(md, to: "render-\(template.rawValue.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "")).png") }
                results.append(Result(template: template.rawValue, seconds: Date().timeIntervalSince(start), markdown: md, overview: overview, sections: sections, items: items, leaks: leaks, error: nil))
                print("\(template.rawValue): overview=\(overview) sections=\(sections) items=\(items) leaks=\(leaks.count) \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            } catch {
                results.append(Result(template: template.rawValue, seconds: Date().timeIntervalSince(start), markdown: "", overview: false, sections: [], items: 0, leaks: [], error: "\(error)"))
                print("\(template.rawValue): ERROR \(error)")
            }
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        try! enc.encode(results).write(to: URL(fileURLWithPath: "results.json"))
        let failed = results.filter { $0.error != nil || !$0.overview || $0.sections.isEmpty || !$0.leaks.isEmpty }
        print(failed.isEmpty ? "PASS: \(results.count) templates render structured summaries." : "FAIL: \(failed.map(\.template))")
        exit(failed.isEmpty ? 0 : 1)
    }
}
