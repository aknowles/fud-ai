import Foundation

extension OptionalNutrient {
    /// What the number means, in plain words, for the nutrients the health features watch;
    /// nil for the rest.
    var plainExplanation: String? {
        switch self {
        case .sugar:
            String(localized: "All the sugar in the food: what's naturally there, like lactose in milk or fructose in fruit, plus any added sugar. Added sugar is part of this total, not extra.")
        case .addedSugar:
            String(localized: "Only the sugar put in during cooking or processing: syrup, honey, table sugar, sweetened powders and sauces. Guidelines limit this part (about 25–36 g a day); natural sugar in milk and whole fruit doesn't count against it. For gout, fructose matters either way, so sweet drinks and juice count even when the sugar is natural.")
        case .saturatedFat:
            String(localized: "The fat in butter, cheese, fatty meat and coconut oil. DASH and heart-health goals keep it low because it raises LDL cholesterol.")
        case .transFat:
            String(localized: "Fat from partially hydrogenated oils, found in some fried and packaged foods. Keep it as close to zero as you can.")
        case .sodium:
            String(localized: "Mostly from salt. Most of it comes from packaged, restaurant and cured foods rather than the salt shaker. DASH and blood-pressure goals limit it.")
        case .potassium:
            String(localized: "Found in fruit, vegetables, beans and dairy. It helps lower blood pressure, so DASH aims high, but some kidney conditions and medicines need it limited.")
        case .fiber:
            String(localized: "The part of plant foods you don't digest. It keeps you full and helps blood sugar and cholesterol; most people get too little.")
        case .purines:
            String(localized: "Compounds the body breaks down into uric acid, which causes gout flares. Highest in organ meats, some seafood, red meat and beer; low in dairy, eggs and most vegetables.")
        case .alcohol:
            String(localized: "Grams of alcohol. Beer and spirits raise uric acid for gout, and alcohol clashes with several medicines.")
        case .phosphorus:
            String(localized: "Found in protein foods, dairy, colas and many processed foods with phosphate additives. Kidney conditions often need it limited.")
        case .oxalate:
            String(localized: "A compound in spinach, rhubarb, nuts, beets and tea that can form kidney stones. Estimated from a reference table.")
        case .tyramine:
            String(localized: "Builds up in aged cheese, cured meat, soy sauce and other aged or fermented foods. Dangerous with MAOI medicines. Estimated from a reference table.")
        case .vitaminK:
            String(localized: "Mostly from leafy greens. Warfarin needs it steady from day to day rather than low.")
        case .caffeine:
            String(localized: "From coffee, tea, energy drinks and chocolate. About 400 mg a day is a common upper limit for adults.")
        case .cholesterol:
            String(localized: "Found only in animal foods such as eggs, meat and dairy. Saturated fat affects blood cholesterol more than this number does.")
        case .calcium:
            String(localized: "From dairy, fortified plant milks, tofu and leafy greens. Prednisone and other steroids thin bones, so goals aim higher while you take them; DASH also counts dairy.")
        case .magnesium:
            String(localized: "From nuts, seeds, beans, whole grains and leafy greens. Part of the DASH pattern, and some medicines lower it.")
        case .vitaminD:
            String(localized: "From fortified milk, fatty fish, eggs and sunlight. Works with calcium for bones, which matters on steroids.")
        case .vitaminB12:
            String(localized: "Found in meat, fish, eggs, dairy and fortified foods. Metformin can lower it over time, so goals aim to keep it up.")
        default:
            nil
        }
    }
}
