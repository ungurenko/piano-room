import Foundation
import os

/// Audio delivery never waits for MainActor. Only screen notifications are batched.
final class MIDIRouter: @unchecked Sendable {
    typealias Submit = @Sendable (MIDIEvent, @escaping @Sendable () -> Bool,
                                  @escaping @Sendable (Result<MIDIEvent, Error>) -> Void) -> Void
    private struct State {
        var epoch: UInt64 = 0
        var active = true
        var pending: [Result<MIDIEvent, Error>] = []
        var scheduled = false
        var feedbackVersions: [UInt8: UInt64] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let submit: Submit
    private let observe: @MainActor @Sendable ([Result<MIDIEvent, Error>]) -> Void

    init(submit: @escaping Submit,
         observe: @escaping @MainActor @Sendable ([Result<MIDIEvent, Error>]) -> Void) {
        self.submit = submit
        self.observe = observe
    }

    func invalidate(stop: Bool = false) {
        state.withLock {
            $0.epoch &+= 1
            $0.pending.removeAll(keepingCapacity: !stop)
            if stop { $0.active = false }
        }
    }

    /// A newer manual setting supersedes only feedback for that controller.
    func invalidateFeedback(controller: UInt8) {
        state.withLock { value in
            value.feedbackVersions[controller, default: 0] &+= 1
            value.pending.removeAll { result in
                guard case .success(let event) = result else { return false }
                return Self.feedbackController(for: event) == controller
            }
        }
    }

    private static func feedbackController(for event: MIDIEvent) -> UInt8? {
        if case .controlChange(let controller, _, _) = event,
           controller == 91 || controller == 93 { return controller }
        return nil
    }

    func receive(_ event: MIDIEvent) {
        let controller = Self.feedbackController(for: event)
        let stamp = state.withLock { value -> (UInt64, UInt64)? in
            guard value.active else { return nil }
            return (value.epoch, controller.map { value.feedbackVersions[$0, default: 0] } ?? 0)
        }
        guard let (ticket, feedbackVersion) = stamp else { return }
        submit(event, { [weak self] in
            self?.state.withLock { $0.active && $0.epoch == ticket } ?? false
        }, { [weak self] result in
            self?.enqueue(result, ticket: ticket, controller: controller, feedbackVersion: feedbackVersion)
        })
    }

    private func enqueue(_ result: Result<MIDIEvent, Error>, ticket: UInt64,
                         controller: UInt8?, feedbackVersion: UInt64) {
        let schedule = state.withLock { value in
            guard value.active, value.epoch == ticket else { return false }
            if case .success = result, let controller,
               value.feedbackVersions[controller, default: 0] != feedbackVersion { return false }
            value.pending.append(result)
            guard !value.scheduled else { return false }
            value.scheduled = true
            return true
        }
        if schedule {
            Task { @MainActor [weak self] in self?.drain() }
        }
    }

    @MainActor private func drain() {
        let batch = state.withLock { value in
            let batch = value.pending
            value.pending.removeAll(keepingCapacity: true)
            value.scheduled = false
            return batch
        }
        if !batch.isEmpty { observe(batch) }
    }
}
