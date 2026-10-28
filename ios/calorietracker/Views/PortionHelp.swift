import SwiftUI
import UIKit

/// Portion-size help on Review Food (#19): quick multipliers of the estimated serving,
/// a hand-size and everyday-object guide, and a note when a photo had AR scale.
enum PortionMultiplier {
    static let values: [Double] = [0.5, 0.75, 1, 1.5, 2]

    static func label(_ value: Double) -> String {
        switch value {
        case 0.5: return "½×"
        case 0.75: return "¾×"
        case 1.5: return "1½×"
        default: return "\(ServingUnitEditor.formatQuantity(value))×"
        }
    }

    /// Quantity text, in the selected unit, for `multiplier` times the estimated serving.
    static func quantityText(baseGrams: Double, multiplier: Double, option: ServingUnitOption) -> String {
        let grams = baseGrams * multiplier
        return ServingUnitEditor.formatQuantity(option.gramsPerUnit > 0 ? grams / option.gramsPerUnit : grams)
    }

    /// The multiplier the current serving matches, if any.
    static func current(servingGrams: Double, baseGrams: Double) -> Double? {
        guard baseGrams > 0 else { return nil }
        let ratio = servingGrams / baseGrams
        return values.first { abs($0 - ratio) < 0.01 }
    }
}

/// Hand sizes and everyday objects for judging a portion by eye.
enum PortionReference {
    struct Item: Hashable {
        let symbol: String
        let title: String
        let amount: String
    }

    static let hands: [Item] = [
        Item(symbol: "hand.raised.fill", title: String(localized: "Palm"), amount: String(localized: "about 3 oz (85 g) cooked meat or fish")),
        Item(symbol: "hand.raised.fingers.spread.fill", title: String(localized: "Fist"), amount: String(localized: "about 1 cup (240 ml) rice, pasta, cereal or fruit")),
        Item(symbol: "circle.bottomhalf.filled", title: String(localized: "Cupped hand"), amount: String(localized: "about 1 oz (28 g) nuts or chips")),
        Item(symbol: "hand.thumbsup.fill", title: String(localized: "Thumb"), amount: String(localized: "about 1 tbsp (15 ml) butter, oil or peanut butter")),
        Item(symbol: "hand.point.up.left.fill", title: String(localized: "Fingertip"), amount: String(localized: "about 1 tsp (5 ml) oil or butter")),
    ]

    static let objects: [Item] = [
        Item(symbol: "rectangle.portrait.fill", title: String(localized: "Deck of cards"), amount: String(localized: "about 3 oz (85 g) meat")),
        Item(symbol: "baseball.fill", title: String(localized: "Baseball"), amount: String(localized: "about 1 cup (240 ml)")),
        Item(symbol: "tennisball.fill", title: String(localized: "Tennis ball"), amount: String(localized: "about ½ cup (120 ml), or one medium fruit")),
        Item(symbol: "circle.fill", title: String(localized: "Golf ball"), amount: String(localized: "about 2 tbsp (30 ml)")),
        Item(symbol: "die.face.4.fill", title: String(localized: "Four dice"), amount: String(localized: "about 1½ oz (42 g) cheese")),
    ]

    /// AI-facing English, sent with photos that have no AR measurement, so a card or
    /// coin in the frame still gives the picture a real-world scale.
    static let sizeReferenceSection = """
    SIZE REFERENCES
    If a bank or credit card (8.56 × 5.40 cm), a coin (a US quarter is 2.43 cm across; most coins are 1.6–2.8 cm) or another object of standard size is visible next to the food, use it to judge the real size of the plate, bowl and food instead of assuming typical sizes.
    """

    /// The AR measurement section when a photo has one, otherwise the size-reference hint.
    static func promptSection(for scales: [PortionScale?]) -> String {
        PortionScale.promptSection(for: scales) ?? sizeReferenceSection
    }

    /// The AR measurement of the first photo that had a usable one.
    static func arScale(in images: [UIImage]) -> PortionScale? {
        images.lazy.compactMap(PortionScaleRegistry.scale(for:)).first { $0.readiness == .ready }
    }
}

/// Rows for the Serving section of Review Food.
struct PortionHelpRows: View {
    let images: [UIImage]
    let baseServingGrams: Double
    let servingGrams: Double
    let servingOption: ServingUnitOption
    @Binding var quantityText: String
    @State private var showGuide = false

    var body: some View {
        let current = PortionMultiplier.current(servingGrams: servingGrams, baseGrams: baseServingGrams)
        HStack(spacing: 6) {
            ForEach(PortionMultiplier.values, id: \.self) { value in
                Button {
                    quantityText = PortionMultiplier.quantityText(baseGrams: baseServingGrams, multiplier: value, option: servingOption)
                } label: {
                    Text(PortionMultiplier.label(value))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(current == value ? AppColors.calorie : .secondary)
                .accessibilityLabel(String(localized: "\(PortionMultiplier.label(value)) the estimated portion"))
                .accessibilityAddTraits(current == value ? .isSelected : [])
                .accessibilityIdentifier("review.portion.multiplier.\(ServingUnitEditor.formatQuantity(value))")
            }
        }

        if let scale = PortionReference.arScale(in: images) {
            Label {
                Text("Sized with the AR camera: the photo covers about \(Int(scale.photoWidthCm.rounded())) × \(Int(scale.photoHeightCm.rounded())) cm of table.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "ruler")
                    .foregroundStyle(AppColors.calorie)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("review.portion.arScale")
        }

        Button {
            showGuide = true
        } label: {
            Label("Portion guide", systemImage: "hand.raised")
        }
        .accessibilityIdentifier("review.portion.guide")
        .sheet(isPresented: $showGuide) {
            PortionGuideSheet()
        }
    }
}

struct PortionGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PortionReference.hands, id: \.self, content: row)
                } header: {
                    Text("Your hand")
                } footer: {
                    Text("Hands vary; an adult's hand is the usual guide.")
                }
                Section("Everyday objects") {
                    ForEach(PortionReference.objects, id: \.self, content: row)
                }
                Section("Photo scale") {
                    Label {
                        Text("When the camera can see the table clearly from above, Fud AI measures it with AR and sends the real size to the AI. Review Food then says the photo was sized with the AR camera.")
                    } icon: {
                        Image(systemName: "ruler")
                    }
                    Label {
                        Text("No AR? Put a bank card or a coin next to the food. The AI uses its known size to judge the portion.")
                    } icon: {
                        Image(systemName: "creditcard")
                    }
                }
            }
            .navigationTitle("Portion guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ item: PortionReference.Item) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.amount)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: item.symbol)
                .foregroundStyle(AppColors.calorie)
        }
        .accessibilityElement(children: .combine)
    }
}
