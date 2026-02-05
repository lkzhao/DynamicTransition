//
//  AnimationTarget.swift
//
//
//  Created by Luke Zhao on 11/13/23.
//

import UIKit
import Motion

internal struct AnimationTarget<Target: AnyObject, Value: SIMDRepresentable>: Hashable {
    public let id: ObjectIdentifier
    public weak var target: Target?
    public let keyPath: ReferenceWritableKeyPath<Target, Value>

    public init(target: Target, keyPath: ReferenceWritableKeyPath<Target, Value>) {
        self.target = target
        self.keyPath = keyPath
        self.id = ObjectIdentifier(target)
    }

    public var value: Value {
        get {
            target?[keyPath: keyPath] ?? .zero
        }
        nonmutating set {
            target?[keyPath: keyPath] = newValue
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(keyPath)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.keyPath == rhs.keyPath
    }
}
