import XCTest
@testable import jotley

final class SummaryTemplateTests: XCTestCase {
    @MainActor func testTemplatePersistenceConflictsAndDeletion() throws {
        let suite = "JotleyTemplateTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SummaryTemplateStore(defaults: defaults)
        let original = try store.save(name: "Client recap", instructions: "Include decisions and action items.")
        XCTAssertEqual(try store.resolve(original.key).prompt, original.instructions)
        XCTAssertThrowsError(try store.save(name: "CLIENT RECAP", instructions: "Different"))
        let edited = try store.save(id: original.id, name: "Client follow-up", instructions: "Only action items.", expectedRevision: original.revision)
        XCTAssertEqual(edited.key, original.key)
        XCTAssertNotEqual(edited.revision, original.revision)
        XCTAssertThrowsError(try store.save(id: original.id, name: "Stale", instructions: "Stale", expectedRevision: original.revision))
        let reopened = SummaryTemplateStore(defaults: defaults)
        XCTAssertEqual(reopened.templates, [edited])
        XCTAssertThrowsError(try reopened.delete(id: edited.id, expectedRevision: original.revision))
        try reopened.delete(id: edited.id, expectedRevision: edited.revision)
        XCTAssertThrowsError(try reopened.resolve(edited.key))
        XCTAssertEqual(reopened.title(for: edited.key), "Template unavailable")
        XCTAssertTrue(SummaryTemplateStore(defaults: defaults).templates.isEmpty)
        XCTAssertEqual(reopened.definitions.count, LocalSummaryTemplate.allCases.count)
    }

    @MainActor func testValidationUsesUTF8BudgetAndPreservesCorruptStorage() throws {
        let suite = "JotleyTemplateValidation.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SummaryTemplateStore(defaults: defaults)
        XCTAssertThrowsError(try store.save(name: " ", instructions: "Use bullets"))
        XCTAssertThrowsError(try store.save(name: "Empty", instructions: "\n"))
        XCTAssertThrowsError(try store.save(name: String(repeating: "x", count: 61), instructions: "Use bullets"))
        XCTAssertThrowsError(try store.save(name: "Too long", instructions: String(repeating: "語", count: 667)))
        XCTAssertEqual(try store.save(name: "Valid", instructions: String(repeating: "語", count: 666)).instructions.utf8.count, 1998)
        let data = Data("preserve unreadable original".utf8)
        defaults.set(data, forKey: "jotleyCustomSummaryTemplates.v1")
        let unreadable = SummaryTemplateStore(defaults: defaults)
        XCTAssertNotNil(unreadable.storageError)
        XCTAssertThrowsError(try unreadable.save(name: "New", instructions: "New"))
        XCTAssertEqual(defaults.data(forKey: "jotleyCustomSummaryTemplates.v1"), data)
    }

    func testCustomPromptSurvivesLongSourceAndDoesNotForceBuiltInFormat() async throws {
        let source = String(repeating: "Original source facts. ", count: 250)
        let definition = SummaryTemplateDefinition(key: "custom/example", title: "Actions", prompt: "Only list actions. Use the heading Next Steps.")
        let probe = TemplateInferenceProbe()
        let result = try await LocalSummary.run(source, template: definition, infer: { text, prompt, _, _ in
            await probe.record(text, prompt)
            return prompt == LocalSummary.extractionPrompt ? "Preserved fact. " : "## Next Steps\n- Review onboarding."
        }, checkpoint: { await probe.save($0) }, snapshot: { _ in })
        XCTAssertEqual(result, "## Next Steps\n- Review onboarding.")
        let captured = await probe.values()
        XCTAssertEqual(captured.filter { $0.1 == LocalSummary.extractionPrompt }.map(\.0).joined(), source)
        XCTAssertTrue(captured.last?.1.contains(definition.prompt) == true)
        XCTAssertFalse(LocalSummary.finalPrompt(definition).contains("start with \"## Summary\""))
        let savedValue = await probe.saved()
        let saved = try XCTUnwrap(savedValue)
        XCTAssertEqual(saved.templatePrompt, definition.prompt)
        let changed = SummaryTemplateDefinition(key: definition.key, title: definition.title, prompt: "Use a new format.")
        let replacement = try await LocalSummary.run(source, template: changed, infer: { _, _, _, _ in "Updated" }, resuming: saved, snapshot: { _ in })
        XCTAssertEqual(replacement, "Updated")
    }

    func testOldBuiltInCheckpointStillDecodes() throws {
        let old = Data(#"{"input":"Original","templateKey":"meetings/general","source":"Original","pass":0,"facts":[]}"#.utf8)
        let checkpoint = try JSONDecoder().decode(LocalSummaryCheckpoint.self, from: old)
        XCTAssertNil(checkpoint.templatePrompt)
        XCTAssertEqual(checkpoint.templateKey, LocalSummaryTemplate.meeting.key)
    }

    func testInstalledCustomTemplateProducesSummary() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_CUSTOM_TEMPLATE_MODEL"] == "1" else { throw XCTSkip("Real Apple model check is opt-in") }
        let locale = Locale(identifier: "en-US")
        if let reason = LocalSummary.readiness(locale: locale) { throw XCTSkip(reason) }
        let template = SummaryTemplateDefinition(key: "custom/model-check", title: "Next Steps", prompt: "Write only a Next Steps section with a short bullet for each action, including its owner and deadline when mentioned.")
        let result = try await LocalSummary.generate("Maya will review onboarding on Friday. Alex will test accessibility. The launch waits for both checks.", template: template, locale: locale) { _ in }
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Maya"))
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Friday"))
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Alex"))
        XCTAssertNil(result.range(of: #"(?im)^\s*[-*•][^\n]*Alex[^\n]*Friday"#, options: .regularExpression), "A deadline was moved to a different task")
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Next Steps"), "The custom heading was omitted")
        XCTAssertFalse(result.isEmpty)
        print("REAL CUSTOM TEMPLATE SUMMARY:\n\(result)")
    }
}

private actor TemplateInferenceProbe {
    var calls: [(String, String)] = []
    var checkpoint: LocalSummaryCheckpoint?
    func record(_ source: String, _ prompt: String) { calls.append((source, prompt)) }
    func save(_ value: LocalSummaryCheckpoint) { checkpoint = value }
    func saved() -> LocalSummaryCheckpoint? { checkpoint }
    func values() -> [(String, String)] { calls }
}
