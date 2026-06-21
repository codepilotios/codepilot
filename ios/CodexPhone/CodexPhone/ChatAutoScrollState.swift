import Foundation

struct ChatAutoScrollState: Equatable {
    private(set) var shouldFollowLatest = true
    private(set) var hasUnseenActivity = false

    mutating func userDraggedTowardHistory() {
        shouldFollowLatest = false
    }

    mutating func reachedLatest() {
        shouldFollowLatest = true
        hasUnseenActivity = false
    }

    mutating func forceFollowLatest() {
        reachedLatest()
    }

    @discardableResult
    mutating func noteIncomingActivityWhileDetached() -> Bool {
        guard !shouldFollowLatest else {
            hasUnseenActivity = false
            return false
        }
        hasUnseenActivity = true
        return true
    }
}
