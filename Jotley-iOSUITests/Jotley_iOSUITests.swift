import XCTest
import UIKit
#if DEBUG
import FoundationModels
import Speech
#endif

final class Jotley_iOSUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Tag replacement").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.staticTexts["Outdated-1"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
            app.buttons["noteDetailGenerateSummaryButton"].tap()
            XCTAssertTrue(app.staticTexts["AI"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Design"].exists)
            for old in oldTags { XCTAssertFalse(app.staticTexts[old].exists, "Old tags must disappear without reopening the note") }
            XCTAssertFalse(app.staticTexts["Overflow"].exists)
            for tag in ["AI", "Design", "Research", "Planning", "Meetings"] {
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", tag)).count, 1)
            }
            XCTAssertTrue(app.buttons["noteDetailGenerateSummaryButton"].waitForExistence(timeout: 5))
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
            for theme in ["Purple", "Magenta", "Orange", "Yellow", "Light Blue"] {
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
                if theme == "Magenta" {
                    let attachment = XCTAttachment(screenshot: app.screenshot())
                    attachment.name = "Neutral glass Done with Magenta theme - \(mode)"
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
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notesListNoteRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        app.buttons["noteDetailGenerateSummaryButton"].tap()
        let cancel = app.buttons["noteDetailCancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); XCTAssertTrue(cancel.isHittable)
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
        XCTAssertTrue(app.buttons["noteDetailGenerateSummaryButton"].isEnabled)
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
        app.buttons["noteDetailGenerateSummaryButton"].tap()
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
            XCTAssertTrue(app.buttons["noteDetailTemplatesButton"].exists)
            XCTAssertEqual(app.buttons["noteDetailGenerateSummaryButton"].label, "Regenerate Summary")
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
        XCTAssertGreaterThan(viewport.frame.height, 100)
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
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["noteDetailTranscribeAudioButton"].exists)
        app.buttons["noteDetailMoreActionsButton"].tap()
        XCTAssertTrue(app.buttons["noteDetailContinueTranscriptionMenuButton"].exists)
        XCTAssertFalse(app.buttons["noteDetailPlayRecordingButton"].exists)
        XCTAssertFalse(app.buttons["retrySavedAudioButton"].exists)
    }


    @MainActor func testSpeechSettingsExplainUnsupportedLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "zxx"]
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
        let app = XCUIApplication(); app.launch()
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
        let app = XCUIApplication(); app.launch()
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
        let app = XCUIApplication(); app.launch()
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
            app.buttons["Close"].tap()
        } else {
            XCTAssertEqual(pause.label, "Pause transcription")
            app.buttons["transcriptionStopButton"].tap()
        }
        if app.alerts["Jotley"].waitForExistence(timeout: 3) { app.alerts["Jotley"].buttons["OK"].tap() }
        XCTAssertTrue(app.staticTexts["noteDetailTitle"].waitForExistence(timeout: 20))
    }


    @MainActor func testLiveOnlyNoteKeepsTemplatesAndContinueActionWithoutAudioControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-transcriptionLanguage", "zxx"]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = ##"[{"title":"Live transcript","folder":"","tags":[],"transcript":"Mina ships Friday.","summary":""}]"##
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
        let failure = app.alerts["Transcription Needs Attention"]
        XCTAssertTrue(failure.waitForExistence(timeout: 15)); failure.buttons["OK"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Mina ships Friday."].waitForExistence(timeout: 10))
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
        let app = XCUIApplication(); app.launch()
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
        XCTAssertFalse(app.otherElements["ActivityListView"].exists)
        share.tap()
        let textShare = app.buttons["shareNoteButton"]
        XCTAssertTrue(textShare.waitForExistence(timeout: 5)); textShare.tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(close.exists); close.tap()
        XCTAssertFalse(app.otherElements["ActivityListView"].exists)
    }

    #if DEBUG

    @MainActor private func openRatingsCardFromSettings(_ app: XCUIApplication) {
        let settings = app.buttons["notesListSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let openCard = app.buttons["settingsSupportJotleyCard"]
        for _ in 0..<8 where !openCard.isHittable { app.swipeUp() }
        XCTAssertTrue(app.descendants(matching: .any)["settingsRateJotley"].firstMatch.exists)
        XCTAssertTrue(openCard.isHittable, app.debugDescription); openCard.tap()
        XCTAssertTrue(app.staticTexts["jotleySupportTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground, "Opening the card must not activate another Settings link")
    }

    @MainActor func testRatingsCardOpensFromSettingsAndStaysAvailableAfterRelaunch() throws {
        let app = XCUIApplication()
        let fixture: [[String: Any]] = [["title": "Support verification", "folder": "Work", "tags": [], "transcript": "Locally recorded words", "summary": "# Summary\nLocal notes stay private."]]
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "6"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "USA"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Dark"
        app.launch()
        XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].waitForExistence(timeout: 3), "The review menu must be user-opened, not an automatic custom review prompt")
        openRatingsCardFromSettings(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "free for personal and paid work")).firstMatch.exists)
        XCTAssertTrue(app.buttons["jotleySupportShare"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["jotleySupportFeedback"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["jotleySupportTitle"].label.contains("Supported by people."))
        XCTAssertTrue(app.staticTexts["Support is optional. All features stay free."].exists)
        XCTAssertTrue(app.staticTexts["Optional · jotley.ai/tips"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["jotleyStyledSupportPrompt"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Support must use the app's themed card rather than a system alert")
        XCTAssertTrue(app.descendants(matching: .any)["jotleySupportTip"].firstMatch.waitForExistence(timeout: 5))
        let card = app.descendants(matching: .any)["jotleyStyledSupportPrompt"].firstMatch
        XCTAssertLessThan(card.frame.height, app.frame.height * 0.85, "The normal-size support card should leave the app visible")
        XCTAssertGreaterThanOrEqual(app.buttons["jotleySupportShare"].frame.height, 58)
        XCTAssertEqual(app.staticTexts["jotleySupportTitle"].frame.minX,
                       app.staticTexts["Support is optional. All features stay free."].frame.minX,
                       accuracy: 2, "The heading and footer should share a leading edge")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Protomota Software")).firstMatch.exists)
        XCTAssertFalse(app.buttons["settingsSupportJotleyCard"].isHittable, "The modal must prevent interaction with underlying actions")
        let dismissButton = app.buttons["jotleySupportDismiss"]
        XCTAssertTrue(dismissButton.isHittable)
        XCTAssertGreaterThanOrEqual(dismissButton.frame.height, 44)
        let feedbackRow = app.descendants(matching: .any)["jotleySupportFeedback"].firstMatch
        XCTAssertTrue(feedbackRow.isHittable)
        XCTAssertLessThanOrEqual(feedbackRow.frame.maxY,
                                 app.staticTexts["Support is optional. All features stay free."].frame.minY - 12,
                                 "All four actions must fit above the pinned footer at normal text size")
        XCTAssertLessThanOrEqual(dismissButton.frame.maxY, app.frame.maxY - 12, "Dismissal must remain fully visible above the screen edge")
        let reviewRow = app.descendants(matching: .any)["jotleySupportReview"].firstMatch
        let tipRow = app.descendants(matching: .any)["jotleySupportTip"].firstMatch
        let shareRow = app.buttons["jotleySupportShare"]
        XCTAssertTrue(reviewRow.isHittable)
        XCTAssertGreaterThanOrEqual(reviewRow.frame.height, 74)
        XCTAssertLessThan(reviewRow.frame.minY, tipRow.frame.minY)
        XCTAssertLessThan(tipRow.frame.minY, shareRow.frame.minY)
        XCTAssertLessThan(shareRow.frame.minY, feedbackRow.frame.minY)
        XCTAssertGreaterThan(reviewRow.frame.height, tipRow.frame.height)
        XCTAssertEqual(reviewRow.label, "Rate and review Jotley on the App Store")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Your rating and review help others discover Jotley")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "First-time Jotley support message"
        attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["jotleySupportDismiss"].tap()
        XCTAssertTrue(app.buttons["settingsSupportJotleyCard"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "JOTLEY_TEST_ENGAGEMENT_COUNT")
        app.launch()
        XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].waitForExistence(timeout: 3))
        openRatingsCardFromSettings(app)
        XCTAssertTrue(app.descendants(matching: .any)["jotleySupportReview"].firstMatch.isHittable)
        app.buttons["jotleySupportClose"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsRateJotley"].firstMatch.exists)
    }
    @MainActor func testRestrictedStorefrontKeepsStyledSupportWithoutWebTips() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOTLEY_SCREENSHOT_DATA"] = #"""
        [{"title":"Regional support verification","folder":"Work","tags":[],"transcript":"Local transcript","summary":""}]
        """#
        app.launchEnvironment["JOTLEY_TEST_ENGAGEMENT_COUNT"] = "6"
        app.launchEnvironment["JOTLEY_TEST_STOREFRONT"] = "GBR"
        app.launchEnvironment["JOTLEY_SCREENSHOT_APPEARANCE"] = "Light"
        app.launch()
        XCTAssertTrue(app.buttons["notesListNewNoteButton"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].waitForExistence(timeout: 3), "The review menu must be user-opened, not an automatic custom review prompt")
        openRatingsCardFromSettings(app)
        XCTAssertTrue(app.buttons["jotleySupportShare"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["jotleySupportTip"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Optional tips")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["jotleySupportFeedback"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Styled support in a restricted storefront"
        attachment.lifetime = .keepAlways; add(attachment)
        let reviewRow = app.descendants(matching: .any)["jotleySupportReview"].firstMatch
        XCTAssertTrue(reviewRow.isHittable)
        XCTAssertLessThan(reviewRow.frame.minY, app.buttons["jotleySupportShare"].frame.minY)
        XCTAssertEqual(reviewRow.label, "Rate and review Jotley on the App Store")
        app.buttons["jotleySupportClose"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsRateJotley"].firstMatch.exists)
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
        let finished = expectation(for: NSPredicate(format: "enabled == YES AND label == %@", "Regenerate Summary"), evaluatedWith: generate)
        wait(for: [finished], timeout: 60)
        XCTAssertFalse(app.staticTexts["jotleySupportTitle"].waitForExistence(timeout: 3), "The sixth saved action must not trigger a custom review prompt")
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists)
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
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Long template verification").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.staticTexts["Long recording summary"].waitForExistence(timeout: 5))
        let templates = app.buttons["noteDetailTemplatesButton"]
        let templateFrame = templates.frame
        let summaryFrame = app.buttons["noteDetailGenerateSummaryButton"].frame
        for (key, title) in [("lecture", "Lecture"), ("meetings/general", "General Meeting"), ("default-summary", "Auto"), ("lecture", "Lecture")] {
            templates.tap()
            let choice = app.buttons["noteTemplate-\(key)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            let start = Date(); choice.tap()
            let updated = expectation(for: NSPredicate(format: "label == %@", "Templates: " + title), evaluatedWith: templates)
            wait(for: [updated], timeout: 5)
            for (actual, expected) in [(templates.frame, templateFrame), (app.buttons["noteDetailGenerateSummaryButton"].frame, summaryFrame)] {
                XCTAssertEqual(actual.width, expected.width, accuracy: 0.5)
                XCTAssertEqual(actual.height, expected.height, accuracy: 0.5)
                XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5)
                XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5)
            }
            print("Long-note template selection \(title): \(Date().timeIntervalSince(start))s")
            XCTAssertTrue(app.staticTexts["Long recording summary"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["markdownListItem-1"].firstMatch.exists)
            XCTAssertFalse(app.textViews.firstMatch.exists, "Template selection must not enter editing")
            XCTAssertEqual(app.buttons["noteDetailGenerateSummaryButton"].label, "Regenerate Summary")
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
        templates.tap(); app.buttons["noteTemplate-meetings/general"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists,
                      "Changing templates keeps the rendered summary open")
        generate.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists, "Regenerate starts without a confirmation")
        let finished = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: generate)
        wait(for: [finished], timeout: 60)
        XCTAssertEqual(templates.label, "Templates: General Meeting")
        XCTAssertEqual(title.label, generatedTitle, "Regeneration preserves the generated title")
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        let summary = XCTAttachment(screenshot: app.screenshot())
        summary.name = "Actual simulator summary title and template regeneration"; summary.lifetime = .keepAlways; add(summary)
    }
    #endif

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
        let templates = app.buttons["noteDetailTemplatesButton"]
        XCTAssertTrue(templates.exists && templates.isEnabled)
        templates.tap(); app.buttons["noteTemplate-default-summary"].tap()
        XCTAssertEqual(templates.label, "Templates: Auto")
        XCTAssertTrue(app.descendants(matching: .any)["noteDetailSummaryContent"].exists,
                      "Template choice must keep the rendered summary visible")
        let regenerate = app.buttons["noteDetailGenerateSummaryButton"]
        XCTAssertEqual(regenerate.label, "Regenerate Summary")
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
