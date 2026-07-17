import ActivityKit
import Foundation

struct TotalCreditActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Kind: String, Codable, Hashable {
            case available
            case refilling
            case authenticationRequired
            case unavailable
        }

        let kind: Kind
        let percent: Int?
        let progress: Double
        let usableAccountCount: Int
        let reportedAccountCount: Int
        let nextRefreshAt: Int?
        let refreshLabel: String?
        let generatedAt: Int
    }

    let identifier: String
}
