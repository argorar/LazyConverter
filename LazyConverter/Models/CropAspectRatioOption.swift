import Foundation

enum CropAspectRatioOption: String, CaseIterable, Identifiable {
    case free = "Free"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"
    case oneOne = "1:1"
    case fourThree = "4:3"

    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        case .oneOne: return 1.0
        case .fourThree: return 4.0 / 3.0
        }
    }
}
