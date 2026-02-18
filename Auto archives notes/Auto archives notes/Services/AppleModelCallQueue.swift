//
//  AppleModelCallQueue.swift
//  Auto archives notes
//
//  Some on-device model APIs can behave poorly under concurrent calls.
//  This provides a simple async serial queue so all FoundationModels calls are queued.
//

import Foundation

#if canImport(FoundationModels)

actor AppleModelCallQueue {
    static let shared = AppleModelCallQueue()

    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !running {
            running = true
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    private func release() {
        if waiters.isEmpty {
            running = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

#endif

