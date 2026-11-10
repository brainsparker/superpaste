import Foundation

struct InsertionContext: Equatable {
    let value: String
    let selectionLocation: Int
    let selectionLength: Int
}

/// Ownership survives the staging delay, but never a user's external copy.
@MainActor
final class ClipboardRestoration<Snapshot> {
    private var pending: (snapshot: Snapshot, changeCount: Int)?

    func remember(_ snapshot: Snapshot, changeCount: Int) {
        pending = (snapshot, changeCount)
    }

    @discardableResult
    func settle(changeCount: Int, restore: (Snapshot) -> Bool, currentOwnedCount: () -> Int? = { nil }) -> Bool {
        guard let pending else { return true }
        guard pending.changeCount == changeCount else {
            self.pending = nil
            return true
        }
        guard restore(pending.snapshot) else {
            if let count = currentOwnedCount() { self.pending = (pending.snapshot, count) }
            return false
        }
        self.pending = nil
        return true
    }
}
