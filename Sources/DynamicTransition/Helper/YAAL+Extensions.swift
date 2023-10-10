//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/9/23.
//

import UIKit
import YetAnotherAnimationLibrary

extension Yaal where Base: UIView {
    var frameWithoutTransform: MixAnimation<CGRect> {
        return animationFor(key: "frameWithoutTransform",
                            getter: { [weak base] in base?.frameWithoutTransform },
                            setter: { [weak base] in base?.frameWithoutTransform = $0 })
    }
    var size: MixAnimation<CGSize> {
        return animationFor(key: "size",
                            getter: { [weak base] in base?.bounds.size },
                            setter: { [weak base] in base?.bounds.size = $0 })
    }
    var cornerRadius: MixAnimation<CGFloat> {
        return animationFor(key: "cornerRadius",
                            getter: { [weak base] in base?.cornerRadius },
                            setter: { [weak base] in base?.cornerRadius = $0 })
    }
    var shadowOpacity: MixAnimation<CGFloat> {
        return animationFor(key: "shadowOpacity",
                            getter: { [weak base] in base?.shadowOpacity },
                            setter: { [weak base] in base?.shadowOpacity = $0 })
    }
}

extension MixAnimation {
    func updateTo(value: Value, animated: Bool, stiffness: Double? = nil, damping: Double? = nil) {
        let anim = MixAnimationUpdateState(animation: self, value: value, animated: animated, stiffness: stiffness, damping: damping)
        AnimationTransactionGroup.add(anim)
    }
}

protocol AnimationUpdateState {
    func run(completion: ((Bool) -> ())?)
    func stop()
}

struct MixAnimationUpdateState<Value: VectorConvertible>: AnimationUpdateState {
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

class AnimationTransactionGroup {
    private var completionBlock: ((Bool) -> Void)?
    private var animations: [AnimationUpdateState] = []

    static var currentTransaction: AnimationTransactionGroup?

    private init() {
    }

    func stop() {
        for animation in animations {
            animation.stop()
        }
    }

    static func begin(completionBlock: ((Bool) -> Void)?) {
        currentTransaction = AnimationTransactionGroup()
        currentTransaction?.completionBlock = completionBlock
    }

    static func commit() -> AnimationTransactionGroup? {
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

    static func add(_ anim: AnimationUpdateState) {
        if let currentTransaction {
            currentTransaction.animations.append(anim)
        } else {
            anim.run(completion: nil)
        }
    }
}
