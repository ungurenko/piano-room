import Foundation
import os
import Testing
@testable import PianoRoom

struct MIDIRouterTests {
    @Test @MainActor func audioDeliveryDoesNotWaitForScreen() async {
        let queue = DispatchQueue(label: "test.midi.audio")
        let delivered = OSAllocatedUnfairLock(initialState: [MIDIEvent]())
        var observed: [MIDIEvent] = []
        let router = MIDIRouter(submit: { event, valid, completion in
            queue.async {
                guard valid() else { return }
                delivered.withLock { $0.append(event) }
                completion(.success(event))
            }
        }, observe: { batch in
            observed.append(contentsOf: batch.compactMap { try? $0.get() })
        })
        let events: [MIDIEvent] = [.noteOn(note: 60, velocity: 90, channel: 0),
            .controlChange(controller: 64, value: 127, channel: 0),
            .programChange(program: 16, channel: 0), .noteOff(note: 60, channel: 0)]
        for event in events { router.receive(event) }
        // MainActor is occupied until this sync returns; audio must already finish.
        queue.sync {}
        #expect(delivered.withLock { $0 } == events)
        #expect(observed.isEmpty)
        for _ in 0..<20 where observed.count != events.count { await Task.yield() }
        #expect(observed == events)
    }

    @Test @MainActor func invalidationRejectsQueuedAudioAndScreenEvents() async {
        let queue = DispatchQueue(label: "test.midi.epoch")
        let gate = DispatchSemaphore(value: 0)
        let delivered = OSAllocatedUnfairLock(initialState: 0)
        var observed = 0
        let router = MIDIRouter(submit: { event, valid, completion in
            queue.async {
                guard valid() else { return }
                delivered.withLock { $0 += 1 }
                completion(.success(event))
            }
        }, observe: { batch in observed += batch.count })
        let note = MIDIEvent.noteOn(note: 60, velocity: 90, channel: 0)
        router.receive(note)
        queue.sync {}
        router.invalidate()
        queue.async { gate.wait() }
        router.receive(note)
        router.invalidate(stop: true)
        gate.signal()
        queue.sync {}
        router.receive(note)
        queue.sync {}
        for _ in 0..<20 { await Task.yield() }
        #expect(delivered.withLock { $0 } == 1)
        #expect(observed == 0)
    }

    @Test @MainActor func manualEffectsDiscardOnlySupersededScreenFeedback() async {
        let queue = DispatchQueue(label: "test.midi.feedback")
        let gate = DispatchSemaphore(value: 0)
        let delivered = OSAllocatedUnfairLock(initialState: [MIDIEvent]())
        var observed: [MIDIEvent] = []
        let router = MIDIRouter(submit: { event, valid, completion in
            queue.async {
                guard valid() else { return }
                delivered.withLock { $0.append(event) }
                completion(.success(event))
            }
        }, observe: { batch in
            observed.append(contentsOf: batch.compactMap { try? $0.get() })
        })
        let reverb = MIDIEvent.controlChange(controller: 91, value: 10, channel: 0)
        let delay = MIDIEvent.controlChange(controller: 93, value: 20, channel: 0)
        let pedal = MIDIEvent.controlChange(controller: 64, value: 127, channel: 0)
        let noteOff = MIDIEvent.noteOff(note: 60, channel: 0)
        router.receive(reverb)
        queue.sync {}
        // Reverb feedback is already pending, while delay completion is in flight.
        queue.async { gate.wait() }
        router.receive(delay)
        router.receive(pedal)
        router.receive(noteOff)
        router.invalidateFeedback(controller: 91)
        router.invalidateFeedback(controller: 93)
        gate.signal()
        queue.sync {}
        for _ in 0..<20 where observed.count != 2 { await Task.yield() }
        #expect(delivered.withLock { $0 } == [reverb, delay, pedal, noteOff])
        #expect(observed == [pedal, noteOff])
        // Subsequent MIDI remains authoritative and other controllers are untouched.
        router.receive(reverb)
        queue.sync {}
        for _ in 0..<20 where observed.count != 3 { await Task.yield() }
        #expect(observed == [pedal, noteOff, reverb])
    }

}
