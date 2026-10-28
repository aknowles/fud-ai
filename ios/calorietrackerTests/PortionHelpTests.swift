import Foundation
import Testing
import UIKit
@testable import calorietracker

/// Portion multipliers set the quantity in the selected unit, the AR note finds a usable
/// measurement, and photos without one ask the AI to use a card or coin for scale (#19).
@MainActor
struct PortionHelpTests {
    private let grams = ServingUnitOption.grams
    private let cup = ServingUnitOption(unit: "cup", gramsPerUnit: 240)

    @Test func multipliersScaleTheEstimateInTheSelectedUnit() {
        #expect(PortionMultiplier.quantityText(baseGrams: 200, multiplier: 1.5, option: grams) == "300")
        #expect(PortionMultiplier.quantityText(baseGrams: 240, multiplier: 0.5, option: cup) == "0.5")
        #expect(PortionMultiplier.quantityText(baseGrams: 240, multiplier: 0.75, option: cup) == "0.75")
        #expect(PortionMultiplier.quantityText(baseGrams: 480, multiplier: 2, option: cup) == "4")
    }

    @Test func currentMultiplierMatchesOnlyAnOfferedRatio() {
        #expect(PortionMultiplier.current(servingGrams: 150, baseGrams: 200) == 0.75)
        #expect(PortionMultiplier.current(servingGrams: 200, baseGrams: 200) == 1)
        #expect(PortionMultiplier.current(servingGrams: 230, baseGrams: 200) == nil)
        #expect(PortionMultiplier.current(servingGrams: 100, baseGrams: 0) == nil)
    }

    @Test func labelsUseFractions() {
        #expect(PortionMultiplier.values.map(PortionMultiplier.label) == ["½×", "¾×", "1×", "1½×", "2×"])
    }

    @Test func arNoteUsesTheFirstUsableMeasurement() {
        let size = CGSize(width: 4, height: 4)
        let plain = UIGraphicsImageRenderer(size: size).image { _ in }
        let tilted = UIGraphicsImageRenderer(size: size).image { _ in }
        let overhead = UIGraphicsImageRenderer(size: size).image { _ in }
        let ready = PortionScale(cameraHeightCm: 40, tiltDegrees: 3, photoWidthCm: 38, photoHeightCm: 51)
        PortionScaleRegistry.attach(PortionScale(cameraHeightCm: 40, tiltDegrees: 45, photoWidthCm: 30, photoHeightCm: 40), to: tilted)
        PortionScaleRegistry.attach(ready, to: overhead)

        #expect(PortionReference.arScale(in: [plain, tilted, overhead]) == ready)
        #expect(PortionReference.arScale(in: [plain, tilted]) == nil)
    }

    @Test func photosWithoutARScaleGetTheCardOrCoinHint() throws {
        let ready = PortionScale(cameraHeightCm: 40, tiltDegrees: 3, photoWidthCm: 38, photoHeightCm: 51)
        let measured = PortionReference.promptSection(for: [ready])
        #expect(measured == PortionScale.promptSection(for: [ready]))
        #expect(!measured.contains("SIZE REFERENCES"))

        let unmeasured = PortionReference.promptSection(for: [nil])
        #expect(unmeasured == PortionReference.sizeReferenceSection)
        #expect(unmeasured.contains("8.56 × 5.40 cm"))
        #expect(unmeasured.contains("coin"))
    }
}
