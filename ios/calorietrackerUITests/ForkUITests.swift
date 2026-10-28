import XCTest

/// UI tests for the fork's own screens, cards, menu entries and settings rows. Each test starts
/// a fresh UI-testing install and seeds only what it needs as launch-argument defaults (JSON
/// values go in as plist data literals), so no test depends on another.
final class ForkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func makeApp(_ defaults: [String: Any] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-reset", "--ui-testing-onboarded",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-WorkoutVectorsBaseURL", "none",
            "-didPromptReviewAfterFirstLog", "YES",
        ]
        for (key, value) in defaults.sorted(by: { $0.key < $1.key }) {
            app.launchArguments += ["-\(key)", Self.argument(value)]
        }
        app.launch()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 15))
        return app
    }

    /// A defaults launch argument: YES/NO, a number, a string, or JSON as a data literal.
    private static func argument(_ value: Any) -> String {
        switch value {
        case let flag as Bool: return flag ? "YES" : "NO"
        case let number as Int: return String(number)
        case let text as String: return text
        default:
            let data = try! JSONSerialization.data(withJSONObject: value)
            return "<" + data.map { String(format: "%02x", $0) }.joined() + ">"
        }
    }

    /// Seconds since 2001, as the app's JSON dates are stored.
    private static func stamp(daysAgo: Int = 0, hour: Int) -> Double {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!.timeIntervalSinceReferenceDate
    }

    private static func food(_ name: String, calories: Int, protein: Double = 5, daysAgo: Int = 0, hour: Int = 9) -> [String: Any] {
        ["id": UUID().uuidString, "name": name, "calories": calories, "protein": protein, "carbs": 20, "fat": 5,
         "timestamp": stamp(daysAgo: daysAgo, hour: hour), "source": "manual", "mealType": "snack"]
    }

    private static let allDay: [String: Any] = ["weekdays": [1, 2, 3, 4, 5, 6, 7], "startMinute": 0, "endMinute": 1439]

    private static func collection(_ name: String, items: [[String: Any]] = [], schedule: [String: Any]? = nil,
                                   kinds: [String]? = nil) -> [String: Any] {
        var collection: [String: Any] = ["id": UUID().uuidString, "name": name, "items": items]
        if let schedule { collection["schedule"] = schedule }
        if let kinds { collection["kinds"] = kinds }
        return collection
    }

    /// Scrolls until `element` sits fully inside the screen, clear of the status bar at the
    /// top and the tab bar and floating buttons at the bottom. Uses frames rather than
    /// `isHittable`, which fails outright for an element that is partly off screen.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        func onScreen() -> Bool {
            guard element.exists else { return false }
            let window = app.windows.firstMatch.frame
            let frame = element.frame
            guard !frame.isEmpty, window.contains(frame) else { return false }
            let clear = CGRect(x: window.minX, y: window.minY + 60, width: window.width, height: window.height - 60 - 190)
            // Fully inside the window, so asking for hittability is safe; it covers the last
            // rows of a list that cannot scroll any further.
            return clear.contains(frame) || element.isHittable
        }
        for _ in 0..<8 where !onScreen() { app.swipeUp(velocity: .slow) }
        for _ in 0..<8 where !onScreen() { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(onScreen(), "Not reachable: \(element)", file: file, line: line)
    }

    @MainActor
    private func open(_ method: String, in app: XCUIApplication) {
        app.open(URL(string: "fudai://log-food?method=\(method)")!)
    }

    /// Any element whose own label contains `fragment`; SwiftUI often merges a row's texts
    /// into one button or control, so plain static-text queries miss them.
    @MainActor
    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    @MainActor
    private func element(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    // MARK: - Health profile and Home cards

    @MainActor
    func testHealthSetupCardOpensTheProfileWithTastes() {
        let app = makeApp()
        let setUp = app.buttons["Set up"]
        reveal(setUp, in: app)
        setUp.tap()
        XCTAssertTrue(app.navigationBars["Health Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Conditions"].exists)
        let tastes = app.staticTexts["Tastes & treats"]
        reveal(tastes, in: app)
        tastes.tap()
        XCTAssertTrue(app.navigationBars["Tastes & Treats"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWaterSuggestionForGoutTurnsOnWaterTracking() {
        let app = makeApp(["fork.healthProfile": ["entries": ["gout"]]])
        let card = app.staticTexts["Track water?"]
        reveal(card, in: app)
        app.buttons["Track water"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        let water = app.staticTexts["Water"]
        reveal(water, in: app)
    }

    @MainActor
    func testTappingWaterShowsLoggedWaterAndCountedDrinks() {
        var coffee = Self.food("Cold brew", calories: 5, hour: 8)
        coffee["servingSizeGrams"] = 355
        var beer = Self.food("Beer", calories: 150, hour: 8)
        beer["servingSizeGrams"] = 355
        let water: [[String: Any]] = [["id": UUID().uuidString, "date": Self.stamp(hour: 7), "milliliters": 500]]
        let app = makeApp(["waterTrackingEnabled": true, "waterEntries": water, "foodEntries": [coffee, beer]])
        let bar = text(containing: "Water", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Water")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Water"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "855 ml of", in: app).exists)
        XCTAssertTrue(app.staticTexts["Cold brew"].exists)
        XCTAssertTrue(app.staticTexts["Alcohol doesn't count"].exists)
    }

    @MainActor
    func testDrinksInTheDiaryShowVolumeNotWeight() {
        var vitaminwater = Self.food("Vitaminwater", calories: 120, daysAgo: 0, hour: 9)
        vitaminwater["servingSizeGrams"] = 591
        var chicken = Self.food("Chicken breast", calories: 900, daysAgo: 0, hour: 9)
        chicken["servingSizeGrams"] = 591
        let app = makeApp(["fork.units.system": "us", "foodEntries": [vitaminwater, chicken]])
        let drink = text(containing: "20 fl oz", in: app)
        reveal(drink, in: app)
        XCTAssertTrue(text(containing: "1 lb 5 oz", in: app).exists, "Solid foods keep their weight")
    }

    @MainActor
    func testHomeBarsSayWhichWayIsGood() {
        let app = makeApp(["foodEntries": [Self.food("Toast", calories: 200, protein: 8)],
                           "fork.healthProfile": ["entries": ["gout"]]])
        // Protein is a target: "to go", not "left".
        XCTAssertTrue(text(containing: "g to go", in: app).waitForExistence(timeout: 5))
        // The gout card's purines are a limit: "left".
        let purines = text(containing: "mg left", in: app)
        reveal(purines, in: app)
    }

    @MainActor
    func testTreatCardAppearsAfterOnTrackDaysAndHidesForToday() {
        let treat: [String: Any] = Self.food("Salted caramel ice cream", calories: 280)
        let history = [Self.food("Lunch", calories: 1_600, daysAgo: 1, hour: 12), Self.food("Lunch", calories: 1_600, daysAgo: 2, hour: 12)]
        let app = makeApp(["foodEntries": history, "fork.foodTastes": ["treats": [treat]]])
        let card = app.staticTexts["Room for a treat"]
        reveal(card, in: app)
        XCTAssertTrue(app.staticTexts["Salted caramel ice cream"].exists)
        app.buttons["Not today"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCaloriesScreenExplainsTheGoalAndOffersExerciseOptions() {
        let app = makeApp()
        // The gauge reads as one button: "Calories, 0, 2,452 left".
        let calories = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Calories,")).firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        calories.tap()
        XCTAssertTrue(app.staticTexts["How your goal works"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Maintenance (estimated)"].exists)
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Calorie goal")).firstMatch
        reveal(picker, in: app)
        picker.tap()
        app.buttons["Add extra exercise"].firstMatch.tap()
        // The share control sits below the picker, often under the fold.
        reveal(app.buttons["50%"], in: app)
    }

    // MARK: - Collections and places

    @MainActor
    func testScheduledCollectionShowsOnHomeAndLogsInOneTap() {
        let app = makeApp(["fork.foodCollections": [Self.collection("Office snacks", items: [Self.food("Almonds", calories: 170)],
                                                                    schedule: Self.allDay)]])
        let card = app.staticTexts["Office snacks"]
        reveal(card, in: app)
        app.buttons["Log"].firstMatch.tap()
        XCTAssertTrue(app.images["Logged"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCollectionAddMenuOffersPhotoAndBarcodeAndPlaceSettings() {
        let app = makeApp(["fork.foodCollections": [Self.collection("Office snacks", items: [Self.food("Almonds", calories: 170)])]])
        open("collections", in: app)
        let row = app.staticTexts["Office snacks"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["Add Foods"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Take a photo of what's there"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose a photo"].exists)
        XCTAssertTrue(app.buttons["Scan a barcode"].exists)
        app.buttons["From Favorites, Frequent or Recent"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        let place = app.staticTexts["Place & Schedule"]
        reveal(place, in: app)
        place.tap()
        XCTAssertTrue(app.buttons["Use my current location"].waitForExistence(timeout: 5))
        // Tap the switch itself; a tap on the row's label does not flip it.
        app.switches["On a schedule"].switches.firstMatch.tap()
        XCTAssertTrue(text(containing: "From", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Until", in: app).exists)
    }

    @MainActor
    func testKindsOfPlaceCanBePickedIncludingOwnWords() {
        let app = makeApp(["fork.foodCollections": [Self.collection("Office")]])
        open("collections", in: app)
        let row = app.staticTexts["Office"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let add = app.staticTexts["Add a kind of place"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.navigationBars["What's Here"].waitForExistence(timeout: 5))
        app.staticTexts["Pizza place"].tap()
        let own = app.textFields["e.g. sushi counter, taco truck"]
        reveal(own, in: app)
        own.tap()
        own.typeText("Taco truck\n")
        app.navigationBars["What's Here"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Pizza place"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Taco truck"].exists)
    }

    @MainActor
    func testCoffeeBarOrderBecomesTheUsualOnHome() {
        let app = makeApp(["fork.foodCollections": [Self.collection("Office cafe", schedule: Self.allDay, kinds: ["coffeeBar"])]])
        let order = app.buttons["Order"]
        reveal(order, in: app)
        order.tap()
        XCTAssertTrue(app.navigationBars["Coffee Bar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sugar (total)"].exists)
        app.navigationBars["Coffee Bar"].buttons["Log"].tap()
        // Once a drink is logged, the card shows it as the usual with a way to order another.
        // The card is on screen when the sheet closes; wait rather than scroll, since a scroll
        // can leave the small text button under the floating buttons.
        XCTAssertTrue(app.navigationBars["Coffee Bar"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Your usual ·", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Order a different drink"].waitForExistence(timeout: 5))
    }

    // MARK: - Suggestions, tastes, menus

    @MainActor
    func testTastesScreenAddsALike() {
        let app = makeApp()
        open("suggestions", in: app)
        let tastes = app.staticTexts["Tastes & treats"]
        reveal(tastes, in: app)
        tastes.tap()
        let field = app.textFields["Add a like, e.g. salmon"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("salmon\n")
        XCTAssertTrue(app.staticTexts["salmon"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMenuImportAsksForWeekOrDayAndOffersTheCamera() {
        let app = makeApp()
        open("suggestions", in: app)
        let week = app.staticTexts["Week plan"]
        reveal(week, in: app)
        week.tap()
        app.navigationBars["Week Plan"].buttons["Add"].tap()
        app.buttons["Import a menu"].tap()
        XCTAssertTrue(app.navigationBars["Import a Menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Take a photo of the menu"].exists)
        app.buttons["One day"].tap()
        XCTAssertTrue(element(labeled: "Day", in: app).waitForExistence(timeout: 5))
    }

    // MARK: - Coach

    @MainActor
    func testCoachRepliesOfferFoodsToLogAndTheAddMenuHasFromCoach() {
        let chat: [[String: Any]] = [
            ["id": UUID().uuidString, "role": "user", "content": "What should I snack on?", "timestamp": Self.stamp(hour: 10)],
            ["id": UUID().uuidString, "role": "assistant", "content": "Try Greek yogurt with berries.", "timestamp": Self.stamp(hour: 10)],
        ]
        let app = makeApp(["coachChatHistory": chat])
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["Log foods from this"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        open("from_coach", in: app)
        XCTAssertTrue(app.navigationBars["From Coach"].waitForExistence(timeout: 5))
    }

    // MARK: - Progress

    @MainActor
    func testTrendsOpenWithTheGoutPresetAndShowADayWhenTapped() {
        var dinner = Self.food("Dinner", calories: 1_800, daysAgo: 1, hour: 19)
        dinner["supplementalNutrients"] = ["purines": 450, "alcohol": 28]
        let flare: [String: Any] = ["id": UUID().uuidString, "date": Self.stamp(hour: 7), "kind": "goutFlare", "severity": 2]
        let app = makeApp(["foodEntries": [dinner], "fork.symptoms": [flare], "fork.healthProfile": ["entries": ["gout"]]])
        app.tabBars.buttons["Progress"].tap()
        let card = app.staticTexts["Trends"]
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Purines (mg)", in: app).exists)
        XCTAssertTrue(text(containing: "Alcohol (g)", in: app).exists)
        app.buttons["7 days"].tap()
        let chart = text(containing: "Purines trend chart", in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        // Yesterday sits near the right edge of a 7-day chart.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)).tap()
        let foods = app.buttons["Foods behind purines"]
        reveal(foods, in: app)
    }

    // MARK: - Settings

    @MainActor
    func testAppSettingsOpenUnitsFoodMemoryAndCoachPersonality() {
        let app = makeApp()
        app.tabBars.buttons["Settings"].tap()
        let category = app.buttons["settings.category.appPreferences"]
        reveal(category, in: app)
        category.tap()
        for (row, title) in [("Units", "Units"), ("Food Memory", "Food Memory"), ("Coach Personality", "Coach Personality")] {
            let link = app.buttons[row].firstMatch
            reveal(link, in: app)
            link.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) did not open")
            app.navigationBars[title].buttons.element(boundBy: 0).tap()
        }
    }

    @MainActor
    func testMedicinesHaveTheirOwnSettingsAndTheLockHidesNamesOnHome() {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let doseMinute = min((now.hour ?? 0) * 60 + (now.minute ?? 0) + 90, 23 * 60 + 59)
        let profile: [String: Any] = ["entries": ["levothyroxine"],
                                      "doseSchedules": ["levothyroxine": ["times": [doseMinute]]]]
        let app = makeApp(["fork.healthProfile": profile])
        XCTAssertTrue(text(containing: "Levothyroxine at", in: app).waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let category = app.buttons["settings.category.medicines"]
        reveal(category, in: app)
        category.tap()
        XCTAssertTrue(app.navigationBars["Medicines"].waitForExistence(timeout: 5))
        let lock = app.switches["Lock with Face ID"]
        reveal(lock, in: app)
        lock.switches.firstMatch.tap()
        XCTAssertEqual(lock.value as? String, "1")
        XCTAssertTrue(app.switches.containing(NSPredicate(format: "label CONTAINS %@", "Share medicine names with AI")).firstMatch.exists)

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(text(containing: "Medicine at", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(text(containing: "Levothyroxine", in: app).exists)
    }

    @MainActor
    func testWaterSettingsCountDrinksToggle() {
        let app = makeApp(["waterTrackingEnabled": true])
        app.tabBars.buttons["Settings"].tap()
        let category = app.buttons["settings.category.trackingNotifications"]
        reveal(category, in: app)
        category.tap()
        let toggle = app.switches.containing(NSPredicate(format: "label CONTAINS %@", "Count drinks toward water")).firstMatch
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    // MARK: - Workouts

    @MainActor
    func testCalorieBurnButtonIsAFullWidthBarThatAsksForAWorkoutFirst() {
        let app = makeApp(["fudai.workouts.tab.mode.v2": "log"])
        app.tabBars.buttons["Workouts"].tap()
        let button = app.buttons["workouts.log.calculateBurn"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, "Calculate calorie burn")
        // A wide, short bar, not the old 156-pt round button.
        XCTAssertGreaterThan(button.frame.width, app.windows.firstMatch.frame.width * 0.8)
        XCTAssertLessThan(button.frame.height, 80)
        button.tap()
        XCTAssertTrue(app.alerts["Log a workout first"].waitForExistence(timeout: 5))
    }
}
