import XCTest

@MainActor
final class FoundationChatUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchApp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
    }

    func testCreatesChatAndShowsMobileComposer() {
        launchApp()

        XCTAssertTrue(
            app.staticTexts["Apple Intelligence · Local"].waitForExistence(timeout: 8)
        )

        app.buttons["Новый чат"].firstMatch.tap()

        XCTAssertTrue(app.textFields["mobile.composer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mobile.attachments"].exists)
        XCTAssertTrue(app.buttons["mobile.send"].exists)
        XCTAssertTrue(app.navigationBars["Новый чат"].exists)

        let attachmentFrame = app.buttons["mobile.attachments"].frame
        let sendFrame = app.buttons["mobile.send"].frame
        XCTAssertEqual(attachmentFrame.height, sendFrame.height, accuracy: 1)
        XCTAssertEqual(attachmentFrame.width, sendFrame.width, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "mobile-welcome-and-composer"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testOpensThreeSectionSettingsSheet() {
        launchApp()

        let settingsButton = app.buttons["Параметры"].firstMatch
        for _ in 0..<3 where !settingsButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Параметры"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ответ"].exists)
        XCTAssertTrue(app.buttons["Инструкции"].exists)
        XCTAssertTrue(app.buttons["Модель"].exists)

        app.buttons["Инструкции"].tap()
        XCTAssertTrue(app.buttons["Создать свой промпт"].waitForExistence(timeout: 3))

        app.buttons["Модель"].tap()
        XCTAssertTrue(app.staticTexts["Возможности"].waitForExistence(timeout: 3))
    }

    func testCreatesProjectFromMobileSidebar() {
        launchApp()

        let createProject = app.buttons.matching(
            NSPredicate(format: "label == 'Создать проект' OR label == 'Новый проект'")
        ).firstMatch
        XCTAssertTrue(createProject.waitForExistence(timeout: 5))
        createProject.tap()

        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        let projectName = "Мобильный проект"
        nameField.typeText(projectName)
        app.alerts.buttons["Создать"].tap()

        XCTAssertTrue(app.staticTexts[projectName].waitForExistence(timeout: 3))
    }

    func testLocalModelGeneratesResponse() {
        launchApp()

        app.buttons["Новый чат"].firstMatch.tap()

        let composer = app.textFields["mobile.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Ответь одним коротким словом.")

        let send = app.buttons["mobile.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["mobile.assistant.content"]
                .waitForExistence(timeout: 60)
        )
    }
}
