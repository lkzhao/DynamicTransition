//
//  TransitionPropertyAnimator.swift
//
//
//  Created by Luke Zhao on 11/13/23.
//

import UIKit
import Motion

internal protocol AnyTransitionPropertyAnimator {
    func seekTo(position: TransitionEndPosition)
    func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void)
    func pause()
    func shift(progress: Double)
}

public class TransitionPropertyAnimator<View: UIView, Value: SIMDRepresentable> {
    private let animation: AdditiveAnimation<View, Value>

    public var response: CGFloat
    public var dampingRatio: CGFloat

    public var presentedOffsetValue: Value {
        didSet {
            if targetPosition == .presented {
                animation.toValue = presentedOffsetValue
            }
        }
    }
    public var dismissedOffsetValue: Value {
        didSet {
            if targetPosition == .dismissed {
                animation.toValue = dismissedOffsetValue
            }
        }
    }
    public var value: Value {
        get {
            animation.value
        }
        set {
            animation.value = newValue
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
    public var baseValue: Value {
        get {
            animation.baseValue
        }
        set {
            animation.baseValue = newValue
        }
    }
    public var isIndependent: Bool = false
    public var isAnimating: Bool {
        targetPosition != nil
    }
    public private(set) var targetPosition: TransitionEndPosition?

    internal init(target: AnimationTarget<View, Value>, response: CGFloat, dampingRatio: CGFloat) {
        self.animation = AdditiveAnimation(target: target)
        self.presentedOffsetValue = .zero
        self.dismissedOffsetValue = .zero
        self.response = response
        self.dampingRatio = dampingRatio
    }

    /// Set the new target value and apply the offset to the current value
    /// Note that the value set here is the final value, not the offset value (both `presentedOffsetValue` and `dismissedOffsetValue` are offset values)
    public func setNewTargetValueAndApplyOffset(position: TransitionEndPosition, newValue: Value) {
        let offsetValue = Value(newValue.simdRepresentation() - baseValue.simdRepresentation())
        if position == .presented {
            value = Value(value.simdRepresentation() + offsetValue.simdRepresentation() - presentedOffsetValue.simdRepresentation())
            presentedOffsetValue = offsetValue
        } else {
            value = Value(value.simdRepresentation() + offsetValue.simdRepresentation() - dismissedOffsetValue.simdRepresentation())
            dismissedOffsetValue = offsetValue
        }
    }
}

extension TransitionPropertyAnimator: AnyTransitionPropertyAnimator {
    internal func seekTo(position: TransitionEndPosition) {
        value = position == .presented ? presentedOffsetValue : dismissedOffsetValue
    }

    internal func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void) {
        let toValue = position == .presented ? presentedOffsetValue : dismissedOffsetValue
        isIndependent = false
        targetPosition = position
        animation.animate(to: toValue, response: response, dampingRatio: dampingRatio, completion: completion)
    }

    internal func pause() {
        targetPosition = nil
        animation.stop()
    }

    internal func shift(progress: Double) {
        guard !isIndependent else { return }
        let presentedVector = presentedOffsetValue.simdRepresentation()
        let dismissedVector = dismissedOffsetValue.simdRepresentation()
        let progressDiff = Value.SIMDType.Scalar(progress) * (presentedVector - dismissedVector)
        var valueVector = value.simdRepresentation()
        valueVector += progressDiff

        // clamp value between presented value and dismissed value
        let range = presentedVector.createClampingRange(other: dismissedVector)
        valueVector.clamp(lowerBound: range.lowerBound, upperBound: range.upperBound)

        value = Value(valueVector)
    }
}
