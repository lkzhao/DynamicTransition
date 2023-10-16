//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/12/23.
//

import UIKit
import Motion
import simd

public enum TransitionEndPosition {
    case dismissed
    case presented
}

class TransitionAnimator {
    private var children: [AnyHashable: AnyTransitionPropertyAnimator]
    private var completion: (TransitionEndPosition) -> Void

    public private(set) var targetPosition: TransitionEndPosition? = nil
    public var isAnimating: Bool {
        targetPosition != nil
    }

    public init(completion: @escaping (TransitionEndPosition) -> Void) {
        children = [:]
        self.completion = completion
    }

    private struct AnimatorID<View: UIView, Value: SIMDRepresentable>: Hashable {
        let view: View
        let keypath: ReferenceWritableKeyPath<View, Value>
    }

    public subscript<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) -> TransitionPropertyAnimator<Value> {
        let key = AnimatorID(view: view, keypath: keyPath)
        if let animator = children[key] as? TransitionPropertyAnimator<Value> {
            return animator
        } else {
            let animation = SpringAnimation(initialValue: view[keyPath: keyPath])
            animation.configure(stiffness: 300, damping: 30)
            animation.onValueChanged { [weak view] value in
                view?[keyPath: keyPath] = value
            }
            let animator = TransitionPropertyAnimator(animation: animation)
            children[key] = animator
            return animator
        }
    }

    public func seekTo(position: TransitionEndPosition) {
        for child in children.values {
            child.seekTo(position: position)
        }
    }

    public func animateTo(position: TransitionEndPosition) {
        guard targetPosition == nil else {
            assertionFailure("You should pause the animation before starting another animation")
            return
        }
        targetPosition = position
        let dispatchGroup = DispatchGroup()
        for child in children.values {
            dispatchGroup.enter()
            child.animateTo(position: position) {
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) { [weak self] in
            self?.completion(position)
        }
    }


    public func pause() {
        targetPosition = nil
        for child in children.values {
            child.pause()
        }
    }

    public func shift(progress: Double) {
        for child in children.values {
            child.shift(progress: progress)
        }
    }
}

public class TransitionPropertyAnimator<Value: SIMDRepresentable> {
    public let animation: Motion.SpringAnimation<Value>

    public var presentedValue: Value {
        didSet {
            if targetPosition == .presented {
                animation.toValue = presentedValue
            }
        }
    }
    public var dismissedValue: Value {
        didSet {
            if targetPosition == .dismissed {
                animation.toValue = dismissedValue
            }
        }
    }
    public var value: Value {
        get {
            animation.value
        }
        set {
            animation.updateValue(to: newValue, postValueChanged: true)
        }
    }
    public var velocity: Value {
        get {
            animation.velocity
        }
        set {
            animation.velocity = newValue
        }
    }
    public var isIndependent: Bool = false
    public var isAnimating: Bool {
        targetPosition != nil
    }
    public private(set) var targetPosition: TransitionEndPosition?

    fileprivate init(animation: Motion.SpringAnimation<Value>) {
        self.animation = animation
        self.presentedValue = animation.value
        self.dismissedValue = animation.value
    }
}

fileprivate protocol AnyTransitionPropertyAnimator {
    func seekTo(position: TransitionEndPosition)
    func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void)
    func pause()
    func shift(progress: Double)
}

extension TransitionPropertyAnimator: AnyTransitionPropertyAnimator {
    fileprivate func seekTo(position: TransitionEndPosition) {
        value = position == .presented ? presentedValue : dismissedValue
    }

    fileprivate func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void) {
        let value = position == .presented ? presentedValue : dismissedValue
        let threshold = max(1, animation.value.distance(between: value)) * 0.005
        let epsilon = (threshold as? Value.SIMDType.EpsilonType) ?? 0.01
        isIndependent = false
        targetPosition = position
        if animation.value.simdRepresentation().approximatelyEqual(to: value.simdRepresentation(), epsilon: epsilon) {
            completion()
        } else {
            animation.configure(stiffness: 300, damping: 30)
            animation.toValue = value
            animation.resolvingEpsilon = epsilon
            animation.completion = completion
            animation.start()
        }
    }

    fileprivate func pause() {
        targetPosition = nil
        animation.stop()
    }

    fileprivate func shift(progress: Double) {
        guard !isIndependent else { return }
        let presentedVector = presentedValue.simdRepresentation()
        let dismissedVector = dismissedValue.simdRepresentation()
        let progressDiff = Value.SIMDType.Scalar(progress) * (presentedVector - dismissedVector)
        var valueVector = value.simdRepresentation()
        valueVector += progressDiff

        // clamp value between presented value and dismissed value
        let range = presentedVector.createClampingRange(other: dismissedVector)
        valueVector.clamp(lowerBound: range.lowerBound, upperBound: range.upperBound)

        value = Value(valueVector)
    }
}
