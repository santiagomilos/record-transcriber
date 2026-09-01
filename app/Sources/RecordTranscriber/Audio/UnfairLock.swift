import os

/// UnfairLock guards the handful of values shared between the audio thread and
/// the rest of the app.
///
/// `OSAllocatedUnfairLock` would be the obvious choice, but its `withLock` takes
/// a `@Sendable` closure and the raw audio buffers this code hands across the
/// boundary are not Sendable — making that exact sharing safe is what the lock
/// is for. It is held only for a memcpy or a struct copy, never across a call
/// that can block.
final class UnfairLock {
    private let storage: UnsafeMutablePointer<os_unfair_lock>

    init() {
        storage = .allocate(capacity: 1)
        storage.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(storage)
        defer { os_unfair_lock_unlock(storage) }
        return body()
    }
}
