//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/7/23.
//

import Foundation

protocol EventStore<Event> {
    associatedtype Event
    func send(_ event: Event)
}

protocol SimpleStoreReceiver<Event>: AnyObject {
    associatedtype Event
    func receive(_ event: Event)
}

class SimpleStore<Event>: EventStore {
    weak var target: (any SimpleStoreReceiver<Event>)?
    init(target: any SimpleStoreReceiver<Event>) {
        self.target = target
    }
    func send(_ event: Event) {
        target?.receive(event)
    }
}
