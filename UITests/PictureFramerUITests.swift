import XCTest

/// End-to-end flow: pick a photo → editor with detected quad → corrected
/// preview → save to photo library → success screen. Runs against the real
/// photo picker and the real add-only permission alert.
final class PictureFramerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Shared flow: launch, pick the newest photo, land in the editor.
    /// Returns the app. `resettingPhotosPermission` restores the photos
    /// permission to not-determined first (iOS 26 then auto-grants
    /// add-only saves without a prompt).
    @MainActor
    private func launchAndPickNewestPhoto(resettingPhotosPermission: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if resettingPhotosPermission {
            app.resetAuthorizationStatus(for: .photos)
        }
        app.launch()
        app.buttons["Choose Photo"].tap()

        // The PhotosPicker is remote content but its grid cells are exposed
        // to XCUITest as images labelled "Photo, <date>", newest first. Tap
        // the seeded painting (added moments ago → newest).
        let newestPhoto = app.images
            .matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'"))
            .firstMatch
        XCTAssertTrue(newestPhoto.waitForExistence(timeout: 15), "photo picker grid did not appear")
        // A first-run onboarding banner can cover the grid.
        let closeOnboarding = app.buttons["Close"]
        if closeOnboarding.waitForExistence(timeout: 2) {
            closeOnboarding.tap()
        }
        // Coordinate tap skips the hittability check, which stays false
        // while picker thumbnails stream in.
        newestPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return app
    }

    @MainActor
    func testPickStraightenAndSaveFlow() throws {
        let app = launchAndPickNewestPhoto()

        // Editor appears once loading + detection finish.
        let saveButton = app.buttons["Save to Photos"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 30), "editor did not appear")

        // Nudge a corner handle in Adjust mode (exercises the
        // display→pixel mapping and quad clamping).
        let topLeftHandle = app.otherElements["Top left corner"].firstMatch.exists
            ? app.otherElements["Top left corner"].firstMatch
            : app.descendants(matching: .any)["Top left corner"].firstMatch
        if topLeftHandle.waitForExistence(timeout: 5) {
            topLeftHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: topLeftHandle.coordinate(
                    withNormalizedOffset: CGVector(dx: 1.5, dy: 1.5)
                ))
        }

        // Switch to the corrected preview and give the render a moment.
        app.buttons["Preview"].tap()
        Thread.sleep(forTimeInterval: 2)

        // Pan: drag the preview, Recenter appears; reset restores the hint.
        let preview = app.images.firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "corrected preview missing")
        XCTAssertTrue(app.staticTexts["Drag to pan image"].exists, "pan hint missing")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        let recenter = app.buttons["Recenter"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 10), "Recenter button did not appear after pan")
        recenter.tap()
        XCTAssertTrue(
            app.staticTexts["Drag to pan image"].waitForExistence(timeout: 10),
            "pan hint did not return after recentering"
        )
        Thread.sleep(forTimeInterval: 1)
        XCTContext.runActivity(named: "corrected preview") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        saveButton.tap()

        // First save triggers the add-only photos permission alert, which
        // belongs to springboard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }

        XCTAssertTrue(
            app.staticTexts["Saved to your photo library."].waitForExistence(timeout: 30),
            "success screen did not appear"
        )

        // Start over resets to the picker screen.
        app.buttons["Straighten Another"].tap()
        XCTAssertTrue(
            app.buttons["Choose Photo"].waitForExistence(timeout: 10),
            "picker screen did not return after reset"
        )
    }

    /// A revoked add-only permission must surface the error message and a
    /// Settings deep link — and keep the editor state intact.
    ///
    /// iOS 26 grants add-only saves without a prompt, so denial only
    /// happens via the Settings toggle. Revoke before running:
    ///   xcrun simctl privacy booted revoke photos-add com.corti.PictureFramer
    /// When the permission is (auto-)granted instead, the test skips.
    @MainActor
    func testRevokedPermissionShowsErrorAndSettingsLink() throws {
        // Phase 1: get the permission firmly denied. After a simctl revoke
        // iOS 26 re-prompts on the first save; deny it. iOS may kill the
        // app on the in-flight TCC change — that's fine, phase 2 relaunches.
        let app = launchAndPickNewestPhoto(resettingPhotosPermission: false)
        let saveButton = app.buttons["Save to Photos"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 30), "editor did not appear")
        saveButton.tap()

        // Granted permission (the common state) means no prompt and an
        // eventual success screen — check that FIRST and generously; a
        // cold-start full-res save can take several seconds. Only then
        // treat the situation as "prompt is on screen".
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let dontAllow = springboard.buttons["Don't Allow"]
        if app.staticTexts["Saved to your photo library."].waitForExistence(timeout: 20) {
            throw XCTSkip("photos-add permission granted — revoke via simctl to exercise the denial path")
        } else if dontAllow.waitForExistence(timeout: 5) {
            dontAllow.tap()
        } else {
            // The iOS 26 card-style permission prompt is not reachable via
            // accessibility queries on springboard or the app. Tap the
            // "Don't Allow" button's screen position directly (layout is
            // stable on the pinned iPhone 17 Pro destination).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.64)).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // Phase 2: fresh launch with the permission now denied — no
        // prompt; save must fail gracefully with message + Settings link.
        let relaunched = launchAndPickNewestPhoto(resettingPhotosPermission: false)
        let saveAgain = relaunched.buttons["Save to Photos"]
        XCTAssertTrue(saveAgain.waitForExistence(timeout: 30), "editor did not appear after relaunch")
        saveAgain.tap()

        XCTAssertTrue(
            relaunched.staticTexts["Allow photo access in Settings to save."].waitForExistence(timeout: 15),
            "denial error message did not appear"
        )
        let settingsLink = relaunched.links["Open Settings"].exists
            || relaunched.buttons["Open Settings"].exists
        XCTAssertTrue(settingsLink, "Settings deep link missing")
        // Editor still alive — user can adjust and retry.
        XCTAssertTrue(saveAgain.exists)
    }
}
