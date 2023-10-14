//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/12/23.
//

import YetAnotherAnimationLibrary
import UIKit

extension MixAnimation {
    func transitionTo(value: Value, animated: Bool, stiffness: Double? = nil, damping: Double? = nil) {
        let anim = TransactionItem(animation: self, value: value, animated: animated, stiffness: stiffness, damping: damping)
        TransitionTransaction.add(anim)
    }
}

private protocol AnyTransactionItem {
    func run(completion: ((Bool) -> ())?)
    func stop()
}

private struct TransactionItem<Value: VectorConvertible>: AnyTransactionItem {
    var animation: MixAnimation<Value>
    var value: Value
    var animated: Bool
    var stiffness: Double?
    var damping: Double?
    func run(completion: ((Bool) -> Void)?) {
        if animated {
            let threshold = max(1, animation.value.vector.distance(between: value.vector)) * 0.005
            animation.animateTo(value, stiffness: stiffness, damping: damping, threshold: threshold) { result in
                if !result {
                    print("Animation \(self) cancelled")
                }
                completion?(result)
            }
        } else {
            animation.setTo(value)
            completion?(true)
        }
    }
    func stop() {
        animation.stop()
    }
}

class TransitionTransaction {
    private var completionBlock: ((Bool) -> Void)?
    private var animations: [AnyTransactionItem] = []

    static var currentTransaction: TransitionTransaction?

    private init() {
    }

    internal func stop() {
        for animation in animations {
            animation.stop()
        }
    }

    internal static func begin(completionBlock: ((Bool) -> Void)?) {
        currentTransaction = TransitionTransaction()
        currentTransaction?.completionBlock = completionBlock
    }

    internal static func commit() -> TransitionTransaction? {
        guard let currentTransaction else { return nil }
        self.currentTransaction = nil
        guard !currentTransaction.animations.isEmpty else {
            currentTransaction.completionBlock?(true)
            return nil
        }
        var allFinished = true
        let dispatchGroup = DispatchGroup()
        for animation in currentTransaction.animations {
            dispatchGroup.enter()
            animation.run { finished in
                allFinished = allFinished && finished
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) {
            currentTransaction.completionBlock?(allFinished)
        }
        return currentTransaction
    }

    fileprivate static func add(_ anim: AnyTransactionItem) {
        if let currentTransaction {
            currentTransaction.animations.append(anim)
        } else {
            anim.run(completion: nil)
        }
    }
}
