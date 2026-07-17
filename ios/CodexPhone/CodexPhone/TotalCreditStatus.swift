import Foundation

struct TotalCreditStatus {
    let activityState: TotalCreditActivityAttributes.ContentState

    init(accounts: [AccountUsageStatus], now: Date) {
        let nowEpoch = Int(now.timeIntervalSince1970)
        let buckets = accounts.compactMap(AccountCreditBucket.init(account:))
        let availableBuckets = buckets.filter { !$0.authStale }
        let reportedBuckets = availableBuckets.filter { $0.remainingPercent != nil }
        let remainingValues = reportedBuckets.map { max(0, min(100, $0.remainingPercent ?? 0)) }
        let remainingSum = remainingValues.reduce(0, +)

        if !reportedBuckets.isEmpty, remainingSum > 0 {
            let progress = Double(remainingSum) / Double(reportedBuckets.count * 100)
            activityState = .init(
                kind: .available,
                percent: Int((progress * 100).rounded()),
                progress: max(0, min(1, progress)),
                usableAccountCount: remainingValues.filter { $0 > 0 }.count,
                reportedAccountCount: reportedBuckets.count,
                nextRefreshAt: nil,
                refreshLabel: nil,
                generatedAt: nowEpoch
            )
            return
        }

        if let nextRefresh = availableBuckets
            .filter({ ($0.resetAt ?? 0) > nowEpoch })
            .min(by: { ($0.resetAt ?? Int.max) < ($1.resetAt ?? Int.max) }) {
            let resetAt = nextRefresh.resetAt ?? nowEpoch
            let remainingSeconds = max(0, resetAt - nowEpoch)
            let windowSeconds = max(60, (nextRefresh.windowMins ?? 0) * 60)
            activityState = .init(
                kind: .refilling,
                percent: nil,
                progress: max(0, min(1, 1 - Double(remainingSeconds) / Double(windowSeconds))),
                usableAccountCount: 0,
                reportedAccountCount: reportedBuckets.count,
                nextRefreshAt: resetAt,
                refreshLabel: nextRefresh.label,
                generatedAt: nowEpoch
            )
            return
        }

        if !accounts.isEmpty, accounts.allSatisfy(\.authStale) {
            activityState = .init(
                kind: .authenticationRequired,
                percent: nil,
                progress: 0,
                usableAccountCount: 0,
                reportedAccountCount: 0,
                nextRefreshAt: nil,
                refreshLabel: nil,
                generatedAt: nowEpoch
            )
            return
        }

        activityState = .init(
            kind: .unavailable,
            percent: nil,
            progress: 0,
            usableAccountCount: 0,
            reportedAccountCount: reportedBuckets.count,
            nextRefreshAt: nil,
            refreshLabel: nil,
            generatedAt: nowEpoch
        )
    }
}
