//
//  EventDispatcher.swift
//
//
//  Multicast publish/subscribe for gaze and tracking events. Backed by
//  Combine's `PassthroughSubject` (multicast by default), with thin
//  `AsyncStream` wrappers for async/await consumers.
//

import Foundation
import Combine

public final class EventDispatcher<Event> {
    private let subject = PassthroughSubject<Event, Never>()

    public init() {}

    public var publisher: AnyPublisher<Event, Never> { subject.eraseToAnyPublisher() }

    /// Async stream backed by the same multicast source. Each call produces
    /// an independent stream so multiple async consumers can coexist.
    public var stream: AsyncStream<Event> {
        AsyncStream { continuation in
            let cancellable = subject.sink { event in
                continuation.yield(event)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    public func send(_ event: Event) {
        subject.send(event)
    }
}
