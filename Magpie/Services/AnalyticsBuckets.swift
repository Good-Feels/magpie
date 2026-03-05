import Foundation

enum AnalyticsBuckets {
    static func queryLengthBucket(for length: Int) -> String {
        switch length {
        case ..<1:
            return "0"
        case 1...3:
            return "1-3"
        case 4...8:
            return "4-8"
        default:
            return "9+"
        }
    }

    static func resultCountBucket(for count: Int) -> String {
        switch count {
        case ..<1:
            return "0"
        case 1...5:
            return "1-5"
        case 6...20:
            return "6-20"
        default:
            return "21+"
        }
    }
}
