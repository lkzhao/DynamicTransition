//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/12/23.
//

import YetAnotherAnimationLibrary
import UIKit

enum TransitionEndPosition {
    case dismissed
    case presented
}

protocol AnyStateAnimator {
    func seekTo(position: TransitionEndPosition)
    func animateTo(position: TransitionEndPosition, completion: @escaping (Bool) -> Void)
    func pause()
    func shift(progress: CGFloat)
}

private struct StateAnimator<Value: VectorConvertible>: AnyStateAnimator {
    var animation: MixAnimation<Value>

    var presentedValue: Value
    var dismissedValue: Value
    var currentValue: Value {
        get {
            animation.value.value
        }
        set {
            animation.setTo(newValue)
        }
    }
    var currentVelocity: Value {
        get {
            animation.velocity.value
        }
        set {
            animation.velocity.value = newValue
        }
    }

    var stiffness: Double?
    var damping: Double?

    func seekTo(position: TransitionEndPosition) {
        let value = position == .presented ? presentedValue : dismissedValue
        animation.setTo(value)
    }

    func animateTo(position: TransitionEndPosition, completion: @escaping (Bool) -> Void) {
        let value = position == .presented ? presentedValue : dismissedValue
        let threshold = max(1, animation.value.vector.distance(between: value.vector)) * 0.005
        animation.animateTo(value, stiffness: stiffness, damping: damping, threshold: threshold, completionHandler: completion)
    }

    func pause() {
        animation.stop()
    }

    func shift(progress: CGFloat) {
        let newValueVector = progress * (presentedValue.vector - dismissedValue.vector) + currentValue.vector
        let newValue = Value.from(vector: newValueVector)
        animation.setTo(newValue)
    }
}

struct TransitionAnimator {
    private var children: [Animation: AnyStateAnimator]
    private var completion: (TransitionEndPosition) -> Void

    init(completion: @escaping (TransitionEndPosition) -> Void) {
        children = [:]
        self.completion = completion
    }

    mutating func add<Value: VectorConvertible>(animation: MixAnimation<Value>, presentedValue: Value, dismissedValue: Value, stiffness: Double? = 300, damping: Double? = 35) {
        let animator = StateAnimator(animation: animation, presentedValue: presentedValue, dismissedValue: dismissedValue, stiffness: stiffness, damping: damping)
        children[animation] = animator
    }

    private func stateAnimatorFor<Value: VectorConvertible>(animation: MixAnimation<Value>) -> StateAnimator<Value>? {
        children[animation] as? StateAnimator<Value>
    }

    func seekTo(position: TransitionEndPosition) {
        for child in children.values {
            child.seekTo(position: position)
        }
    }

    func animateTo(position: TransitionEndPosition) {
        var allFinished = true
        let dispatchGroup = DispatchGroup()
        for child in children.values {
            dispatchGroup.enter()
            child.animateTo(position: position) { finished in
                allFinished = allFinished && finished
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) {
            if allFinished {
                completion(position)
            }
        }
    }

    func pause() {
        for child in children.values {
            child.pause()
        }
    }

    func shift(progress: CGFloat) {
        for child in children.values {
            child.shift(progress: progress)
        }
    }
}
