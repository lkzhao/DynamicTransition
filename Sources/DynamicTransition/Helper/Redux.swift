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

protocol EventReceiver<Event>: AnyObject {
    associatedtype Event
    func receive(_ event: Event)
}

class Store<Event>: EventStore {
    weak var target: (any EventReceiver<Event>)?
    init(target: any EventReceiver<Event>) {
        self.target = target
    }
    func send(_ event: Event) {
        target?.receive(event)
    }
}
