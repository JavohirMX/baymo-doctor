import XCTest

final class dr_dashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyClinicWithoutDemoArgument() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-realClinic",
            "-clinicStoreName", "uitest-empty-\(UUID().uuidString)",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()
        app.activate()

        let title = app.staticTexts["All patients"]
        let sidebar = app.descendants(matching: .any)["sidebar.allPatients"]
        let appeared = title.waitForExistence(timeout: 8) || sidebar.waitForExistence(timeout: 2)
        if !appeared {
            XCTFail("Clinic window did not show All patients.\n\(app.debugDescription)")
            return
        }
        let empty = app.descendants(matching: .any)["clinic.empty"]
        let showsEmpty = empty.waitForExistence(timeout: 6)
            || app.staticTexts["No patients yet"].waitForExistence(timeout: 2)
            || app.staticTexts["0 children"].exists
        XCTAssertTrue(showsEmpty)
        XCTAssertFalse(app.descendants(matching: .any)["patient.Rizky"].exists)
        XCTAssertFalse(app.staticTexts["Demo clinic"].exists)
    }

    @MainActor
    func testDemoClinicOpensRizkyRecording() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoClinic",
            "-clinicStoreName", "uitest-demo-\(UUID().uuidString)",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()

        let rizky = app.descendants(matching: .any)["patient.Rizky"]
        XCTAssertTrue(rizky.waitForExistence(timeout: 15))
        rizky.click()
        let opened = app.buttons["Edit"].waitForExistence(timeout: 4)
            || app.buttons["Timeline"].waitForExistence(timeout: 2)
            || app.staticTexts["Timeline"].waitForExistence(timeout: 2)
        if !opened {
            rizky.doubleClick()
        }
        XCTAssertTrue(
            app.buttons["Edit"].waitForExistence(timeout: 5)
                || app.staticTexts["Recording schedule"].waitForExistence(timeout: 2)
        )

        openChangeRecording(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["ecg.viewer"].waitForExistence(timeout: 8))
        let showsMeasurement = app.buttons["ecg.markReviewed"].waitForExistence(timeout: 8)
            || app.staticTexts["Heart rate (bpm)"].exists
            || app.staticTexts["QRS (ms)"].exists
            || app.descendants(matching: .any)["ecg.measurements"].exists
        XCTAssertTrue(showsMeasurement)
    }

    @MainActor
    private func openChangeRecording(in app: XCUIApplication) {
        let timeline = app.descendants(matching: .any)["timeline.change"]
        if clickIfHittable(timeline, timeout: 2) { return }

        if app.buttons["ECGs"].waitForExistence(timeout: 2) {
            app.buttons["ECGs"].click()
        } else if app.staticTexts["ECGs"].exists {
            app.staticTexts["ECGs"].firstMatch.click()
        }

        let row = app.descendants(matching: .any)["ecg.row.change"]
        if clickIfHittable(row, timeout: 3) { return }

        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if clickIfHittable(timeline, timeout: 0.2) { return }
            if clickIfHittable(row, timeout: 0.2) { return }
            if scroll.exists {
                scroll.scroll(byDeltaX: 0, deltaY: -350)
            }
        }
        XCTFail("Could not open the 8 Nov change recording")
    }

    @MainActor
    private func clickIfHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.click()
        return true
    }
}
