import XCTest
import UIKit
#if DEBUG
import FoundationModels
import Speech
#endif

final class Jotley_iOSUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }


    @MainActor private func triggerSummaryAction(in app: XCUIApplication) {
        let firstSummary = app.buttons["noteDetailGenerateSummaryButton"]
        if firstSummary.exists && firstSummary.isHittable { firstSummary.tap() }
        else {
            app.buttons["noteDetailMoreActionsButton"].tap()
            let generate = app.buttons["noteDetailGenerateSummaryMenuButton"]
            if generate.exists { generate.tap() }
            else {
                app.buttons["noteDetailSummaryTemplateMenu"].tap()
                app.buttons["Lecture"].tap()
            }
        }
    }

    @MainActor func testTemplateChangeRegeneratesExistingSummaryAutomatically() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"[{"title":"Template update","folder":"","tags":[],"transcript":"Maya reviews milestones Friday. Sam tests the next steps.","summary":"Existing summary stays safe until its replacement finishes."}]"#
        app.launchEnvironment["JOTLEY_TEST_SUMMARY_SCROLL"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launch()
        XCTAssertTrue(app.buttons["noteDetailMoreActionsButton"].waitForExistence(timeout: 15))
        app.buttons["noteDetailMoreActionsButton"].tap()
        XCTAssertFalse(app.buttons["noteDetailGenerateSummaryMenuButton"].exists)
        app.buttons["noteDetailSummaryTemplateMenu"].tap()
        app.buttons["Lecture"].tap()
        let cancel = app.buttons["noteDetailCancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Changing a template must start generation without another button")
        cancel.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Existing summary stays safe")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["noteDetailGenerateSummaryButton"].exists)
    }

    @MainActor func testAutomaticFirstNoteSelectionAndDeletion() throws {
        let isIPad = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad")
        XCUIDevice.shared.orientation = isIPad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"[{"title":"Newest note","folder":"","tags":[],"transcript":"First note.","summary":"A useful summary."},{"title":"Older note","folder":"","tags":[],"transcript":"Second note.","summary":""},{"title":"Oldest note","folder":"","tags":[],"transcript":"Third note.","summary":""}]"#
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launch()
        let title = app.staticTexts["noteDetailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Newest note")
        let transcriptTab = app.buttons["noteDetailTranscriptTab"]
        let summaryTab = app.buttons["noteDetailSummaryTab"]
        transcriptTab.tap(); XCTAssertTrue(transcriptTab.isSelected)
        summaryTab.tap(); XCTAssertTrue(summaryTab.isSelected)
        if !isIPad { app.buttons["BackButton"].tap() }
        let older = app.buttons.containing(.staticText, identifier: "Older note").firstMatch
        XCTAssertTrue(older.waitForExistence(timeout: 5)); older.tap()
        XCTAssertEqual(title.label, "Older note")
        app.buttons["noteDetailMoreActionsButton"].tap()
        app.buttons["Delete Note"].tap()
        app.alerts["Delete Note"].buttons["Delete"].tap()
        if isIPad {
            let selectedNewest = expectation(for: NSPredicate(format: "label == %@", "Newest note"), evaluatedWith: title)
            wait(for: [selectedNewest], timeout: 10)
            XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Newest note").firstMatch.isHittable)
        } else {
            XCTAssertTrue(title.waitForNonExistence(timeout: 10), "Deleting on a single-column iPhone must return to the list, not open the newest note")
            let settings = app.buttons["notesListSettingsButton"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5)); XCTAssertTrue(settings.isHittable)
            XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Newest note").firstMatch.isHittable)
        }
        let oldest = app.buttons.containing(.staticText, identifier: "Oldest note").firstMatch
        XCTAssertTrue(oldest.waitForExistence(timeout: 5)); oldest.tap()
        XCTAssertEqual(title.label, "Oldest note", "A remaining note must still open normally")
        app.terminate(); app.launch()
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Newest note") // Initial selection is unchanged; fixtures reset on launch.
    }

    @MainActor func testSummaryStyleAppliesToEveryNoteAndPersistsInSettings() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"First summary","folder":"","tags":[],"transcript":"Maya reviews Friday.","summary":"## Summary\nA focused launch.\n\n## Next Steps\n- **Maya:** Review Friday."},{"title":"Second summary","folder":"","tags":[],"transcript":"Alex tests Monday.","summary":"## Summary\nA clear plan.\n\n## Next Steps\n- Test Monday."}]"###
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()
        func showLibrary() {
            let row = app.buttons.containing(.staticText, identifier: "Second summary").firstMatch
            if row.exists && row.isHittable { return }
            let back = app.buttons["BackButton"]
            if back.exists && back.isHittable { back.tap() }
            else {
                let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
                XCTAssertTrue(sidebar.waitForExistence(timeout: 5)); sidebar.tap()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
        }
        func openNote(_ title: String) {
            let row = app.buttons.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
            XCTAssertTrue(app.buttons["noteDetailMoreActionsButton"].waitForExistence(timeout: 5))
        }
        func changeStyle(_ title: String) {
            app.buttons["noteDetailMoreActionsButton"].tap()
            app.buttons["noteDetailSummaryStyleMenu"].tap()
            let option = app.buttons[title]
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        }
        openNote("First summary")
        changeStyle("Standard Text")
        XCTAssertTrue(app.staticTexts["summaryTextLine-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A focused launch."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Next Steps"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '**Maya**' OR label CONTAINS '## Next'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Standard Text summary Dark with neutral headings and bullets"; shot.lifetime = .keepAlways; add(shot)
        showLibrary(); openNote("Second summary")
        XCTAssertTrue(app.staticTexts["summaryTextLine-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A clear plan."].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["notesListSettingsButton"].waitForExistence(timeout: 15))
        app.buttons["notesListSettingsButton"].tap()
        let picker = app.descendants(matching: .any)["summaryDisplayStylePicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Standard Text") || (picker.value as? String)?.contains("Standard Text") == true, picker.debugDescription)
        picker.tap(); app.buttons["Cards"].tap()
        app.buttons["settingsDoneButton"].tap()
        openNote("Second summary")
        XCTAssertTrue(app.descendants(matching: .any)["structuredSummaryOverview"].firstMatch.waitForExistence(timeout: 5))
        showLibrary(); openNote("First summary")
        XCTAssertTrue(app.descendants(matching: .any)["structuredSummaryOverview"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testPhoneCornerCaptureStaysClearOfNoteActions() throws {
        guard (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPhone") else {
            throw XCTSkip("Requires iPhone")
        }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Duo interface checks","folder":"Work","tags":["Planning"],"transcript":"Maya will review the launch plan on Friday.","summary":"## Decisions\n- Review the launch plan Friday."}]"###
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            let row = app.buttons.containing(.staticText, identifier: "Duo interface checks").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["notesListNewNoteButton"].isHittable)
            let gear = app.buttons["notesListSettingsButton"]
            let folders = app.buttons["notesListFolderDrawerButton"]
            XCTAssertEqual(gear.frame.size, folders.frame.size)
            if orientation == .portrait {
                XCTAssertEqual(gear.frame.minX - app.frame.minX, 8, accuracy: 1)
            }
            gear.tap()
            XCTAssertTrue(app.buttons["settingsDoneButton"].waitForExistence(timeout: 5))
            app.buttons["settingsDoneButton"].tap()
            row.tap()
            let plus = app.buttons["notesListNewNoteButton"]
            XCTAssertTrue(plus.waitForExistence(timeout: 5)); XCTAssertTrue(plus.isHittable)
            XCTAssertEqual(app.buttons.matching(identifier: "notesListNewNoteButton").count, 1)
            XCTAssertGreaterThanOrEqual(plus.frame.width, 44)
            XCTAssertEqual(plus.frame.width, 44, accuracy: 1)
            XCTAssertGreaterThanOrEqual(app.frame.maxX - plus.frame.maxX, 0)
            for tab in ["noteDetailSummaryTab", "noteDetailTranscriptTab"] {
                app.buttons[tab].tap()
                let quickAction = app.buttons[tab == "noteDetailSummaryTab" ? "noteDetailSummaryAskAIButton" : "noteDetailContinueTranscriptionButton"]
                XCTAssertTrue(quickAction.isHittable)
                XCTAssertFalse(app.buttons["noteDetailGenerateSummaryButton"].exists)
                XCTAssertFalse(plus.frame.intersects(quickAction.frame))
                XCTAssertEqual(quickAction.frame.height, 44, accuracy: 1)
                XCTAssertEqual(plus.frame.midY, quickAction.frame.midY, accuracy: 1)
                let title = app.staticTexts["noteDetailTitle"]
                let sidebarIsBesideNote = row.isHittable && row.frame.maxX <= title.frame.minX
                let detailLeading = sidebarIsBesideNote ? title.frame.minX - 16 : app.frame.minX
                XCTAssertEqual(app.frame.maxX - plus.frame.maxX, 24, accuracy: 1)
                XCTAssertEqual(quickAction.frame.midX, (detailLeading + app.frame.maxX) / 2, accuracy: 1)
                XCTAssertTrue(app.buttons["noteDetailShareButton"].isHittable)
                XCTAssertTrue(app.buttons["noteDetailMoreActionsButton"].isHittable)
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Duo corner controls - \(orientation.rawValue)"
            attachment.lifetime = .keepAlways; add(attachment)
            plus.tap()
            let pause = app.buttons["transcriptionPauseButton"]
            XCTAssertTrue(pause.waitForExistence(timeout: 10)); XCTAssertEqual(pause.frame.height, 84, accuracy: 1); pause.tap()
            XCTAssertEqual(pause.label, "Resume transcription"); pause.tap()
            XCTAssertEqual(pause.label, "Pause transcription")
            let stop = app.buttons["transcriptionStopButton"]
            XCTAssertEqual(stop.frame.height, 60, accuracy: 1)
            let recording = XCTAttachment(screenshot: app.screenshot())
            recording.name = "Large themed Pause and larger glass Stop"; recording.lifetime = .keepAlways; add(recording)
            stop.tap()
            XCTAssertTrue(app.staticTexts["Completed transcript."].waitForExistence(timeout: 10))
            let settled = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: app.buttons["noteDetailMoreActionsButton"])
            wait(for: [settled], timeout: 5)
            app.buttons["noteDetailContinueTranscriptionButton"].tap()
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            app.buttons["transcriptionCloseButton"].tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    @MainActor func testCompactAddTagSheetSavesAndCancels() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Tag design check","folder":"Work","tags":[],"transcript":"Review Friday’s plan.","summary":""}]"###
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Tag design check").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let addButton = app.buttons["noteDetailAddTagButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5)); addButton.tap()
        let field = app.textFields["addTagTextField"]
        let save = app.buttons["addTagSaveButton"]
        let cancel = app.buttons["addTagCancelButton"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(field.frame.height, 52)
        XCTAssertTrue(save.isHittable && cancel.isHittable)
        XCTAssertFalse(save.isEnabled)
        XCTAssertGreaterThan(cancel.frame.minY, app.frame.height * 0.15, "The tag sheet must leave the note visible above it, even with the keyboard")
        field.tap(); field.typeText("Launch review")
        XCTAssertTrue(save.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Compact Add Tag with styled input and glass action"; shot.lifetime = .keepAlways; add(shot)
        // Return also submits the compact form when a hardware keyboard is
        // connected to a foldable simulator with a separate keyboard surface.
        field.typeText("\n")
        let tag = app.descendants(matching: .any)["noteDetailTag-Launch-review"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        addButton.tap(); XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Draft")
        cancel.tap()
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["noteDetailTag-Draft"].firstMatch.exists)
    }

    @MainActor func testOnboardingSwipeNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
        app.launch()
        let title = app.staticTexts["onboardingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        func expectTitle(_ text: String) {
            let match = expectation(for: NSPredicate(format: "label == %@", onboardingTitle(text, in: app)), evaluatedWith: title)
            wait(for: [match], timeout: 5)
        }
        title.swipeRight(); expectTitle("Stay in the conversation.")
        title.swipeLeft(); expectTitle("Find the useful parts.")
        title.swipeRight(); expectTitle("Stay in the conversation.")
        app.buttons["onboardingContinue"].tap(); expectTitle("Find the useful parts.")
        title.swipeLeft(); expectTitle("Start with your language.")
        title.swipeLeft(); expectTitle("Give your words a place.")
        title.swipeLeft(); expectTitle("Free software.\nSupported by people.")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Swiping must not request microphone access")
        title.swipeLeft(); expectTitle("Free software.\nSupported by people.")
        XCTAssertTrue(app.buttons["onboardingContinue"].exists, "Swiping past the end must not finish setup")
        app.buttons["onboardingBack"].tap(); expectTitle("Give your words a place.")
    }

    @MainActor private func onboardingTitle(_ text: String, in app: XCUIApplication) -> String {
        guard UIDevice.current.model.hasPrefix("iPad"), app.frame.width >= 620 else { return text }
        return switch text {
        case "Stay in the conversation.": "Stay in the\nconversation."
        case "Find the useful parts.": "Find clarity in\nevery conversation."
        case "Start with your language.": "Start with\nyour language."
        case "Give your words a place.": "Give your words\na place."
        default: text
        }
    }

    @MainActor func testOnboardingFitsWithoutScrolling() throws {
        try verifyCenteredOnboarding(orientation: .portrait)
    }

    @MainActor func testOnboardingIsCenteredInIPadLandscape() throws {
        guard (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad") else { throw XCTSkip("iPad landscape layout") }
        try verifyCenteredOnboarding(orientation: .landscapeLeft, appearance: "Dark")
    }

    @MainActor func testOnboardingDarkModeKeepsCenteredLayout() throws {
        try verifyCenteredOnboarding(orientation: .portrait, appearance: "Dark")
    }

    @MainActor private func verifyCenteredOnboarding(orientation: UIDeviceOrientation, appearance: String = "Light") throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "USA"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = appearance
        app.launch()
        XCTAssertTrue(app.staticTexts["onboardingTitle"].waitForExistence(timeout: 15))
        let initialAction = app.buttons["onboardingContinue"].frame
        let initialTitleTop = app.staticTexts["onboardingTitle"].frame.minY
        let block = app.descendants(matching: .any)["onboardingContentBlock"].firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let initialBlock = block.frame
        if UIDevice.current.model.hasPrefix("iPad") {
            let skip = app.buttons["onboardingSkip"].frame
            let brand = app.staticTexts["onboardingBrand"].frame
            XCTAssertLessThan(brand.minX, 100, "Brand belongs at the window's top-left corner")
            XCTAssertLessThan(app.frame.maxX - skip.maxX, 60, "Skip setup belongs at the window's top-right corner")
            if app.frame.width >= 1000 {
                XCTAssertGreaterThan(initialBlock.width, 800, "Roomy iPad windows should enlarge the whole content area")
                XCTAssertGreaterThan(app.staticTexts["onboardingTitle"].frame.height, 40)
            }
        }
        var tallestPageHeight: CGFloat = 0
        let titles = ["Stay in the conversation.", "Find the useful parts.", "Start with your language.", "Give your words a place.", "Free software.\nSupported by people."]
            .map { onboardingTitle($0, in: app) }
        for index in 0..<5 {
            let titleMatches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", titles[index]), object: app.staticTexts["onboardingTitle"])
            XCTAssertEqual(XCTWaiter.wait(for: [titleMatches], timeout: 15), .completed)
            if index == 2 {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["onboardingLanguagePicker"])
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed)
            }
            let contentFits = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let title = app.staticTexts["onboardingTitle"]
                return title.exists && title.isHittable && !app.scrollViews["onboardingFallbackScroll"].exists
            }, object: nil)
            let fitted = XCTWaiter.wait(for: [contentFits], timeout: 5)
            for (screenIndex, screen) in XCUIScreen.screens.enumerated() {
                let shot = XCTAttachment(screenshot: screen.screenshot())
                shot.name = "Fitted onboarding step \(index + 1) screen \(screenIndex)"
                shot.lifetime = .keepAlways; add(shot)
            }
            XCTAssertFalse(app.scrollViews["onboardingFallbackScroll"].exists, "Normal text should use a layout without a scroll view")
            XCTAssertEqual(fitted, .completed, "The settled page must fit without scrolling")
            XCTAssertTrue(app.staticTexts["onboardingTitle"].isHittable)
            if index == 2 {
                let hint = app.staticTexts["onboardingLanguageHint"]
                XCTAssertTrue(hint.isHittable)
                XCTAssertLessThan(hint.frame.maxY, app.descendants(matching: .any)["onboardingProgress"].firstMatch.frame.minY - 8)
                if app.buttons["onboardingSpeechSetup"].exists { XCTAssertTrue(app.buttons["onboardingSpeechSetup"].isHittable) }
            }
            if index == 4 {
                XCTAssertTrue(app.buttons["onboardingTipJotley"].isHittable)
                XCTAssertTrue(app.buttons["onboardingReviewJotley"].isHittable)
                XCTAssertTrue(app.staticTexts["onboardingSupportSettingsHint"].isHittable)
            }
            XCTAssertEqual(block.frame.minY, initialBlock.minY, accuracy: 1, "Center one outer block, not each page individually")
            tallestPageHeight = max(tallestPageHeight, block.frame.height)
            let headerBottom = app.descendants(matching: .any)["onboardingHeader"].firstMatch.frame.maxY
            let footerTop = app.descendants(matching: .any)["onboardingProgress"].firstMatch.frame.minY
            print("ONBOARDING step=\(index) block=\(block.frame) headerBottom=\(headerBottom) footerTop=\(footerTop) heading=\(app.staticTexts["onboardingTitle"].frame)")
            XCTAssertEqual(app.buttons["onboardingContinue"].frame.minY, initialAction.minY, accuracy: 1)
            XCTAssertEqual(app.staticTexts["onboardingTitle"].frame.minY, initialTitleTop, accuracy: 1, "Onboarding headings must stay at the same height on every page")
            if index < 4 {
                if index == 3 && app.buttons["onboardingNotNow"].exists { app.buttons["onboardingNotNow"].tap() }
                else { app.buttons["onboardingContinue"].tap() }
            }
        }
        let headerBottom = app.descendants(matching: .any)["onboardingHeader"].firstMatch.frame.maxY
        let footerTop = app.descendants(matching: .any)["onboardingProgress"].firstMatch.frame.minY
        XCTAssertGreaterThan(initialBlock.minY + tallestPageHeight / 2, (headerBottom + footerTop) / 2 + 8,
            "The shared content block should sit lower in the available area")
        XCTAssertLessThanOrEqual(initialBlock.minY + tallestPageHeight, footerTop - 8,
            "Even the tallest page must remain clear of the footer")
    }

    @MainActor func testOnboardingSupportIsOptionalAndStorefrontAware() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Keep this note","folder":"","tags":[],"transcript":"Existing notes stay safe.","summary":""}]"###
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        for country in ["USA", "GBR"] {
            app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = country
            app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = country == "USA" ? "Dark" : "Light"
            app.launch()
            let title = app.staticTexts["onboardingTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            for _ in 0..<3 { app.buttons["onboardingContinue"].tap() }
            if app.buttons["onboardingNotNow"].exists { app.buttons["onboardingNotNow"].tap() }
            else { app.buttons["onboardingContinue"].tap() }
            XCTAssertEqual(title.label, "Free software.\nSupported by people.")
            let tip = app.buttons["onboardingTipJotley"]
            if country == "USA" {
                XCTAssertTrue(tip.waitForExistence(timeout: 5))
                if !tip.isHittable { app.scrollViews.firstMatch.swipeUp() }
                XCTAssertTrue(tip.isHittable)
            } else { XCTAssertFalse(tip.exists) }
            let review = app.buttons["onboardingReviewJotley"]
            XCTAssertTrue(review.exists)
            if !review.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(review.isHittable)
            XCTAssertTrue(app.staticTexts["onboardingSupportSettingsHint"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let shot = XCTAttachment(screenshot: screen.screenshot())
                shot.name = "Optional onboarding support - \(country) - screen \(index)"
                shot.lifetime = .keepAlways; add(shot)
            }
            let back = app.buttons["onboardingBack"]
            XCTAssertTrue(back.isHittable); back.tap()
            XCTAssertEqual(title.label, onboardingTitle("Give your words a place.", in: app))
            if app.buttons["onboardingNotNow"].exists { app.buttons["onboardingNotNow"].tap() }
            else { app.buttons["onboardingContinue"].tap() }
            app.buttons["onboardingContinue"].tap()
            XCTAssertTrue(app.staticTexts["Keep this note"].waitForExistence(timeout: 8))
            app.terminate()
            app.launchEnvironment.removeValue(forKey: "JOTLEY_TEST_RESET_ONBOARDING")
            app.launch()
            XCTAssertTrue(app.buttons["notesListSettingsButton"].waitForExistence(timeout: 10))
            XCTAssertFalse(title.exists)
            app.terminate()
        }
    }

    @MainActor func testFirstSummaryFooterClearsLastTranscriptLine() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let text = (1...20).map { "Paragraph \($0): Review the next steps and keep a clear record of the conversation." }.joined(separator: "\n\n") + "\n\nFinal line above summary controls."
        let fixture: [[String: Any]] = [["title": "First summary footer", "folder": "Work", "tags": [], "transcript": text, "summary": ""]]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "First summary footer").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let primary = app.buttons["noteDetailGenerateSummaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5)); XCTAssertTrue(primary.isHittable)
        let last = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Final line above summary controls.'")).firstMatch
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<14 {
            if last.exists && last.isHittable && last.frame.maxY < primary.frame.minY - 8 { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(last.exists && last.isHittable)
        XCTAssertLessThan(last.frame.maxY, primary.frame.minY - 8)
        XCTAssertTrue(primary.isHittable)
        XCTAssertTrue(app.buttons["noteDetailTemplatesButton"].isHittable)
        XCTAssertLessThan(primary.frame.maxY, app.buttons["noteDetailContinueTranscriptionButton"].frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "First-time summary controls above Continue and Plus"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testSummaryFooterStaysInDetailColumnWithSidebar() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Column alignment check","folder":"Work","tags":[],"transcript":"Keep the controls with this note, without covering the notes list.","summary":""}]"###
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Column alignment check").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        var verifiedSideBySideLayout = false
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let primary = app.buttons["noteDetailGenerateSummaryButton"]
            XCTAssertTrue(primary.waitForExistence(timeout: 5))
            let title = app.staticTexts["noteDetailTitle"]
            let template = app.buttons["noteDetailTemplatesButton"]
            let quick = app.buttons["noteDetailContinueTranscriptionButton"]
            XCTAssertTrue(primary.isHittable && template.isHittable && quick.isHittable)
            if row.isHittable && row.frame.maxX <= title.frame.minX {
                verifiedSideBySideLayout = true
                XCTAssertGreaterThanOrEqual(template.frame.minX, title.frame.minX - 1)
                XCTAssertGreaterThanOrEqual(primary.frame.minX, title.frame.minX - 1)
                XCTAssertGreaterThan(quick.frame.minX, row.frame.maxX)
                XCTAssertEqual(quick.frame.midX, (template.frame.minX + primary.frame.maxX) / 2, accuracy: 1)
                let plus = app.buttons["notesListNewNoteButton"]
                if (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPhone") {
                    // Foldable app.frame can describe the inactive outer
                    // display. Both controls must share the active column edge.
                    XCTAssertEqual(primary.frame.maxX, plus.frame.maxX, accuracy: 1)
                }
            }
            XCTAssertLessThan(primary.frame.maxY, quick.frame.minY)
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let capture = XCTAttachment(screenshot: screen.screenshot())
                capture.name = "Detail-column footer - \(orientation.rawValue) - screen \(index)"
                capture.lifetime = .keepAlways; add(capture)
            }
        }
        XCTAssertTrue(verifiedSideBySideLayout, "Run this check on an unfolded Duo or iPad with an adjacent sidebar")
    }

    @MainActor func testSummaryActionsKeepPaddingAcrossWindowChanges() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        for hasSummary in [true, false] {
            let title = hasSummary ? "Summary ready" : "Transcript ready"
            let fixture: [[String: Any]] = [["title": title, "folder": "Work", "tags": [],
                "transcript": "Maya will review Friday’s launch plan. Alex will finish the accessibility checks.",
                "summary": hasSummary ? "## Key Points\n- Review Friday’s launch plan." : ""]]
            app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let row = app.buttons.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait] {
                XCUIDevice.shared.orientation = orientation
                let primary = app.buttons["noteDetailGenerateSummaryButton"]
                if hasSummary {
                    XCTAssertFalse(primary.exists, "Regeneration belongs in More after a summary exists")
                    XCTAssertFalse(app.buttons["noteDetailTemplatesButton"].exists)
                    let quickAction = app.buttons["noteDetailSummaryAskAIButton"]
                    let settled = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: quickAction)
                    wait(for: [settled], timeout: 5)
                    XCTAssertEqual(quickAction.frame.height, 44, accuracy: 1)
                    app.buttons["noteDetailMoreActionsButton"].tap()
                    XCTAssertFalse(app.buttons["noteDetailGenerateSummaryMenuButton"].exists)
                    app.buttons["noteDetailSummaryTemplateMenu"].tap()
                    let template = app.buttons["Personal Note"]
                    XCTAssertTrue(template.waitForExistence(timeout: 5))
                    // Opening the template menu must not start inference.
                    app.tap()
                    XCTAssertTrue(app.buttons["noteDetailSummaryAskAIButton"].exists)
                } else {
                    XCTAssertTrue(primary.waitForExistence(timeout: 5))
                    XCTAssertEqual(primary.label, "Generate Summary")
                    let textWidth = ("Generate Summary" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width
                    XCTAssertGreaterThanOrEqual(primary.frame.width, textWidth + 31)
                    XCTAssertTrue(app.buttons["noteDetailTemplatesButton"].isHittable)
                    if orientation == .portrait {
                        XCTAssertGreaterThan(primary.frame.minY, app.frame.midY, "First-time generation stays at the bottom")
                    }
                    XCTAssertLessThan(primary.frame.maxY, app.buttons["noteDetailContinueTranscriptionButton"].frame.minY,
                                      "First-time generation belongs above the bottom quick actions")
                }
                if orientation == .portrait {
                    let isPhone = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPhone")
                    let cornerButton = isPhone ? app.buttons["notesListNewNoteButton"] : app.buttons[hasSummary ? "noteDetailSummaryAskAIButton" : "noteDetailContinueTranscriptionButton"]
                    XCTAssertEqual(app.frame.maxY - cornerButton.frame.maxY, isPhone ? 24 : 16, accuracy: 2)
                    if isPhone { XCTAssertEqual(app.frame.maxX - cornerButton.frame.maxX, 24, accuracy: 2) }
                }
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let capture = XCTAttachment(screenshot: screen.screenshot())
                    capture.name = "\(hasSummary ? "Regenerate" : "Generate") Summary - \(orientation.rawValue) - screen \(index)"
                    capture.lifetime = .keepAlways; add(capture)
                }
            }
            app.terminate()
        }
    }

    @MainActor func testNotesListLastNoteScrollsAboveCaptureButton() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let fixture: [[String: Any]] = (1...20).map { index in
            ["title": "Scroll note \(index)", "folder": "", "tags": [],
             "transcript": "Example note \(index).", "summary": "Summary \(index).",
             "timestampOffset": -Double(index * 86_400)]
        }
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            XCTAssertTrue(app.staticTexts["Scroll note 1"].waitForExistence(timeout: 15))
            let last = app.buttons.containing(.staticText, identifier: "Scroll note 20").firstMatch
            let plus = app.buttons["notesListNewNoteButton"]
            let list = app.collectionViews.firstMatch
            // An open portrait Duo drawer covers the detail footer; its rows
            // can use the drawer's full height. Adjacent/compact lists clear it.
            let isPortraitDrawer = app.frame.height > app.frame.width && UIDevice.current.userInterfaceIdiom == .phone && app.frame.width > 500
            let bottomLimit = isPortraitDrawer ? list.frame.maxY - 8 : plus.frame.minY - 8
            for _ in 0..<12 {
                if last.exists && last.isHittable && last.frame.maxY < bottomLimit { break }
                if list.exists { list.swipeUp() } else { app.swipeUp() }
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Last library note above footer - \(orientation.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertTrue(last.exists && last.isHittable, "The oldest note must be reachable by scrolling")
            XCTAssertLessThan(last.frame.maxY, bottomLimit, "The complete last row must remain above visible controls or within the drawer")
            last.tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, "Scroll note 20")
        }
    }

    @MainActor func testTranscriptLastLineClearsFloatingControls() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let text = (1...25).map { "Paragraph \($0): Review the next steps and keep a clear record of the conversation." }.joined(separator: "\n\n") + "\n\nFinal transcript line stays readable."
        let fixture: [[String: Any]] = [["title": "Floating footer check", "folder": "", "tags": [], "transcript": text, "summary": "A long conversation."]]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        for appearance in ["Light", "Dark"] {
            XCUIDevice.shared.orientation = .portrait
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = appearance
            app.launch()
            let row = app.buttons.containing(.staticText, identifier: "Floating footer check").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
            app.buttons["noteDetailTranscriptTab"].tap()
            let last = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final transcript line stays readable.")).firstMatch
            let continueButton = app.buttons["noteDetailContinueTranscriptionButton"]
            let content = app.scrollViews.firstMatch
            for _ in 0..<14 {
                if last.exists && last.isHittable && last.frame.maxY < continueButton.frame.minY - 8 { break }
                content.swipeUp()
            }
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Transcript hierarchy - \(appearance)"
            hierarchy.lifetime = .keepAlways; add(hierarchy)
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let capture = XCTAttachment(screenshot: screen.screenshot())
                capture.name = "Transcript screen \(index) - \(appearance)"
                capture.lifetime = .keepAlways; add(capture)
            }
            XCTAssertTrue(last.exists && last.isHittable)
            XCTAssertLessThan(last.frame.maxY, continueButton.frame.minY - 8, "The last line must scroll fully clear of the floating controls")
            XCTAssertTrue(continueButton.isHittable)
            XCTAssertEqual(continueButton.frame.height, 44, accuracy: 1)
            XCTAssertFalse(app.buttons["noteDetailGenerateSummaryButton"].exists)
            let isPhone = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPhone")
            let cornerButton = isPhone ? app.buttons["notesListNewNoteButton"] : continueButton
            XCTAssertEqual(app.frame.maxY - cornerButton.frame.maxY, isPhone ? 24 : 16, accuracy: 2)
            if isPhone { XCTAssertEqual(app.frame.maxX - cornerButton.frame.maxX, 24, accuracy: 2) }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Floating controls with complete transcript - \(appearance)"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
    }

    @MainActor func testSimulatedCaptureTimerMatchesElapsedTimeAndPauses() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launch()
        let plus = app.buttons["notesListNewNoteButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15)); plus.tap()
        let duration = app.staticTexts["transcriptionDurationText"]
        XCTAssertTrue(duration.waitForExistence(timeout: 10))
        func seconds() -> Int {
            let numbers = duration.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            return numbers.count == 2 ? numbers[0] * 60 + numbers[1] : -1
        }
        let before = seconds()
        let started = ProcessInfo.processInfo.systemUptime
        Thread.sleep(forTimeInterval: 3)
        let after = seconds()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertEqual(Double(after - before), elapsed, accuracy: 1.5, "Simulator capture must advance at real time")
        app.buttons["transcriptionPauseButton"].tap()
        let paused = seconds()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(seconds(), paused, "Pause must freeze the timer")
        app.buttons["transcriptionCloseButton"].tap()
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
    }

    @MainActor func testOnboardingSpeechSetupStartsOrReportsItsResult() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "en-US"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 15))
        app.buttons["onboardingContinue"].tap()
        app.buttons["onboardingContinue"].tap()
        let setup = app.buttons["onboardingSpeechSetup"]
        guard setup.waitForExistence(timeout: 10) else { throw XCTSkip("This runtime does not need speech setup") }
        setup.tap()
        let activeOrFinished = NSPredicate { _, _ in
            app.buttons["onboardingCancelSpeechSetup"].exists ||
            app.descendants(matching: .any)["onboardingSpeechError"].firstMatch.exists ||
            app.staticTexts["Ready to transcribe offline"].exists
        }
        let changed = expectation(for: activeOrFinished, evaluatedWith: app)
        wait(for: [changed], timeout: 15)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Real Apple speech setup action"; capture.lifetime = .keepAlways; add(capture)
        if app.buttons["onboardingCancelSpeechSetup"].exists {
            app.buttons["onboardingCancelSpeechSetup"].tap()
            XCTAssertTrue(setup.waitForExistence(timeout: 15), "Cancellation must leave setup available to retry")
        }
    }

    @MainActor func testWelcomeSetupPersistsAndCanBeReopenedWithoutLosingNotes() throws {
        let isPad = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad")
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Keep this note","folder":"","tags":[],"transcript":"Existing words remain safe while setting up Jotley.","summary":"A saved note."}]"###
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        for mode in ["Dark", "Light"] {
            let selectedLanguage = mode == "Dark" ? "French" : "German"
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = mode
            app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
            app.launch()
            let title = app.staticTexts["onboardingTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            let actionFrame = app.buttons["onboardingContinue"].frame
            let progressY = app.descendants(matching: .any)["onboardingProgress"].firstMatch.frame.midY
            for expected in ["Stay in the conversation.", "Find the useful parts.", "Start with your language.", "Give your words a place."] {
                XCTAssertEqual(title.label, onboardingTitle(expected, in: app))
                XCTAssertTrue(app.buttons["onboardingContinue"].isHittable, "The primary action must remain visible")
                XCTAssertLessThanOrEqual(app.buttons["onboardingContinue"].frame.maxX, app.frame.maxX - 12, "The action must fit completely inside the window")
                XCTAssertGreaterThanOrEqual(app.buttons["onboardingContinue"].frame.minX, app.frame.minX + 12)
                XCTAssertEqual(app.buttons["onboardingContinue"].frame.minY, actionFrame.minY, accuracy: 1)
                XCTAssertEqual(app.buttons["onboardingContinue"].frame.minX, actionFrame.minX, accuracy: 1)
                XCTAssertEqual(app.descendants(matching: .any)["onboardingProgress"].firstMatch.frame.midY, progressY, accuracy: 1)
                if expected == "Give your words a place.", app.buttons["onboardingNotNow"].exists {
                    let secondary = app.buttons["onboardingNotNow"].frame
                    let primary = app.buttons["onboardingContinue"].frame
                    XCTAssertEqual(secondary.midX, primary.midX, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(secondary.minY, primary.maxY + 8)
                }
                XCTAssertEqual(app.alerts.count, 0, "No permission alert should appear without an explicit request")
                if expected == "Start with your language." {
                    let picker = app.buttons["onboardingLanguagePicker"]
                    XCTAssertTrue(picker.waitForExistence(timeout: 10))
                    let enabled = NSPredicate(format: "enabled == true")
                    expectation(for: enabled, evaluatedWith: picker)
                    waitForExpectations(timeout: 15)
                    picker.tap()
                    for unsupported in ["Arabic", "Russian", "Hindi", "Polish", "Ukrainian"] {
                        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", unsupported)).firstMatch.exists)
                    }
                    XCTAssertFalse(app.buttons["English (United Kingdom)"].exists, "Regional variants must not become extra languages")
                    let choice = app.buttons[selectedLanguage]
                    XCTAssertTrue(choice.waitForExistence(timeout: 5))
                    choice.tap()
                    XCTAssertTrue(picker.label.contains(selectedLanguage))
                }
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "Jotley welcome \(mode) - \(expected)"
                attachment.lifetime = .keepAlways; add(attachment)
                if expected != "Give your words a place." { app.buttons["onboardingContinue"].tap() }
            }
            if app.buttons["onboardingNotNow"].exists { app.buttons["onboardingNotNow"].tap() }
            else { app.buttons["onboardingContinue"].tap() }
            XCTAssertEqual(title.label, "Free software.\nSupported by people.")
            XCTAssertTrue(app.staticTexts["onboardingSupportSettingsHint"].exists)
            app.buttons["onboardingContinue"].tap()
            XCTAssertTrue(app.staticTexts["Keep this note"].waitForExistence(timeout: 8))
            app.terminate()
            app.launchEnvironment.removeValue(forKey: "JOTLEY_TEST_RESET_ONBOARDING")
            app.launch()
            let settings = app.buttons["notesListSettingsButton"]
            if !settings.exists {
                let back = app.buttons["BackButton"]
                if back.waitForExistence(timeout: 5) { back.tap() }
                else {
                    let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
                    XCTAssertTrue(sidebar.waitForExistence(timeout: 5)); sidebar.tap()
                }
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            XCTAssertFalse(title.exists, "Completed setup must not appear again on launch")
            app.buttons["notesListSettingsButton"].tap()
            XCTAssertTrue(app.buttons["settingsDoneButton"].waitForExistence(timeout: 8))
            let form = app.descendants(matching: .any)["settingsForm"].firstMatch
            XCTAssertTrue(form.waitForExistence(timeout: 5))
            let savedLanguage = app.descendants(matching: .any)["settingsLanguagePicker"].firstMatch
            for _ in 0..<9 {
                if savedLanguage.exists && savedLanguage.isHittable { break }
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                    .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            }
            XCTAssertTrue(savedLanguage.waitForExistence(timeout: 3), app.debugDescription)
            XCTAssertEqual(savedLanguage.value as? String, selectedLanguage, "Settings and onboarding must use the same saved language")
            let replay = app.buttons["settingsWelcomeJotley"]
            for _ in 0..<8 {
                if replay.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(replay.isHittable)
            replay.tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, onboardingTitle("Stay in the conversation.", in: app))
            XCTAssertFalse(app.buttons["settingsDoneButton"].exists, "Replaying welcome must dismiss Settings first")
            if mode == "Dark" {
                app.buttons["onboardingSkip"].tap()
            } else {
                for _ in 0..<5 {
                    if app.buttons["onboardingNotNow"].exists { app.buttons["onboardingNotNow"].tap() }
                    else { app.buttons["onboardingContinue"].tap() }
                }
            }
            XCTAssertTrue(app.staticTexts["Keep this note"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["settingsDoneButton"].exists, "Finishing or skipping welcome must return to notes")
            app.terminate()
        }
    }

    @MainActor func testWelcomeSkipRemainsAccessibleWithLargeTextAndYellowTheme() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Yellow", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["onboardingTitle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["onboardingSkip"].isHittable)
        XCTAssertTrue(app.buttons["onboardingContinue"].isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Welcome with accessibility text and Yellow theme"
        attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["onboardingSkip"].tap()
        XCTAssertTrue(app.buttons["notesListSettingsButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor func testIPadSplitSelectionHighlightsOnlyTheOpenNote() throws {
        guard (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad") else {
            throw XCTSkip("Split selection requires iPad")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Design review","folder":"Work","tags":[],"transcript":"Maya reviews the new interface Friday.","summary":"## Next Steps\n- Review the interface."},{"title":"Garden plans","folder":"Personal","tags":[],"transcript":"Plant herbs by the kitchen window.","summary":"## Weekend\n- Plant herbs."}]"###
        defer { XCUIDevice.shared.orientation = .portrait }

        func assertHighlight(_ row: XCUIElement, selected: Bool) throws {
            XCTAssertEqual(row.isSelected, selected)
            let image = try XCTUnwrap(row.screenshot().image.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var colored = 0
            for index in 0..<(image.width * image.height) {
                let rgb = (0..<3).map { Int(pixels[index * 4 + $0]) }
                if rgb.max()! - rgb.min()! > 20 { colored += 1 }
            }
            let fraction = Double(colored) / Double(image.width * image.height)
            if selected { XCTAssertGreaterThan(fraction, 0.2, "The open note must have a visible theme-colored highlight") }
            else { XCTAssertLessThan(fraction, 0.02, "The previous selection must return to its neutral row") }
        }

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            for mode in ["Dark", "Light"] {
                app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = mode
                app.launch()
                let first = app.buttons.containing(.staticText, identifier: "Design review").firstMatch
                let second = app.buttons.containing(.staticText, identifier: "Garden plans").firstMatch
                XCTAssertTrue(first.waitForExistence(timeout: 15)); first.tap()
                XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, "Design review")
                try assertHighlight(first, selected: true); try assertHighlight(second, selected: false)
                second.tap()
                XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, "Garden plans")
                try assertHighlight(first, selected: false); try assertHighlight(second, selected: true)
                app.buttons["notesListSettingsButton"].tap()
                let done = app.buttons["settingsDoneButton"]
                XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
                try assertHighlight(second, selected: true)
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "iPad split selection and smaller gear - \(mode) \(orientation == .portrait ? "portrait" : "landscape")"
                attachment.lifetime = .keepAlways; add(attachment)
                app.terminate()
            }
        }
    }

    @MainActor func testRegeneratingSummaryReplacesVisibleTenTagSetWithoutReopeningNote() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let oldTags = (1...10).map { "Outdated-\($0)" }
        let fixture: [[String: Any]] = [
            ["title": "Tag replacement", "folder": "", "tags": oldTags,
             "transcript": String(repeating: "AI helps design teams plan research projects and meetings every week. ", count: 40),
             "summary": "An existing summary."],
            ["title": "Library buckets", "folder": "", "tags": ["AI", "Design"], "transcript": "Related work", "summary": ""]
        ]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_TEST_SUMMARY_TAGS"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchArguments = ["-jotleySummaryNotificationsEnabled", "NO"]
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Tag replacement").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.staticTexts["Outdated-1"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
            triggerSummaryAction(in: app)
            XCTAssertTrue(app.staticTexts["AI"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Design"].exists)
            for old in oldTags { XCTAssertFalse(app.staticTexts[old].exists, "Old tags must disappear without reopening the note") }
            XCTAssertFalse(app.staticTexts["Overflow"].exists)
            for tag in ["AI", "Design", "Research", "Planning", "Meetings"] {
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", tag)).count, 1)
            }
            XCTAssertTrue(app.buttons["noteDetailSummaryAskAIButton"].waitForExistence(timeout: 5))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Regeneration replaces ten visible tags with five library-aware tags"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testSettingsDoneGlassRemainsNeutralAcrossThemesAndAppearances() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()
        XCTAssertTrue(app.buttons["notesListSettingsButton"].waitForExistence(timeout: 15))
        app.buttons["notesListSettingsButton"].tap()
        for mode in ["Dark", "Light"] {
            app.descendants(matching: .any)["settingsAppearanceModePicker"].firstMatch.tap()
            app.buttons[mode].tap()
            for theme in ["Purple", "Magenta", "Orange", "Yellow", "Light Blue", "Neutral"] {
                app.descendants(matching: .any)["settingsThemeColorPicker"].firstMatch.tap()
                app.buttons[theme].tap()
                let done = app.buttons["settingsDoneButton"]
                XCTAssertTrue(done.isHittable)
                XCTAssertGreaterThanOrEqual(done.frame.width, 55, "Done must fit without truncating its label")
                let image = try XCTUnwrap(done.screenshot().image.cgImage)
                let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                var colored = 0
                for index in 0..<(image.width * image.height) {
                    let rgb = (0..<3).map { Int(pixels[index * 4 + $0]) }
                    if rgb.max()! - rgb.min()! > 45 { colored += 1 }
                }
                XCTAssertLessThan(Double(colored) / Double(image.width * image.height), 0.05,
                                  "Done must have neutral glass, not an accent fill: \(mode), \(theme)")
                if theme == "Magenta" || theme == "Neutral" {
                    let attachment = XCTAttachment(screenshot: app.screenshot())
                    attachment.name = "Neutral glass Done with \(theme) theme - \(mode)"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.buttons["notesListSettingsButton"].isHittable)
    }

    @MainActor func testMacStyleDateRowsStayReadableWhileScrolling() throws {
        guard (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad") else {
            throw XCTSkip("Sidebar rendering regression requires iPad")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_TEST_INLINE_NOTE_HEADERS"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        var fixture: [[String: Any]] = []
        for index in 0..<48 {
            let dayOffset = index / 3 * 86400
            let minuteOffset = index % 3 * 600
            let sample: [String: Any] = [
                "title": String(format: "Readable note %02d", index), "folder": "", "tags": [String](),
                "transcript": "Keep every note readable while browsing earlier dates.",
                "summary": "## Decisions\n- Keep the sidebar sharp.",
                "timestampOffset": -Double(dayOffset + minuteOffset)
            ]
            fixture.append(sample)
        }
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)

        func assertVisibleRowsAreSharp(dark: Bool) throws {
            let screenshot = XCUIScreen.main.screenshot()
            let normalized = UIGraphicsImageRenderer(size: screenshot.image.size).image { _ in
                screenshot.image.draw(at: .zero)
            }
            let image = try XCTUnwrap(normalized.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let appFrame = app.frame
            let scale = CGFloat(image.width) / appFrame.width
            let searchBottom = app.textFields["notesListSearchField"].frame.maxY
            let footerTop = app.buttons["notesListSettingsButton"].frame.minY
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notesListNoteRow-"))
            var checked = 0
            for row in rows.allElementsBoundByIndex {
                let frame = row.frame
                guard frame.minY > searchBottom + 8, frame.maxY < footerTop, frame.height > 35 else { continue }
                // Inspect title glyphs, not accessibility text: a blurred row can
                // still expose a perfectly readable label to VoiceOver.
                let title = CGRect(x: frame.minX + 12, y: frame.minY + 8,
                                   width: min(230, frame.width - 24), height: 20)
                var contrastingPixels = 0
                for y in max(0, Int((title.minY - appFrame.minY) * scale))..<min(image.height, Int((title.maxY - appFrame.minY) * scale)) {
                    for x in max(0, Int((title.minX - appFrame.minX) * scale))..<min(image.width, Int((title.maxX - appFrame.minX) * scale)) {
                        let offset = y * context.bytesPerRow + x * 4
                        let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                        if (dark ? min(r, g, b) > 185 : max(r, g, b) < 90) && max(r, g, b) - min(r, g, b) < 15 { contrastingPixels += 1 }
                    }
                }
                if contrastingPixels <= 35 {
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = "Unreadable sidebar row - \(row.label)"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
                XCTAssertGreaterThan(contrastingPixels, 35, "Visible note title must remain sharp: \(row.label), frame \(frame), app \(appFrame), image \(image.width)x\(image.height), orientation \(screenshot.image.imageOrientation.rawValue)")
                checked += 1
            }
            XCTAssertGreaterThan(checked, 2, "Must inspect several visible note rows")
        }

        for mode in ["Dark", "Light"] {
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = mode
            app.launch()
            XCTAssertTrue(app.textFields["notesListSearchField"].waitForExistence(timeout: 15))
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            for _ in 0..<4 { list.swipeUp(); try assertVisibleRowsAreSharp(dark: mode == "Dark") }
            for _ in 0..<3 { list.swipeDown(); try assertVisibleRowsAreSharp(dark: mode == "Dark") }
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notesListNoteRow-")).allElementsBoundByIndex.first { $0.isHittable }
            try XCTUnwrap(row).tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 5))
            try assertVisibleRowsAreSharp(dark: mode == "Dark")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Mac-style date rows after scrolling - \(mode)"
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }

    @MainActor func testSettingsPlacementKeepsIPadWindowControlsClear() throws {
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.exists, permission.label.contains("Jotley"), permission.buttons["Allow"].exists {
            permission.buttons["Allow"].tap()
        }
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        let isPad = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad")
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Weekly Design Review","folder":"Work","tags":["design","meeting"],"transcript":"Keep live transcription simple. Maya will test the next build on Friday.","summary":"## Key Decisions\n- Keep live transcription simple.\n- Make Settings easy to reach in every iPad window.\n\n## Next Steps\n- Maya: test the transcription flow.\n- Alex: review the summary templates.\n\n## Next Check-in\nFriday at 10:00. Bring one useful summary and one idea to simplify the experience."},{"title":"Lecture: Working Memory","folder":"Study","tags":[],"transcript":"Group related ideas and write down the next step.","summary":"## Main Ideas\n- Group related ideas.\n- Write down the next step."},{"title":"Weekend Ideas","folder":"Personal","tags":[],"transcript":"Walk the river trail. Try a new recipe.","summary":""}]"###
        let orientations: [UIDeviceOrientation] = isPad ? [.landscapeLeft, .portrait] : [.portrait]
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            for mode in ["Dark", "Light"] {
                app.terminate()
                app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = mode
                app.launch()
                let settings = app.buttons["notesListSettingsButton"]
                let search = app.textFields["notesListSearchField"]
                let plus = app.buttons["notesListNewNoteButton"]
                XCTAssertTrue(settings.waitForExistence(timeout: 15))
                XCTAssertTrue(search.isHittable && plus.isHittable && settings.isHittable)
                XCTAssertEqual(app.buttons.matching(identifier: "notesListSettingsButton").count, 1)
                if isPad {
                    XCTAssertGreaterThan(settings.frame.minY, search.frame.maxY + 200)
                    XCTAssertEqual(settings.frame.midY, plus.frame.midY, accuracy: 1)
                    XCTAssertLessThan(settings.frame.maxX, plus.frame.minX)
                    let navigationBar = app.navigationBars.firstMatch
                    XCTAssertTrue(navigationBar.exists, "Native navigation chrome must reserve space for iPad window controls")
                    XCTAssertGreaterThanOrEqual(search.frame.minY + 1, navigationBar.frame.maxY)
                    let row = app.buttons.containing(.staticText, identifier: "Weekly Design Review").firstMatch
                    XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
                    XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 5))
                    XCTAssertTrue(settings.isHittable)
                } else {
                    XCTAssertEqual(settings.frame.midY, search.frame.midY, accuracy: 1)
                    XCTAssertLessThan(settings.frame.maxX, search.frame.minX)
                }
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "iPad Settings placement \(orientation == .portrait ? "portrait" : "landscape") \(mode)"
                attachment.lifetime = .keepAlways; add(attachment)
                // Hit the full target, including padding beyond the smaller visible iPad circle.
                for point in [CGVector(dx: 0.05, dy: 0.5), CGVector(dx: 0.95, dy: 0.5),
                              CGVector(dx: 0.5, dy: 0.05), CGVector(dx: 0.5, dy: 0.95)] {
                    settings.coordinate(withNormalizedOffset: point).tap()
                    let done = app.buttons["settingsDoneButton"]
                    XCTAssertTrue(done.waitForExistence(timeout: 5), "The entire Settings circle must intercept taps")
                    done.tap()
                    XCTAssertTrue(settings.waitForExistence(timeout: 5)); XCTAssertTrue(settings.isHittable)
                }
            }
        }
    }

    @MainActor func testIPadSettingsInResizedWindowPreview() throws {
        guard (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad") else {
            throw XCTSkip("iPad window management only")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Weekly Design Review","folder":"Work","tags":["design"],"transcript":"Keep live transcription simple.","summary":"## Key Decisions\n- Keep live transcription simple.\n- Make Settings easy to reach in every iPad window.\n\n## Next Steps\n- Maya: test the transcription flow.\n- Alex: review the summary templates."}]"###
        app.launch()
        let settings = app.buttons["notesListSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        let fullScreenWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        func maximizeWindow() {
            guard app.windows.firstMatch.frame.width < fullScreenWidth - 40 else { return }
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
            let expanded = expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.width > fullScreenWidth - 40 }, evaluatedWith: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed, "Return the simulator to full screen after window testing")
        }
        maximizeWindow()
        defer { maximizeWindow() }
        let row = app.buttons.containing(.staticText, identifier: "Weekly Design Review").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let before = app.windows.firstMatch.frame
        // The iPad window manager owns the curved resize handle at this corner.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.993, dy: 0.993))
            .press(forDuration: 0.5, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.88)))
        let resized = expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.width < before.width - 40 }, evaluatedWith: nil)
        guard XCTWaiter.wait(for: [resized], timeout: 5) == .completed else {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Window resize unavailable in Simulator"; attachment.lifetime = .keepAlways; add(attachment)
            throw XCTSkip("Simulator window manager did not expose a resizable app window")
        }
        app.activate()
        let search = app.textFields["notesListSearchField"]
        if !search.isHittable {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        let ready = expectation(for: NSPredicate { _, _ in settings.isHittable && search.isHittable }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription)
        XCTAssertGreaterThan(settings.frame.minY, search.frame.maxY + 100)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "iPad Settings resized window Dark"; attachment.lifetime = .keepAlways; add(attachment)
        settings.tap()
        XCTAssertTrue(app.buttons["settingsDoneButton"].waitForExistence(timeout: 5))
        app.buttons["settingsDoneButton"].tap()
    }

    @MainActor func testMobileSheetDonePlacementAndDarkActionContrast() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Readable actions","folder":"Work","tags":["design"],"transcript":"Maya will test the new interface.","summary":"# Next Steps\n- Test the sheets in both appearances."}]"##
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()

        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        func assertTopRightDone(_ id: String) {
            let done = app.buttons[id]
            XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(done.isHittable)
            XCTAssertEqual(done.label, "Done")
            // Sheets may be centered on iPad; compare with their own title/header.
            let surface = app.windows.firstMatch.frame
            XCTAssertGreaterThan(done.frame.midX, surface.midX)
            // Native toolbar accessibility frames describe the glass capsule, not its enclosing touch target.
            XCTAssertGreaterThanOrEqual(done.frame.height, 32)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Done'")).count, 1)
        }
        func assertLightText(_ id: String, lightText: Bool = true) throws {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
            let image = try XCTUnwrap(app.screenshot().image.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var frame = element.frame.insetBy(dx: 5, dy: 3)
            if !lightText { frame = CGRect(x: frame.minX + frame.width * 0.7, y: frame.minY, width: frame.width * 0.3, height: frame.height) }
            let scale = CGFloat(image.width) / app.frame.width
            var brightNeutralPixels = 0
            for y in max(0, Int(frame.minY * scale))..<min(image.height, Int(frame.maxY * scale)) {
                for x in max(0, Int(frame.minX * scale))..<min(image.width, Int(frame.maxX * scale)) {
                    let offset = y * context.bytesPerRow + x * 4
                    let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                    if (lightText ? min(r, g, b) > 185 : max(r, g, b) < 120) && max(r, g, b) - min(r, g, b) < 12 { brightNeutralPixels += 1 }
                }
            }
            XCTAssertGreaterThan(brightNeutralPixels, 20, "Action text must have neutral contrast in the selected appearance: \(id)")
        }
        for (index, mode) in ["Dark", "Light", "Dark"].enumerated() {
            app.buttons["notesListSettingsButton"].tap()
            let picker = app.descendants(matching: .any)["settingsAppearanceModePicker"].firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap(); app.buttons[mode].tap()
            let themePicker = app.descendants(matching: .any)["settingsThemeColorPicker"].firstMatch
            themePicker.tap(); app.buttons[index == 2 ? "Orange" : "Purple"].tap()
            assertTopRightDone("settingsDoneButton")
            if mode == "Dark" {
                try assertLightText("settingsMacDownloadLink")
                try assertLightText("settingsShareMacDownloadLink")
                try assertLightText("settingsDoneButton")
            } else {
                try assertLightText("settingsAppearanceModePicker", lightText: false)
                try assertLightText("settingsThemeColorPicker", lightText: false)
            }
            capture("360 Settings \(mode) \(index == 2 ? "Orange" : "Purple")")
            app.buttons["settingsDoneButton"].tap()

            app.buttons["notesListFolderDrawerButton"].tap()
            assertTopRightDone("folderDrawerDoneButton")
            if mode == "Dark" { try assertLightText("folderDrawerDoneButton") }
            capture("360 Folders \(mode)")
            app.buttons["folderDrawerManageButton"].tap()
            assertTopRightDone("folderManagementDoneButton")
            capture("360 Manage Folders \(mode)")
            app.buttons["folderManagementDoneButton"].tap()

            app.buttons["notesListTagFilterButton"].tap()
            assertTopRightDone("filterSortDoneButton")
            let done = app.buttons["filterSortDoneButton"]
            let sort = app.descendants(matching: .any)["filterSortPicker"].firstMatch
            XCTAssertTrue(sort.waitForExistence(timeout: 5))
            XCTAssertLessThan(done.frame.maxY, sort.frame.minY)
            if mode == "Dark" { try assertLightText("filterSortPicker"); try assertLightText("filterSortDoneButton") }
            capture("360 Filter and Sort \(mode)")
            done.tap()
        }
        let row = app.buttons.containing(.staticText, identifier: "Readable actions").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let ask = app.buttons["noteDetailSummaryAskAIButton"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5)); try assertLightText("noteDetailSummaryAskAIButton")
        capture("360 Summary actions Dark")
        ask.tap()
        assertTopRightDone("askAIDoneButton")
        capture("360 Ask AI Done Dark")
        app.buttons["askAIDoneButton"].tap()
        app.buttons["Transcript"].tap()
        try assertLightText("noteDetailContinueTranscriptionButton")
        capture("360 Transcript actions Dark")
    }

    @MainActor func testStreamingSummaryFollowsBottomAndPinsCancelGeneration() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Summary scrolling","folder":"","tags":[],"transcript":"Maya reviews milestones Friday. Sam tests the next steps.","summary":"Existing summary remains after Cancel."}]"##
        app.launchEnvironment["JOTLEY_TEST_SUMMARY_SCROLL"] = "1"
        app.launchEnvironment["JOTLEY_TEST_SUMMARY_SCROLL_HOLD"] = "1"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        triggerSummaryAction(in: app)
        let cancel = app.buttons["noteDetailCancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); XCTAssertTrue(cancel.isHittable)
        XCTAssertEqual(cancel.frame.height, 44, accuracy: 1)
        XCTAssertTrue(app.staticTexts["Preparing summary"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let preparing = XCTAttachment(screenshot: app.screenshot())
        preparing.name = "Visible summary preparation before first words"; preparing.lifetime = .keepAlways; add(preparing)
        let latest = app.staticTexts.matching(NSPredicate(format: "label == 'Summary update 18'")).firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 10)); XCTAssertTrue(latest.isHittable)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertLessThanOrEqual(cancel.frame.maxY, app.frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Summary follows latest words with pinned Cancel Generation"; screenshot.lifetime = .keepAlways; add(screenshot)
        cancel.tap()
        let stopped = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cancel)
        wait(for: [stopped], timeout: 10)
        XCTAssertTrue(app.staticTexts["Existing summary remains after Cancel."].exists)
        XCTAssertTrue(app.buttons["noteDetailSummaryAskAIButton"].isEnabled)
        XCTAssertFalse(app.staticTexts["Summary update 25"].waitForExistence(timeout: 2))
    }

    @MainActor func testSummaryContinuesAfterLeavingNoteAndBackgroundingApp() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Background summary","folder":"","tags":[],"transcript":"Maya reviews Friday.","summary":"Existing summary"}]"##
        app.launchEnvironment["JOTLEY_TEST_SUMMARY_SCROLL"] = "1"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        triggerSummaryAction(in: app)
        XCTAssertTrue(app.buttons["noteDetailCancelGenerationButton"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        let cancel = app.buttons["noteDetailCancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Summary update '")).firstMatch.waitForExistence(timeout: 5))
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Back', 'Notes'}")).firstMatch
        XCTAssertTrue(back.exists); back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Summary continues after app background and note navigation"; shot.lifetime = .keepAlways; add(shot)
        cancel.tap()
        let stopped = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cancel)
        wait(for: [stopped], timeout: 10)
        XCTAssertTrue(app.staticTexts["Existing summary"].exists)
    }

    #if DEBUG

    @MainActor func testSummaryAskAIAndTranscriptFooterWithReadableAnswerActions() throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("Apple model is not ready in this simulator")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "en-US"]
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Weekly Design Review","folder":"Work","tags":[],"transcript":"We agreed to keep live transcription simple. Maya will test the microphone on Friday. Sam will review summary templates on Monday.","summary":"# Key Decisions\nKeep live transcription simple.\n\n## Next Steps\n- Maya: test the microphone on Friday.\n- Sam: review summary templates on Monday."}]"##
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Weekly Design Review").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let ask = app.buttons["noteDetailSummaryAskAIButton"]
        let resume = app.buttons["noteDetailContinueTranscriptionButton"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5)); XCTAssertFalse(resume.exists)
        for _ in 0..<2 {
            app.buttons["noteDetailTranscriptTab"].tap()
            XCTAssertTrue(resume.waitForExistence(timeout: 5)); XCTAssertFalse(ask.exists)
            app.buttons["noteDetailSummaryTab"].tap()
            XCTAssertTrue(ask.waitForExistence(timeout: 5)); XCTAssertFalse(resume.exists)
            XCTAssertFalse(app.buttons["noteDetailTemplatesButton"].exists)
            XCTAssertFalse(app.buttons["noteDetailGenerateSummaryButton"].exists)
        }
        let footer = XCTAttachment(screenshot: app.screenshot())
        footer.name = "Summary tab with contextual Ask AI"; footer.lifetime = .keepAlways; add(footer)
        ask.tap()
        let question = app.textViews["askAIQuestionField"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        app.buttons["List any action items"].tap()
        let send = app.buttons["askAISendButton"]
        XCTAssertEqual(question.frame.midY, send.frame.midY, accuracy: 2, "Send arrow should be centered beside its input")
        question.typeText("\n")
        let copy = app.buttons["askAICopyConversationButton"]
        let share = app.buttons["askAIShareConversationButton"]
        let done = app.buttons["askAIDoneButton"]
        XCTAssertGreaterThan(done.frame.minX, share.frame.midX)
        XCTAssertGreaterThan(done.frame.minX, app.buttons["askAIClearButton"].frame.midX)
        let answered = expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: copy)
        wait(for: [answered], timeout: 90)
        XCTAssertFalse(app.buttons["askAICopyAnswerButton"].exists, "Answers no longer carry their own Copy/Share")
        for button in [copy, share] {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        }
        let actions = XCTAttachment(screenshot: app.screenshot())
        actions.name = "Ask AI conversation Copy and Share"; actions.lifetime = .keepAlways; add(actions)
        copy.tap()
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(app.buttons["askAIDoneButton"].waitForExistence(timeout: 5))
        app.buttons["askAIDoneButton"].tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        let returnedToNote = expectation(for: NSPredicate(format: "hittable == YES"), evaluatedWith: ask)
        wait(for: [returnedToNote], timeout: 5)
        app.buttons["noteDetailTranscriptTab"].tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); XCTAssertFalse(ask.exists)
        app.buttons["noteDetailSummaryTab"].tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5)); ask.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        let nativeCopy = app.cells["Copy"]
        XCTAssertTrue(nativeCopy.waitForExistence(timeout: 10), app.debugDescription)
        // Verify the native local-sharing action without sending to another person.
        nativeCopy.tap()
    }
    @MainActor func testLongTranscriptShowsRealPreparationAndSavesActualSummary() throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("Apple summary model is not ready in this simulator")
        }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        let transcript = Array(repeating: "Maya owns accessibility testing for the native notes app. Sam will check that transcripts remain on the device. The team agreed to review the completed checklist on Friday and keep all features free.", count: 192).joined(separator: "\n\n")
        let fixture = [["title": "Weekly accessibility review", "folder": "Work", "tags": ["meeting"], "transcript": transcript, "summary": ""]] as [[String: Any]]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchArguments = ["-transcriptionLanguage", "en-US", "-selectedAppearanceMode", "Dark"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let generate = app.buttons["noteDetailGenerateSummaryButton"]
        generate.tap()
        XCTAssertTrue(app.staticTexts["Reading transcript"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["noteDetailCancelGenerationButton"].isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let preparation = XCTAttachment(screenshot: app.screenshot())
        preparation.name = "Actual long transcript preparation with section progress"; preparation.lifetime = .keepAlways; add(preparation)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        app.activate()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let finished = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: generate)
        wait(for: [finished], timeout: 90)
        XCTAssertFalse(app.buttons["noteDetailCancelGenerationButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Maya'")).firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        let completed = XCTAttachment(screenshot: app.screenshot())
        completed.name = "Actual long transcript summary completed"; completed.lifetime = .keepAlways; add(completed)
    }
    #endif

    @MainActor func testLiveTranscriptFillsFromTopThenFollowsBottom() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "layout"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] =
            ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]?.hasPrefix("iPad") == true ? "Light" : "Dark"
        app.launch()
        let plus = app.buttons["notesListNewNoteButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15)); plus.tap()
        let viewport = app.scrollViews["liveTranscript"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        let first = viewport.staticTexts["First spoken words."].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let roomyViewport = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in viewport.frame.height > 100 }, object: nil)
        let layout = XCTAttachment(screenshot: app.screenshot()); layout.name = "Live capture viewport"; layout.lifetime = .keepAlways; add(layout)
        wait(for: [roomyViewport], timeout: 10)
        XCTAssertGreaterThan(viewport.frame.height, 100, app.debugDescription)
        let firstY = first.frame.minY
        XCTAssertGreaterThanOrEqual(firstY, viewport.frame.minY)
        XCTAssertLessThan(firstY - viewport.frame.minY, 60, "A new transcript must start near the top, with blank space below")
        let beginning = XCTAttachment(screenshot: app.screenshot())
        beginning.name = "New transcript starts at the top"; beginning.lifetime = .keepAlways; add(beginning)
        let second = viewport.staticTexts["Second spoken words."].firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 12))
        XCTAssertEqual(first.frame.minY, firstY, accuracy: 2, "The first card must not shift while the short transcript grows")
        XCTAssertGreaterThan(second.frame.minY, first.frame.maxY)
        XCTAssertTrue(second.isHittable)
        let growing = XCTAttachment(screenshot: app.screenshot())
        growing.name = "Short transcript grows downward"; growing.lifetime = .keepAlways; add(growing)
        for text in ["Full-page transcript words.", "Newest transcript words."] {
            let latest = viewport.staticTexts[text].firstMatch
            XCTAssertTrue(latest.waitForExistence(timeout: 12))
            let follows = expectation(for: NSPredicate(format: "hittable == YES"), evaluatedWith: latest)
            wait(for: [follows], timeout: 5)
            XCTAssertLessThanOrEqual(latest.frame.maxY, viewport.frame.maxY + 1)
            XCTAssertGreaterThan(latest.frame.maxY, viewport.frame.maxY - 90, "Once the page fills, the newest words should remain near the bottom")
            XCTAssertFalse(first.isHittable, "Earlier cards should scroll off the page once the transcript overflows")
        }
        let full = XCTAttachment(screenshot: app.screenshot())
        full.name = "Full transcript follows new words at the bottom"; full.lifetime = .keepAlways; add(full)
        app.buttons["transcriptionCloseButton"].tap()
        XCTAssertTrue(app.staticTexts["Completed transcript."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["transcriptionStopButton"].exists)
    }

    @MainActor func testSwitchingNotesResetsDetailAndContinueUsesSameTranscriber() throws {
        guard (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad") else {
            throw XCTSkip("Split-view selection regression requires iPad")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"[{"title":"Summary note A","folder":"","tags":[],"transcript":"Transcript belonging to the first note.","summary":"## Decisions\n- Approved first note."},{"title":"Transcript note B","folder":"","tags":[],"transcript":"Transcript belonging only to the second note.","summary":""}]"###
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launch()
        let first = app.buttons.containing(.staticText, identifier: "Summary note A").firstMatch
        let second = app.buttons.containing(.staticText, identifier: "Transcript note B").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        for _ in 0..<3 {
            first.tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, "Summary note A")
            XCTAssertTrue(app.buttons["noteDetailSummaryAskAIButton"].waitForExistence(timeout: 5))
            second.tap()
            XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, "Transcript note B")
            XCTAssertTrue(app.staticTexts["Transcript belonging only to the second note."].exists)
            XCTAssertFalse(app.staticTexts["Approved first note."].exists)
        }
        app.buttons["noteDetailContinueTranscriptionButton"].tap()
        XCTAssertTrue(app.buttons["transcriptionStopButton"].waitForExistence(timeout: 10))
        app.buttons["transcriptionCloseButton"].tap()
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, "Transcript note B")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Completed transcript.")).firstMatch.exists)
    }

    @MainActor func testStopAndCloseSaveWithoutConfirmationAndRejectLateWords() throws {
        for action in ["transcriptionStopButton", "transcriptionCloseButton"] {
            let app = XCUIApplication()
            app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
            app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
            app.launchArguments = ["-selectedAppearanceMode", action == "transcriptionCloseButton" ? "Dark" : "Light"]
            app.launch()
            let plus = app.buttons["notesListNewNoteButton"]
            XCTAssertTrue(plus.waitForExistence(timeout: 15)); plus.tap()
            let stop = app.buttons["transcriptionStopButton"]
            XCTAssertTrue(stop.waitForExistence(timeout: 10))
            let lastWords = app.staticTexts["Latest incoming words."]
            XCTAssertTrue(lastWords.waitForExistence(timeout: 10))
            XCTAssertTrue(lastWords.isHittable, "Live transcript should follow the last timestamped card")
            XCTAssertTrue(app.staticTexts["01:25"].exists)
            let live = XCTAttachment(screenshot: app.screenshot())
            live.name = "Timestamped live cards with automatic bottom scroll - " + action
            live.lifetime = .keepAlways; add(live)
            app.buttons[action].tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Keep Transcribing"].exists)
            XCTAssertFalse(app.buttons["Stop and Save"].exists)
            XCTAssertTrue(app.staticTexts["Completed transcript."].exists)
            XCTAssertFalse(stop.exists)
            XCTAssertTrue(app.buttons["noteDetailContinueTranscriptionButton"].exists)
            XCTAssertEqual(app.buttons["noteDetailContinueTranscriptionButton"].label, "Continue Transcription")
            // The fixture attempts a callback two seconds after finalization.
            let late = app.staticTexts["LATE WORDS MUST NEVER APPEAR"]
            XCTAssertFalse(late.waitForExistence(timeout: 4))
            XCTAssertTrue(app.staticTexts["Completed transcript."].exists)
            app.buttons["noteDetailMoreActionsButton"].tap()
            XCTAssertEqual(app.buttons["noteDetailContinueTranscriptionMenuButton"].label, "Continue Transcription")
            XCTAssertFalse(app.buttons["View Live Transcription"].exists)
            app.buttons["noteDetailContinueTranscriptionMenuButton"].tap()
            XCTAssertTrue(stop.waitForExistence(timeout: 10))
            app.buttons["transcriptionCloseButton"].tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
            XCTAssertFalse(stop.exists)
            app.terminate()
        }
    }

    @MainActor func testRestoredQuickRecordAppearsInWidgetGallery() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launch()
        XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = home.icons["Jotley"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10)); icon.press(forDuration: 1.2)
        let editHome = home.buttons["Edit Home Screen"]
        XCTAssertTrue(editHome.waitForExistence(timeout: 5)); editHome.tap()
        let edit = home.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let add = home.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let search = home.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Jotley")
        let item = home.staticTexts["Jotley"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10)); item.tap()
        XCTAssertTrue(home.staticTexts["Live Transcription"].waitForExistence(timeout: 10))
        let screenshotImage = home.screenshot()
        let screenshot = XCTAttachment(screenshot: screenshotImage)
        screenshot.name = "Restored Jotley Quick Record widget gallery"; screenshot.lifetime = .keepAlways; self.add(screenshot)
        try screenshotImage.pngRepresentation.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-widget-gallery.png"))
        print("JOTLEY_WIDGET_SCREENSHOT", FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-widget-gallery.png").path)
        XCUIDevice.shared.press(.home)
    }

    @MainActor func testAskAIRestoredForExistingTranscribedNote() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Ask AI verification","folder":"","tags":[],"transcript":"Mina owns launch. We ship Friday.","summary":""}]"##
        app.launch()
        let note = app.staticTexts["Ask AI verification"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20)); note.tap()
        let more = app.buttons["noteDetailMoreActionsButton"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["noteDetailAskAIShortcut"].exists)
        XCTAssertFalse(app.buttons["noteDetailAskAIButton"].exists)
        more.tap()
        let menuAsk = app.buttons["noteDetailAskAIButton"]
        XCTAssertTrue(menuAsk.waitForExistence(timeout: 5)); menuAsk.tap()
        let field = app.textViews["askAIQuestionField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ask about your note"].exists)
        let screenshotImage = app.screenshot()
        let screenshot = XCTAttachment(screenshot: screenshotImage)
        screenshot.name = "Restored on-device Ask AI"; screenshot.lifetime = .keepAlways; add(screenshot)
        try screenshotImage.pngRepresentation.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-Ask-AI.png"))
        print("JOTLEY_ASK_SCREENSHOT", FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-Ask-AI.png").path)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "processed on this device")).firstMatch.exists)
        app.buttons["List any action items"].tap()
        XCTAssertEqual(field.value as? String, "List any action items")
        app.buttons["askAIDoneButton"].tap()
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["noteDetailAskAIShortcut"].exists)
        more.tap()
        XCTAssertTrue(menuAsk.waitForExistence(timeout: 5)); menuAsk.tap()
        XCTAssertTrue(app.buttons["askAIDoneButton"].waitForExistence(timeout: 5))
    }

    @MainActor func testSpeechPreflightFailureCannotStartCaptureOrOfferAudioRetry() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchArguments = ["-transcriptionLanguage", "zxx"]
        app.launch()
        XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
        app.buttons["notesListNewNoteButton"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Allow", "OK"] {
            let button = springboard.alerts.buttons[title]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
        let alert = app.alerts["Transcription Needs Attention"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'unavailable'")).firstMatch.exists)
        alert.buttons["OK"].tap()
        XCTAssertEqual(app.staticTexts["transcriptionDurationText"].label, "0m 0s")
        XCTAssertFalse(app.buttons["transcriptionStopButton"].exists)
        XCTAssertFalse(app.buttons["savedAudioPlayButton"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Live-only preflight failure does not advertise active capture"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["transcriptionCloseButton"].tap()
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["noteDetailTranscribeAudioButton"].exists)
        app.buttons["noteDetailMoreActionsButton"].tap()
        XCTAssertTrue(app.buttons["noteDetailContinueTranscriptionMenuButton"].exists)
        XCTAssertFalse(app.buttons["noteDetailPlayRecordingButton"].exists)
        XCTAssertFalse(app.buttons["retrySavedAudioButton"].exists)
    }


    @MainActor func testSpeechSettingsExplainUnsupportedLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "zxx", "-jotleyWelcomeCompleted.v1", "YES"]
        app.launch()
        let settings = app.buttons["notesListSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        let status = app.staticTexts["settingsModelStatus"]
        for _ in 0..<4 where !status.isHittable { app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let unsupported = expectation(for: NSPredicate(format: "label CONTAINS %@", "unavailable for the selected language"), evaluatedWith: status)
        wait(for: [unsupported], timeout: 10)
        XCTAssertFalse(app.buttons["settingsSpeechSetupButton"].exists)
        XCTAssertFalse(app.progressIndicators["settingsSpeechSetupProgress"].exists)
        XCTAssertTrue(app.buttons["settingsSpeechRefreshButton"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Speech model readiness and explicit setup explanation"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testAppearanceSwitchesBackAndForthAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launch()
        let settings = app.buttons["notesListSettingsButton"]
        let picker = app.descendants(matching: .any)["settingsAppearanceModePicker"].firstMatch
        for mode in ["Light", "Dark", "Light", "Dark"] {
            XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
            XCTAssertFalse(app.switches["settingsThemedSummaryHeadersToggle"].exists)
            XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
            let choice = app.buttons[mode]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription); choice.tap()
            app.buttons["Done"].tap()
            let search = app.textFields["notesListSearchField"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertEqual(search.frame.height, 44, accuracy: 0.01)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Live appearance switch \(mode)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.terminate(); app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Dark") || (picker.value as? String)?.contains("Dark") == true, app.debugDescription)
    }

    @MainActor func testSettingsShowsVersionAndBuildOnOneLine() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launch()
        let settings = app.buttons["notesListSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        let version = app.staticTexts["settingsAppVersion"]
        for _ in 0..<6 where !version.isHittable { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertNotNil(version.label.range(of: #"^Version [0-9]+\.[0-9]+(?:\.[0-9]+)? \([0-9]+\)$"#, options: .regularExpression))
        XCTAssertFalse(version.label.contains("\n"))
        // SwiftUI exposes the full Form row (56 points), including its padding.
        XCTAssertLessThanOrEqual(version.frame.height, 60)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings version and build on one line"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testLocalNotesSearchAndControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launch()
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        if !((model.hasPrefix("iPhone18,") || model.hasPrefix("iPhone19,")) || model.hasPrefix("iPad17,")) {
            XCTAssertTrue(app.staticTexts["Jotley Unavailable"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iPhone 17 or newer")).firstMatch.exists)
            XCTAssertFalse(app.buttons["notesListNewNoteButton"].exists)
            return
        }
        let search = app.textFields["notesListSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        // UIKit coordinate transforms can return 43.99999999999997 for 44 points.
        XCTAssertGreaterThanOrEqual(search.frame.height + 0.001, 44)
        XCTAssertLessThanOrEqual(search.frame.height, 45)
        let filter = app.buttons["notesListTagFilterButton"]
        XCTAssertGreaterThanOrEqual(filter.frame.height + 0.001, 44)
        XCTAssertGreaterThanOrEqual(filter.frame.width + 0.001, 44)
        filter.tap()
        XCTAssertTrue(app.staticTexts["Filter & Sort"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["notesListNewNoteButton"].tap()
        stopNewTranscriptionAndOpenNote(app)
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["newNoteWriteButton"].exists)
        XCTAssertFalse(app.buttons["newNoteImportButton"].exists)
        XCTAssertFalse(app.buttons["newNoteRecordButton"].exists)
        XCTAssertFalse(app.buttons["transcriptionPauseButton"].exists, "Stopping capture should dismiss the recording screen")
        let marker = "Offline note \(UUID().uuidString.prefix(8))"
        app.staticTexts["noteDetailTitle"].tap()
        let title = app.textFields["noteDetailTitleEditor"]
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + marker + "\n")
        app.terminate(); app.launch()
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(marker)
        let savedRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 5)); savedRow.tap()
        XCTAssertEqual(app.staticTexts["noteDetailTitle"].label, marker)
        XCTAssertFalse(app.buttons["Sign In"].exists)
        XCTAssertFalse(app.buttons["Subscribe"].exists)
    }
    @MainActor private func stopNewTranscriptionAndOpenNote(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.buttons["Allow"]
        if permission.waitForExistence(timeout: 2) { permission.tap() }
        let ok = springboard.alerts.buttons["OK"]
        if ok.exists { ok.tap() }
        let pause = app.buttons["transcriptionPauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        let alert = app.alerts["Transcription Needs Attention"]
        if alert.waitForExistence(timeout: 10) {
            alert.buttons["OK"].tap()
            XCTAssertEqual(app.staticTexts["transcriptionDurationText"].label, "0m 0s")
            XCTAssertFalse(app.buttons["transcriptionStopButton"].exists)
            app.buttons["transcriptionCloseButton"].tap()
        } else {
            XCTAssertEqual(pause.label, "Pause transcription")
            app.buttons["transcriptionStopButton"].tap()
        }
        if app.alerts["Jotley"].waitForExistence(timeout: 3) { app.alerts["Jotley"].buttons["OK"].tap() }
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 20))
    }


    @MainActor func testLiveOnlyNoteKeepsTemplatesAndContinueActionWithoutAudioControls() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "zxx"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Live transcript","folder":"","tags":[],"transcript":"Mina ships Friday.","summary":""}]"##
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.staticTexts["Mina ships Friday."].exists)
        XCTAssertTrue(app.buttons["noteDetailTemplatesButton"].exists)
        XCTAssertTrue(app.buttons["noteDetailGenerateSummaryButton"].isEnabled)
        XCTAssertFalse(app.buttons["savedAudioPlayButton"].exists)
        XCTAssertFalse(app.buttons["noteDetailTranscribeAudioButton"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        XCTAssertTrue(app.buttons["noteDetailContinueTranscriptionButton"].exists)
        screenshot.name = "Live-only note with templates and summary, without saved audio"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["noteDetailMoreActionsButton"].tap()
        let continued = app.buttons["noteDetailContinueTranscriptionMenuButton"]
        XCTAssertTrue(continued.exists); XCTAssertEqual(continued.label, "Continue Transcription")
        XCTAssertFalse(app.buttons["noteDetailPlayRecordingButton"].exists)
        continued.tap()
        XCTAssertTrue(app.buttons["transcriptionPauseButton"].waitForExistence(timeout: 10))
        app.buttons["transcriptionCloseButton"].tap()
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
        app.buttons["noteDetailTranscriptTab"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Completed transcript.")).firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testExistingTranscriptTemplatesStayVisibleWithoutChangingTabs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Template controls","folder":"","tags":[],"transcript":"Existing transcript words","summary":""}]"##
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let templates = app.buttons["noteDetailTemplatesButton"]
        XCTAssertTrue(templates.waitForExistence(timeout: 5))
        XCTAssertEqual(templates.label, "Templates: Auto")
        XCTAssertTrue(app.buttons["noteDetailGenerateSummaryButton"].isEnabled)
        for key in ["lecture", "meetings/stand-up", "default-summary"] {
            templates.tap()
            let choice = app.buttons["noteTemplate-" + key]
            if !choice.isHittable { app.swipeUp() }
            XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
            XCTAssertTrue(app.descendants(matching: .any)["noteDetailTranscriptContent"].exists)
            XCTAssertFalse(app.buttons["noteDetailRecordButton"].exists)
        }
        XCTAssertEqual(templates.label, "Templates: Auto")
    }


    @MainActor func testOriginalShareMenuExportsLocalMarkdownWithoutSending() throws {
        guard ["iPhone18,", "iPhone19,"].contains(where: { ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]?.hasPrefix($0) == true }) else { return }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
        app.buttons["notesListNewNoteButton"].tap()
        stopNewTranscriptionAndOpenNote(app)
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 5))
        let share = app.buttons["noteDetailShareButton"]
        XCTAssertTrue(share.exists); share.tap()
        XCTAssertTrue(app.buttons["shareNoteButton"].waitForExistence(timeout: 5))
        let more = app.buttons["More Export Options"]
        XCTAssertTrue(more.exists); more.tap()
        let formatted = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "exportMarkdownButton", "Full Note (Formatted)")).firstMatch
        XCTAssertTrue(formatted.waitForExistence(timeout: 5), app.debugDescription); formatted.tap()
        let saveToFiles = app.cells["Save to Files"]
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Original file export opens native share sheet"
        attachment.lifetime = .keepAlways; add(attachment)
        // Inspect local export availability only; never choose a messaging service.
        let close = app.buttons["Close"]
        XCTAssertTrue(close.exists); close.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["ActivityListView"].isHittable)
        share.tap()
        let textShare = app.buttons["shareNoteButton"]
        XCTAssertTrue(textShare.waitForExistence(timeout: 5)); textShare.tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(close.exists); close.tap()
        XCTAssertFalse(app.otherElements["ActivityListView"].isHittable)
    }

    #if DEBUG

    @MainActor private func openInlineSupportSettings(_ app: XCUIApplication) {
        let settings = app.buttons["notesListSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let feedback = app.buttons["settingsFeedbackJotley"]
        let form = app.descendants(matching: .any)["settingsForm"].firstMatch
        for _ in 0..<12 where !feedback.isHittable {
            if feedback.exists && feedback.frame.maxY < form.frame.minY { form.swipeDown() }
            else { form.swipeUp() }
        }
        XCTAssertTrue(feedback.isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["settingsDoneButton"].isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["settingsSupportJotleyCard"].exists)
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].exists)
    }

    @MainActor func testSupportActionsLiveDirectlyInSettingsAndShareReturnsThere() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #" [{"title":"Support verification","folder":"Work","tags":[],"transcript":"Local notes stay private.","summary":"A useful summary."}] "#
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "6"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "USA"
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        for mode in ["Dark", "Light"] {
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = mode
            app.launch()
            XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.staticTexts["jotleySupportTitle"].exists)
            openInlineSupportSettings(app)
            let actions = ["settingsRateJotley", "settingsTipJotley", "settingsShareJotley", "settingsFeedbackJotley"].map { app.buttons[$0] }
            XCTAssertTrue(actions[1].waitForExistence(timeout: 10))
            for action in actions {
                XCTAssertTrue(action.isHittable)
                XCTAssertGreaterThanOrEqual(action.frame.height, 44)
                XCTAssertGreaterThan(action.frame.width, 200)
                XCTAssertEqual(action.frame.minX, actions[0].frame.minX, accuracy: 2)
            }
            for index in 1..<actions.count { XCTAssertLessThanOrEqual(actions[index - 1].frame.maxY, actions[index].frame.minY) }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Inline Settings support - \(mode)"; attachment.lifetime = .keepAlways; add(attachment)
            if mode == "Light" {
                actions[2].tap()
                let copyCell = app.cells["Copy"]
                if copyCell.waitForExistence(timeout: 10) { copyCell.tap() }
                else {
                    let copyButton = app.buttons["Copy"]
                    XCTAssertTrue(copyButton.waitForExistence(timeout: 5), app.debugDescription); copyButton.tap()
                }
                XCTAssertTrue(app.buttons["settingsFeedbackJotley"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["settingsDoneButton"].isHittable)
                XCTAssertFalse(app.staticTexts["jotleySupportTitle"].exists)
            }
            app.terminate()
        }
        app.launchEnvironment.removeValue(forKey: "JOTLEY_TEST_ENGAGEMENT_COUNT")
        app.launch(); openInlineSupportSettings(app)
        XCTAssertTrue(app.buttons["settingsShareJotley"].isHittable)
    }

    @MainActor func testRestrictedStorefrontKeepsInlineSupportWithoutWebTips() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #" [{"title":"Regional support","folder":"Work","tags":[],"transcript":"Local transcript","summary":""}] "#
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "6"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "GBR"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launch()
        openInlineSupportSettings(app)
        XCTAssertTrue(app.buttons["settingsRateJotley"].isHittable)
        XCTAssertTrue(app.buttons["settingsShareJotley"].isHittable)
        XCTAssertFalse(app.buttons["settingsTipJotley"].exists)
        XCTAssertTrue(app.buttons["settingsFeedbackJotley"].isHittable)
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].exists)
    }
    @MainActor func testActualSummaryCompletionDoesNotInterruptWithCustomReviewMenu() throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("Apple summary model is not ready in this simulator")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "en-US"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Support milestone","folder":"Work","tags":[],"transcript":"We agreed to keep recordings offline. Maya will test the microphone and Sam will verify the summary templates.","summary":""}]
        """#
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "5"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "USA"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].exists)
        let generate = app.buttons["noteDetailGenerateSummaryButton"]
        XCTAssertTrue(generate.isEnabled); generate.tap()
        let cancel = app.buttons["noteDetailCancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        let finished = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cancel)
        wait(for: [finished], timeout: 60)
        XCTAssertFalse(generate.exists)
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].waitForExistence(timeout: 3), "The sixth saved action must not trigger a custom review prompt")
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists)
    }
    @MainActor func testNativeNoteBackNavigationWithoutCustomSwipes() throws {
        let isIPad = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad")
        XCUIDevice.shared.orientation = isIPad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Native navigation","folder":"Work","tags":[],"transcript":"These are the original spoken words.","summary":"## Summary\nA short overview.\n\n## Key Points\n- Keep navigation familiar."},{"title":"Swipe-delete regression","folder":"Work","tags":[],"transcript":"Disposable test note.","summary":""}]
        """#
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Native navigation").firstMatch
        let window = app.windows.firstMatch
        for tab in ["Summary", "Transcript"] {
            let tabButton = app.buttons["noteDetail\(tab)Tab"]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 15)); tabButton.tap()
            if isIPad {
                // A persistent native split view already exposes the notes menu.
                let content = app.descendants(matching: .any)["noteDetail\(tab)Content"].firstMatch
                content.swipeLeft()
                XCTAssertTrue(tabButton.isSelected, "A swipe must not change note tabs")
                content.swipeRight()
                XCTAssertTrue(tabButton.isSelected, "A swipe must not change note tabs")
            } else {
                let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: end)
                XCTAssertTrue(app.buttons["BackButton"].waitForNonExistence(timeout: 5), "The native Back gesture must return directly to notes from either tab")
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
            row.tap()
            XCTAssertTrue(app.buttons["noteDetailSummaryTab"].waitForExistence(timeout: 5))
        }
        if !isIPad { app.buttons["BackButton"].tap() }
        let disposable = app.buttons.containing(.staticText, identifier: "Swipe-delete regression").firstMatch
        XCTAssertTrue(disposable.waitForExistence(timeout: 5)); disposable.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(disposable.waitForNonExistence(timeout: 5)); XCTAssertTrue(row.exists)
    }

    @MainActor func testMoreMenuKeepsBothEditorsOnEitherTab() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Consistent note menu","folder":"Work","tags":[],"transcript":"Original spoken words.","summary":"## Summary\nA short overview.\n\n## Key Points\n- Keep both editors available."}]
        """#
        app.launchArguments = ["-jotleyWelcomeCompleted.v1", "YES"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launch()
        XCTAssertTrue(app.buttons["noteDetailSummaryTab"].waitForExistence(timeout: 15))
        for tab in ["Summary", "Transcript"] {
            let tabButton = app.buttons["noteDetail\(tab)Tab"]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 5)); tabButton.tap()
            app.buttons["noteDetailMoreActionsButton"].tap()
            for identifier in ["noteDetailSummaryStyleMenu", "noteDetailSummaryTemplateMenu", "noteDetailEditTranscriptButton", "noteDetailEditSummaryButton"] {
                XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 3), "\(identifier) is missing on \(tab)")
            }
            // Exercise the editor belonging to the other tab, not just its label.
            let other = tab == "Summary" ? "Transcript" : "Summary"
            app.buttons["noteDetailEdit\(other)Button"].tap()
            XCTAssertTrue(app.textViews["\(other.lowercased())EditorText"].waitForExistence(timeout: 5))
            app.buttons["\(other.lowercased())EditorCancelButton"].tap()
        }
    }

    @MainActor func testTranscriptEditingAndSummaryMenuAvailability() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #" [{"title":"Transcript editing verification","folder":"Work","tags":[],"transcript":"Original words.","summary":""}] "#
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()
        for identifier in ["notesListFolderDrawerButton", "notesListTagFilterButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 15))
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        app.buttons["notesListFolderDrawerButton"].tap()
        let manage = app.buttons["folderDrawerManageButton"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); manage.tap()
        let folderName = app.textFields["newFolderNameField"]
        XCTAssertTrue(folderName.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(folderName.frame.height, 56)
        let create = app.buttons["createFolderButton"]
        XCTAssertGreaterThanOrEqual(create.frame.height, 44)
        XCTAssertFalse(create.isEnabled)
        folderName.tap(); folderName.typeText("Release Checks")
        XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(app.staticTexts["Release Checks"].waitForExistence(timeout: 5))
        let folderAttachment = XCTAttachment(screenshot: app.screenshot())
        folderAttachment.name = "Folder creation"; folderAttachment.lifetime = .keepAlways; add(folderAttachment)
        app.buttons["folderManagementDoneButton"].tap()
        let row = app.buttons.containing(.staticText, identifier: "Transcript editing verification").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        func openEditor() {
            app.buttons["noteDetailMoreActionsButton"].tap()
            XCTAssertFalse(app.buttons["noteDetailEditSummaryButton"].exists)
            let edit = app.buttons["noteDetailEditTranscriptButton"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
            XCTAssertTrue(app.textViews["transcriptEditorText"].waitForExistence(timeout: 5))
        }
        openEditor()
        let editor = app.textViews["transcriptEditorText"]
        editor.tap(); editor.typeText(" Cancelled.")
        app.buttons["transcriptEditorCancelButton"].tap()
        XCTAssertTrue(app.staticTexts["Original words."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Cancelled.")).firstMatch.exists)
        openEditor()
        editor.tap(); editor.typeText(" Corrected.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Edit Transcript"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["transcriptEditorSaveButton"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Corrected.")).firstMatch.waitForExistence(timeout: 5))
        openEditor()
        XCTAssertTrue((editor.value as? String ?? "").contains("Corrected."))
        app.buttons["transcriptEditorCancelButton"].tap()
    }

    @MainActor func testTemplateChangesKeepLongSummaryVisibleAndResponsive() throws {
        let app = XCUIApplication()
        let summary = "# Long recording summary\n" + (0..<500).map { "- **Point \($0)**: decisions and action items from the recorded meeting." }.joined(separator: "\n")
        let fixture: [[String: Any]] = [["title": "Long template verification", "folder": "Work", "tags": [],
            "transcript": "Recorded meeting words.", "summary": summary]]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_TEST_SUMMARY_SCROLL"] = "1"
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Long template verification").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.staticTexts["Long recording summary"].waitForExistence(timeout: 5))
        let quickAction = app.buttons["noteDetailSummaryAskAIButton"]
        let quickActionFrame = quickAction.frame
        for (key, title) in [("lecture", "Lecture"), ("meetings/general", "General Meeting"), ("default-summary", "Auto"), ("lecture", "Lecture")] {
            app.buttons["noteDetailMoreActionsButton"].tap()
            app.buttons["noteDetailSummaryTemplateMenu"].tap()
            let choice = app.buttons[title]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            let start = Date(); choice.tap()
            if key != "default-summary" {
                let cancel = app.buttons["noteDetailCancelGenerationButton"]
                XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
            }
            XCTAssertTrue(quickAction.waitForExistence(timeout: 5))
            let actual = quickAction.frame
            XCTAssertEqual(actual.width, quickActionFrame.width, accuracy: 0.5)
            XCTAssertEqual(actual.height, quickActionFrame.height, accuracy: 0.5)
            XCTAssertEqual(actual.minX, quickActionFrame.minX, accuracy: 0.5)
            XCTAssertEqual(actual.minY, quickActionFrame.minY, accuracy: 0.5)
            print("Long-note template selection \(title): \(Date().timeIntervalSince(start))s")
            XCTAssertTrue(app.staticTexts["Long recording summary"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["markdownListItem-1"].firstMatch.exists)
            XCTAssertFalse(app.textViews.firstMatch.exists, "Template selection must not enter editing")
            XCTAssertFalse(app.buttons["noteDetailGenerateSummaryButton"].exists)
        }
        app.buttons["noteDetailMoreActionsButton"].tap()
        let edit = app.buttons["noteDetailEditSummaryButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "Summary menu with pencil icon"; menu.lifetime = .keepAlways; add(menu)
        edit.tap()
        XCTAssertTrue(app.textViews["summaryEditorText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["summaryEditorCancelButton"].exists)
        XCTAssertTrue(app.buttons["summaryEditorSaveButton"].exists)
        app.buttons["summaryEditorCancelButton"].tap()
        XCTAssertTrue(app.staticTexts["Long recording summary"].waitForExistence(timeout: 5))
    }

    @MainActor func testSummaryModalEditingAndMarkdownLists() throws {
        for appearance in ["Dark", "Light"] {
            let app = XCUIApplication()
            app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = appearance
            app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Summary editing verification","folder":"Work","tags":[],"transcript":"Original spoken words.","summary":"# Decisions\n- **Keep** the transcript.\n  - Follow up Friday.\n* Review the plan.\n+ Share the checklist.\n1. First step.\n2) Second step."}]"##
            app.launch()
            let row = app.buttons.containing(.staticText, identifier: "Summary editing verification").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
            let bullet = app.descendants(matching: .any)["markdownListItem-1"].firstMatch
            XCTAssertTrue(bullet.waitForExistence(timeout: 5))
            XCTAssertEqual(bullet.label, "• Keep the transcript.")
            let nested = app.descendants(matching: .any)["markdownListItem-2"].firstMatch
            XCTAssertEqual(nested.label, "• Follow up Friday.")
            XCTAssertGreaterThan(nested.frame.minX, bullet.frame.minX)
            XCTAssertEqual(app.descendants(matching: .any)["markdownListItem-5"].firstMatch.label, "1. First step.")
            XCTAssertEqual(app.descendants(matching: .any)["markdownListItem-6"].firstMatch.label, "2. Second step.")
            let rendered = XCTAttachment(screenshot: app.screenshot())
            rendered.name = "Rendered summary Markdown lists - \(appearance)"; rendered.lifetime = .keepAlways; add(rendered)

            func openEditor() {
                app.buttons["noteDetailMoreActionsButton"].tap()
                let edit = app.buttons["noteDetailEditSummaryButton"]
                XCTAssertTrue(edit.waitForExistence(timeout: 5)); XCTAssertEqual(edit.label, "Edit Summary"); edit.tap()
                XCTAssertTrue(app.textViews["summaryEditorText"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.navigationBars["Edit Summary"].exists)
            }
            openEditor()
            let editor = app.textViews["summaryEditorText"]
            XCTAssertTrue((editor.value as? String ?? "").contains("- **Keep** the transcript."))
            let modal = XCTAttachment(screenshot: app.screenshot())
            modal.name = "Summary Save Cancel modal - \(appearance)"; modal.lifetime = .keepAlways; add(modal)
            editor.tap(); editor.typeText("\n\n- Cancelled summary edit.\n\n")
            app.buttons["summaryEditorCancelButton"].tap()
            XCTAssertTrue(bullet.waitForExistence(timeout: 5))
            XCTAssertEqual(bullet.label, "• Keep the transcript.")
            openEditor()
            XCTAssertFalse((editor.value as? String ?? "").contains("Cancelled summary edit."))
            editor.tap(); editor.typeText("\n\n- Approved summary edit.\n\n")
            app.buttons["summaryEditorSaveButton"].tap()
            let saved = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'markdownListItem-' AND label == %@", "• Approved summary edit.")).firstMatch
            XCTAssertTrue(saved.waitForExistence(timeout: 5))
            app.buttons["noteDetailTranscriptTab"].tap()
            XCTAssertTrue(app.staticTexts["Original spoken words."].waitForExistence(timeout: 5))
            openEditor()
            XCTAssertTrue((editor.value as? String ?? "").contains("Approved summary edit."))
            app.buttons["summaryEditorCancelButton"].tap()
            XCTAssertTrue(app.buttons["noteDetailSummaryAskAIButton"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testOpenNoteHeadingsFollowLiveAppearanceChanges() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]?.hasPrefix("iPad") == true else { throw XCTSkip("Needs the iPad split view to keep the note open while changing Settings") }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Appearance verification","folder":"Work","tags":[],"transcript":"Recorded words.","summary":"# Neutral Heading\nBody text and a standard bullet:\n- Recorded audio"}]"##
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Appearance verification").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        for mode in ["Light", "Dark", "Light", "Dark"] {
            app.buttons["notesListSettingsButton"].tap()
            let picker = app.descendants(matching: .any)["settingsAppearanceModePicker"].firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
            app.buttons[mode].tap(); app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["Neutral Heading"].waitForExistence(timeout: 5))
            let snapshot = app.screenshot()
            let cgImage = try XCTUnwrap(snapshot.image.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            for label in ["Neutral Heading", "Body text and a standard bullet:"] {
                let frame = app.staticTexts[label].frame
                let scaleX = CGFloat(cgImage.width) / app.frame.width
                let scaleY = CGFloat(cgImage.height) / app.frame.height
                var levels: [Double] = []
                for y in max(0, Int(frame.minY * scaleY))..<min(cgImage.height, Int(frame.maxY * scaleY)) {
                    for x in max(0, Int(frame.minX * scaleX))..<min(cgImage.width, Int(frame.maxX * scaleX)) {
                        let offset = y * context.bytesPerRow + x * 4
                        let channels = [pixels[offset], pixels[offset + 1], pixels[offset + 2]]
                        if Int(channels.max()!) - Int(channels.min()!) <= 3 { levels.append(Double(channels[0]) / 255) }
                    }
                }
                XCTAssertFalse(levels.isEmpty)
                if mode == "Light" { XCTAssertLessThan(levels.min() ?? 1, 0.35, "\(label) must become dark in an already open note") }
                else { XCTAssertGreaterThan(levels.max() ?? 0, 0.65, "\(label) must become light in an already open note") }
            }
            let attachment = XCTAttachment(screenshot: snapshot)
            attachment.name = "Open note live appearance \(mode)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }


    @MainActor func testExistingNoteGeneratesActualSummaryTitleAndRegeneratesTemplate() throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("Apple summary model is not ready in this simulator")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "en-US"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Untitled","folder":"Work","tags":[],"transcript":"We agreed to keep recordings offline. Maya will test the microphone and Sam will verify the summary templates.","summary":""}]
        """#
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let templates = app.buttons["noteDetailTemplatesButton"]
        XCTAssertEqual(templates.label, "Templates: Auto")
        let generate = app.buttons["noteDetailGenerateSummaryButton"]
        XCTAssertTrue(generate.isEnabled); generate.tap()
        let title = app.staticTexts["noteDetailTitle"]
        let titled = expectation(for: NSPredicate(format: "exists == true AND label != 'Untitled'"), evaluatedWith: title)
        wait(for: [titled], timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        let generatedTitle = title.label
        app.buttons["noteDetailMoreActionsButton"].tap()
        app.buttons["noteDetailSummaryTemplateMenu"].tap()
        app.buttons["General Meeting"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists,
                      "Changing templates keeps the rendered summary open")
        triggerSummaryAction(in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Regenerate starts without a confirmation")
        let finished = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: app.buttons["noteDetailSummaryAskAIButton"])
        wait(for: [finished], timeout: 60)
        XCTAssertFalse(templates.exists)
        XCTAssertEqual(title.label, generatedTitle, "Regeneration preserves the generated title")
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        let summary = XCTAttachment(screenshot: app.screenshot())
        summary.name = "Actual simulator summary title and template regeneration"; summary.lifetime = .keepAlways; add(summary)
    }
    #endif

    @MainActor func testFloatingButtonGlowsFollowLiveThemeChanges() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let isPad = UIDevice.current.model.hasPrefix("iPad")
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple", "-jotleyWelcomeCompleted.v1", "YES"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Live theme controls","folder":"Work","tags":[],"transcript":"The team will review the launch on Friday.","summary":"## Summary\nThe team has a clear plan for Friday."}]
        """#
        app.launch()
        XCTAssertTrue(app.buttons["noteDetailSummaryTab"].waitForExistence(timeout: 15))
        if !isPad { app.buttons["BackButton"].tap() }

        func assertGlow(_ button: XCUIElement, theme: String) throws {
            XCTAssertTrue(button.isHittable)
            let screenshot = app.screenshot()
            let image = try XCTUnwrap(screenshot.image.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let frame = button.frame
            let scale = CGFloat(image.width) / app.frame.width
            var sum = [Double](repeating: 0, count: 3)
            var count = 0.0
            // Sample outside the capsule, excluding its border and icon. These
            // pixels must change even when the control itself isn't recreated.
            for edge in [frame.minY - 7, frame.maxY + 2] {
                for y in max(0, Int(edge * scale))..<min(image.height, Int((edge + 5) * scale)) {
                    for x in max(0, Int((frame.midX - 5) * scale))..<min(image.width, Int((frame.midX + 5) * scale)) {
                        let offset = y * context.bytesPerRow + x * 4
                        for channel in 0..<3 { sum[channel] += Double(pixels[offset + channel]) }
                        count += 1
                    }
                }
            }
            XCTAssertGreaterThan(count, 0)
            let rgb = sum.map { $0 / max(1, count) }
            print("LIVE GLOW \(button.identifier) \(theme): \(rgb)")
            switch theme {
            case "Orange": XCTAssertGreaterThan(rgb[0] - rgb[2], 1, "Orange glow must replace the previous purple glow")
            case "Light Blue": XCTAssertGreaterThan(rgb[2] - rgb[0], 1); XCTAssertGreaterThan(rgb[1] - rgb[0], 0.5)
            case "Neutral": XCTAssertLessThan(rgb.max()! - rgb.min()!, 2, "Neutral glow must not retain a colored cast")
            default: XCTAssertGreaterThan(rgb[2] - rgb[1], 1)
            }
        }
        for mode in ["Dark", "Light"] {
            for theme in ["Orange", "Light Blue", "Neutral", "Purple"] {
                let gear = app.buttons["notesListSettingsButton"]
                gear.tap()
                app.descendants(matching: .any)["settingsAppearanceModePicker"].firstMatch.tap()
                app.buttons[mode].tap()
                app.descendants(matching: .any)["settingsThemeColorPicker"].firstMatch.tap()
                app.buttons[theme].tap()
                app.buttons["settingsDoneButton"].tap()
                XCTAssertTrue(gear.waitForExistence(timeout: 5))
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Live floating glows - \(mode) - \(theme)"; shot.lifetime = .keepAlways; add(shot)
                try assertGlow(app.buttons["notesListNewNoteButton"].firstMatch, theme: theme)
                try assertGlow(gear, theme: theme)
                if !isPad { app.buttons.containing(.staticText, identifier: "Live theme controls").firstMatch.tap() }
                let ask = app.buttons["noteDetailSummaryAskAIButton"]
                XCTAssertTrue(ask.waitForExistence(timeout: 5))
                try assertGlow(ask, theme: theme)
                if !isPad { app.buttons["BackButton"].tap() }
            }
        }
    }

    @MainActor func testSettingsGlassAndAskAIReadability() throws {
        let isPad = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "").hasPrefix("iPad")
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-selectedThemeColor", "Purple", "-jotleyWelcomeCompleted.v1", "YES"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_CHAT_READY"] = "1"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Readable Ask AI controls","folder":"Work","tags":[],"transcript":"The team will review the launch on Friday.","summary":"## Summary\nThe team has a clear plan for Friday."}]
        """#
        for mode in ["Dark", "Light"] {
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = mode
            app.launch()
            XCTAssertTrue(app.buttons["noteDetailSummaryTab"].waitForExistence(timeout: 15))
            if !isPad { app.buttons["BackButton"].tap() }
            let gear = app.buttons["notesListSettingsButton"]
            XCTAssertTrue(gear.waitForExistence(timeout: 5)); XCTAssertTrue(gear.isHittable)
            XCTAssertEqual(gear.frame.width, 44, accuracy: 1); XCTAssertEqual(gear.frame.height, 44, accuracy: 1)
            let gearShot = XCTAttachment(screenshot: app.screenshot())
            gearShot.name = "Settings glass - \(mode)"; gearShot.lifetime = .keepAlways; add(gearShot)
            gear.tap()
            let settingsDone = app.buttons["settingsDoneButton"]
            XCTAssertTrue(settingsDone.waitForExistence(timeout: 5)); settingsDone.tap()
            if !isPad { app.buttons.containing(.staticText, identifier: "Readable Ask AI controls").firstMatch.tap() }
            let ask = app.buttons["noteDetailSummaryAskAIButton"]
            XCTAssertTrue(ask.waitForExistence(timeout: 5)); ask.tap()
            let done = app.buttons["askAIDoneButton"]
            XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isEnabled)
            for identifier in ["askAICopyConversationButton", "askAIShareConversationButton", "askAIClearButton"] {
                let button = app.buttons[identifier]
                XCTAssertTrue(button.exists); XCTAssertFalse(button.isEnabled, "An empty conversation action must stay disabled")
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            }
            let chatShot = XCTAttachment(screenshot: app.screenshot())
            chatShot.name = "Ask AI contrast - \(mode)"; chatShot.lifetime = .keepAlways; add(chatShot)
            done.tap()
        }
    }

    @MainActor func testMarketingChatCaptureAndControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_CHAT_READY"] = "1"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"[{"title":"Friday Launch Plan","folder":"Work","tags":["Design","Planning","Product"],"transcript":"Alex will finish accessibility checks Thursday. Sam will share the launch checklist. Maya leads the review Friday at 10:00.","summary":"The team agreed on a focused Friday launch.","messages":[{"role":"user","content":"Who is doing what before Friday?"},{"role":"assistant","content":"- **Alex:** finish the accessibility checks by Thursday.\n- **Sam:** share the launch checklist and gather feedback.\n- **Maya:** lead the final review on Friday at 10:00."}]}]"#
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchArguments = ["-selectedThemeColor", "Purple", "-jotleyWelcomeCompleted.v1", "YES"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let ask = app.buttons["noteDetailSummaryAskAIButton"]
        XCTAssertTrue(ask.waitForExistence(timeout: 15)); ask.tap()
        let done = app.buttons["askAIDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["askAICopyConversationButton"].isEnabled)
        XCTAssertTrue(app.buttons["askAIShareConversationButton"].isEnabled)
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let shot = XCTAttachment(screenshot: screen.screenshot())
            shot.name = "Marketing-chat-screen-\(index)"; shot.lifetime = .keepAlways; add(shot)
        }
        app.buttons["askAICopyConversationButton"].tap()
        app.buttons["askAIClearButton"].tap()
        XCTAssertTrue(app.buttons["askAIClearCancelButton"].waitForExistence(timeout: 5))
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let shot = XCTAttachment(screenshot: screen.screenshot())
            shot.name = "Local-clear-confirmation-screen-\(index)"; shot.lifetime = .keepAlways; add(shot)
        }
        app.buttons["askAIClearCancelButton"].tap()
        XCTAssertTrue(app.buttons["askAICopyConversationButton"].isEnabled)
        done.tap(); XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap(); XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    }

    // BEGIN LOCAL MARKETING CAPTURE
    @MainActor func testMarketingLiveWaveformCapture() throws {
        guard let levels = ProcessInfo.processInfo.environment["JOTLEY_MARKETING_AUDIO_LEVELS"] else {
            throw XCTSkip("Marketing waveform capture requires measured speech PCM peaks")
        }
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = "[]"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launchEnvironment["JOTLEY_SCREENSHOT_AUDIO_LEVELS"] = levels
        app.launchEnvironment["JOTLEY_SCREENSHOT_LIVE_TEXT"] = "Let’s keep Friday’s launch focused. One clear welcome, readable notes and a final review. Alex will finish the accessibility checks by Thursday. Sam will share the launch checklist."
        app.launchArguments = ["-selectedThemeColor", "Purple", "-jotleyWelcomeCompleted.v1", "YES", "-jotley.summaryDisplayStyle", "cards"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let start = app.buttons["notesListNewNoteButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        XCTAssertTrue(app.buttons["transcriptionPauseButton"].waitForExistence(timeout: 10))
        let waveform = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Live microphone waveform")).firstMatch
        XCTAssertTrue(waveform.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3.5) // Fill the native bar history with measured speech peaks.
        let first = waveform.screenshot().pngRepresentation
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let image = XCTAttachment(screenshot: screen.screenshot())
            image.name = "Marketing-live-waveform-a-screen-\(index)"; image.lifetime = .keepAlways; add(image)
        }
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertNotEqual(first, waveform.screenshot().pngRepresentation, "Measured speech must move the native waveform, not leave a flat line")
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let image = XCTAttachment(screenshot: screen.screenshot())
            image.name = "Marketing-live-waveform-b-screen-\(index)"; image.lifetime = .keepAlways; add(image)
        }
        app.buttons["transcriptionStopButton"].tap()
        app.terminate()
    }

    @MainActor func testMarketingLayoutCaptures() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_CHAT_READY"] = "1"
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ###"""
[
  {
    "title": "Friday Launch Plan",
    "folder": "Work",
    "tags": [
      "Design",
      "Product",
      "Planning"
    ],
    "transcript": "Maya: Let’s keep Friday’s launch focused. The new welcome flow should show people how to start a transcription, find a summary and ask their notes a question.\n\nAlex: I’ll finish the accessibility checks by Thursday afternoon. We should test the compact layout as carefully as the larger one.\n\nSam: I’ll share the launch checklist and gather feedback from the team. Let’s review the final screenshots tomorrow.\n\nMaya: Agreed. We’ll meet Friday at ten, review the remaining questions and make the launch decision together.",
    "summary": "## Summary\nThe team agreed on a focused Friday launch, with clear onboarding, readable notes and a final accessibility review.\n\n## Key Points\n- Keep the welcome flow simple and useful.\n- Check both compact and larger layouts.\n- Review the final screenshots before launch.\n\n## Decisions\n- Meet Friday at 10:00 for the final launch review.\n\n## Action Items\n- Alex: finish accessibility checks by Thursday.\n- Sam: share the launch checklist and gather feedback.\n- Maya: lead the final review on Friday.",
    "timestampOffset": -3600,
    "messages": [
      {
        "role": "user",
        "content": "Who is doing what before Friday?"
      },
      {
        "role": "assistant",
        "content": "- **Alex:** finish the accessibility checks by Thursday.\n- **Sam:** share the launch checklist and gather feedback.\n- **Maya:** lead the final review on Friday at 10:00."
      }
    ]
  },
  {
    "title": "Lecture: Working Memory",
    "folder": "Study",
    "tags": [
      "Learning",
      "Psychology"
    ],
    "transcript": "Working memory holds information while we use it. Focus on one task, group related ideas and test recall without looking at your notes. Space your study sessions over several days.",
    "summary": "## Summary\nAttention and recall improve when study sessions focus on one task at a time.\n\n## Key Points\n- Group related ideas.\n- Explain concepts in your own words.\n- Review over several days.",
    "timestampOffset": -7200
  },
  {
    "title": "Ideas for the Weekend",
    "folder": "Personal",
    "tags": [
      "Ideas"
    ],
    "transcript": "Walk the river trail. Try a new recipe. Make time for a conversation with friends. Leave the rest of the afternoon open.",
    "summary": "## Summary\nA little time outside, something new to try and room for the people who matter.",
    "timestampOffset": -90000
  },
  {
    "title": "Design Review: A Clearer First Step",
    "folder": "Work",
    "tags": [
      "Design",
      "Research"
    ],
    "transcript": "The first screen should make the next step obvious. We agreed to simplify the labels, keep the primary action visible and check the contrast in light and dark mode.",
    "summary": "## Summary\nA clearer first step helps people start with confidence.\n\n## Key Points\n- Use short, familiar labels.\n- Keep the primary action visible.\n- Check contrast in both appearances.",
    "timestampOffset": -172800
  },
  {
    "title": "Book Club: Small Habits",
    "folder": "Personal",
    "tags": [
      "Reading",
      "Ideas"
    ],
    "transcript": "Make the habit small enough to start on a busy day. Keep the book where you will see it. Five pages each evening is a better starting point than a perfect plan.",
    "summary": "## Summary\nSmall, repeatable habits make room for more reading.\n\n## Action Items\n- Leave the next book beside the reading chair.\n- Read five pages each evening.",
    "timestampOffset": -180000
  },
  {
    "title": "Lecture: How We Learn",
    "folder": "Study",
    "tags": [
      "Learning"
    ],
    "transcript": "Practice remembering an idea before checking the answer. Mix short recall sessions with time between reviews. Explain the concept in your own words to spot what is still unclear.",
    "summary": "## Summary\nRecall, spacing and explanation help ideas stay useful.\n\n## Key Points\n- Try recall before rereading.\n- Leave time between reviews.\n- Explain the concept in your own words.",
    "timestampOffset": -259200
  },
  {
    "title": "Garden Plans for Spring",
    "folder": "Personal",
    "tags": [
      "Home",
      "Ideas"
    ],
    "transcript": "Grow herbs near the kitchen window and start tomatoes when the weather warms. Check which planters get the most sunlight. Keep the first season simple.",
    "summary": "## Summary\nStart a small garden with useful herbs and a sunny spot for tomatoes.",
    "timestampOffset": -345600
  }
]
"""###
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "0"
        app.launchEnvironment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] = "1"
        app.launchEnvironment["JOTLEY_SCREENSHOT_LIVE_TEXT"] = "Let’s keep Friday’s launch focused. One clear welcome, readable notes and a final review. Alex will finish the accessibility checks by Thursday. Sam will share the launch checklist."
        func launch(_ theme: String = "Purple", _ appearance: String = "Light") {
            app.terminate()
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = appearance
            app.launchArguments = ["-selectedThemeColor", theme, "-jotleyWelcomeCompleted.v1", "YES", "-jotley.summaryDisplayStyle", "cards"]
            app.launch()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 20))
        }
        func capture(_ name: String) {
            Thread.sleep(forTimeInterval: 0.4) // Capture the settled segmented-control animation.
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let image = XCTAttachment(screenshot: screen.screenshot())
                image.name = "Marketing-\(name)-screen-\(index)"; image.lifetime = .keepAlways; add(image)
            }
        }
        func library() {
            let settings = app.buttons["notesListSettingsButton"]
            if settings.exists && settings.isHittable { return }
            let back = app.buttons["BackButton"]
            if back.exists && back.isHittable { back.tap() }
            else {
                let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
                XCTAssertTrue(sidebar.waitForExistence(timeout: 5)); sidebar.tap()
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
        }
        XCUIDevice.shared.orientation = .portrait
        if ProcessInfo.processInfo.environment["JOTLEY_CAPTURE_NEUTRAL_ONLY"] == "1" {
            launch("Neutral"); capture("neutral")
            library(); capture("neutral-library")
            launch("Neutral", "Dark"); capture("neutral-dark")
            app.terminate()
            return
        }
        launch()
        capture("summary")
        app.scrollViews.firstMatch.swipeUp(); capture("actions")
        launch(); app.buttons["noteDetailTranscriptTab"].tap(); capture("transcript")
        if XCUIScreen.screens.count > 1 {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.buttons["noteDetailTranscriptTab"].waitForExistence(timeout: 5)); capture("landscape-transcript")
            app.buttons["noteDetailSummaryTab"].tap(); capture("landscape-summary")
            XCUIDevice.shared.orientation = .portrait
        }
        launch(); app.buttons["noteDetailSummaryAskAIButton"].tap()
        XCTAssertTrue(app.buttons["askAIDoneButton"].waitForExistence(timeout: 10)); capture("chat")
        app.buttons["askAIDoneButton"].tap(); library(); capture("library")
        app.buttons["notesListFolderDrawerButton"].tap()
        XCTAssertTrue(app.buttons["folderDrawerDoneButton"].waitForExistence(timeout: 5)); capture("folders")
        launch("Orange"); capture("orange")
        launch("Light Blue"); capture("blue")
        launch("Purple", "Dark"); capture("dark")
        launch("Neutral"); capture("neutral")
        launch("Neutral", "Dark"); capture("neutral-dark")
        launch(); app.buttons["notesListNewNoteButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["transcriptionPauseButton"].waitForExistence(timeout: 10)); capture("live")
        app.buttons["transcriptionStopButton"].tap()
        app.terminate()
        app.launchEnvironment["JOTLEY_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "USA"
        app.launchArguments = ["-selectedThemeColor", "Purple"]
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 15)); capture("onboarding")
        app.buttons["onboardingContinue"].tap()
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.staticTexts["onboardingLanguageHint"].waitForExistence(timeout: 60)); capture("language")
        app.terminate()
    }
    // END LOCAL MARKETING CAPTURE

    @MainActor func testAppStoreScreenshots() throws {
        let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        guard (identifier.hasPrefix("iPhone18,") || identifier.hasPrefix("iPhone19,")) || identifier.hasPrefix("iPad17,") else { throw XCTSkip("Use an eligible iPhone or iPad screenshot simulator") }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
[{"title":"Weekly Design Review","folder":"Work","tags":["meeting","design"],"transcript":"Let\u2019s focus on making the first transcription feel simple. We agreed to keep one clear transcription action and show the transcript as the conversation unfolds. The team liked the side-by-side note list on iPad because it makes it easy to compare meeting notes.\n\nFor the next check-in, Maya will test the transcription flow, Alex will review the summary templates, and Sam will organize feedback into a shared checklist. We\u2019ll keep the first release focused on reliable transcription, readable notes, and clear next steps.\n\nOur next review is Friday at ten. Bring one example of a useful meeting summary and one thing that could feel simpler.","summary":"## Key Decisions\n- Keep live transcription simple and show the live transcript.\n- Use the iPad split view to browse notes side by side.\n\n## Next Steps\n- Maya: test the transcription flow.\n- Alex: review the summary templates.\n- Sam: organize the feedback checklist.\n\n## Next Check-in\nFriday at 10:00. Bring one useful summary and one idea to simplify the experience."},{"title":"Lecture: Working Memory","folder":"Study","tags":["lecture","psychology"],"transcript":"Working memory helps us hold information briefly while we use it. Attention is limited, so splitting our focus between too many tasks makes learning harder. We can reduce that load by grouping related ideas and writing down the next step.\n\nFor the study session, explain each concept in your own words, connect it to something you already know, and test yourself without looking at the notes. Space the next review over several days rather than doing everything at once.","summary":"## Main Ideas\n- Working memory holds information while we use it.\n- Focus on one task to reduce mental load.\n- Group related ideas and write down the next step.\n\n## Study Plan\nExplain the ideas in your own words, test recall without notes, and space reviews across several days."},{"title":"Garden Plans for Spring","folder":"Personal","tags":["ideas"],"transcript":"Start with herbs by the kitchen window, then plant tomatoes where they get the most sun. Keep a small notebook for watering, planting dates, and what works well. This weekend, measure the raised bed and make a short seed list.","summary":"## Spring Garden\n- Grow herbs near the kitchen window.\n- Plant tomatoes in the sunniest spot.\n- Track watering and planting dates.\n\n## This Weekend\nMeasure the raised bed and choose seeds."},{"title":"Weekend Ideas","folder":"Personal","tags":["ideas"],"transcript":"Walk the river trail.\nTry a new recipe.\nSketch a few ideas for the garden.\nLeave some time open.","summary":""}]
"""#
        func launch(_ appearance: String) {
            app.terminate()
            app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = appearance
            app.launch()
            XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
            XCTAssertLessThanOrEqual(app.textFields["notesListSearchField"].frame.height, 45)
        }
        func capture(_ name: String) {
            XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = name; image.lifetime = .keepAlways; add(image)
        }
        func openMeeting() {
            let row = app.buttons.containing(.staticText, identifier: "Weekly Design Review").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
            row.tap()
            XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 5))
        }
        launch("Dark")
        openMeeting()
        XCTAssertTrue(app.buttons["Summary"].waitForExistence(timeout: 5))
        capture("01-summary-dark")
        app.buttons["noteDetailMoreActionsButton"].tap()
        app.buttons["noteDetailSummaryTemplateMenu"].tap()
        app.buttons["Auto"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists,
                      "Template choice must keep the rendered summary visible")
        XCTAssertFalse(app.buttons["noteDetailGenerateSummaryButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists)
        launch("Light")
        openMeeting()
        app.buttons["Transcript"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailTranscriptContent"].waitForExistence(timeout: 5))
        capture("02-transcript-light")
        launch("Light")
        capture("03-notes-light")
        launch("Dark")
        app.buttons["notesListFolderDrawerButton"].tap()
        XCTAssertTrue(app.buttons["folderDrawerManageButton"].waitForExistence(timeout: 5))
        capture("04-folders-dark")
        launch("Dark")
        app.buttons["notesListNewNoteButton"].tap()
        stopNewTranscriptionAndOpenNote(app)
        capture("05-new-note-dark")
        app.terminate()
    }

}
