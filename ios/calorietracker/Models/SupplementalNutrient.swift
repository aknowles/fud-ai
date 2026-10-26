import Foundation

enum SupplementalNutrient: String, CaseIterable, Identifiable, Codable {
    case creatine
    case betaAlanine
    case lCitrulline
    case lCarnitine
    case lArginine
    case taurine
    case betaine
    case hmb
    case purines
    case alcohol
    case phosphorus
    case oxalate
    case tyramine

    var id: String { rawValue }

    var jsonKey: String {
        switch self {
        case .creatine: "creatine"
        case .betaAlanine: "beta_alanine"
        case .lCitrulline: "l_citrulline"
        case .lCarnitine: "l_carnitine"
        case .lArginine: "l_arginine"
        case .taurine: "taurine"
        case .betaine: "betaine"
        case .hmb: "hmb"
        case .purines: "purines"
        case .alcohol: "alcohol"
        case .phosphorus: "phosphorus"
        case .oxalate: "oxalate"
        case .tyramine: "tyramine"
        }
    }

    var displayName: String {
        switch self {
        case .creatine: "Creatine"
        case .betaAlanine: "Beta-Alanine"
        case .lCitrulline: "L-Citrulline"
        case .lCarnitine: "L-Carnitine"
        case .lArginine: "L-Arginine"
        case .taurine: "Taurine"
        case .betaine: "Betaine"
        case .hmb: "HMB"
        case .purines: "Purines"
        case .alcohol: "Alcohol"
        case .phosphorus: "Phosphorus"
        case .oxalate: "Oxalate"
        case .tyramine: "Tyramine"
        }
    }

    var optionalNutrient: OptionalNutrient {
        OptionalNutrient(rawValue: rawValue)!
    }
}
