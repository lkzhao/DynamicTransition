//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/12/23.
//

import UIKit
import Motion

enum TransitionEndPosition {
    case dismissed
    case presented
}

protocol AnyStateAnimator {
    func seekTo(position: TransitionEndPosition)
    func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void)
    func pause()
    func shift(progress: CGFloat)
}

extension SupportedSIMD where Scalar: SupportedScalar {
    func distance(between: Self) -> Scalar {
        var result = Scalar.zero
        for i in 0..<scalarCount {
            result += abs(self[i] - between[i])
        }
        return result
    }
}

extension SIMDRepresentable where SIMDType.Scalar: SupportedScalar {
    func distance(between other: Self) -> SIMDType.Scalar {
        simdRepresentation().distance(between: other.simdRepresentation())
    }
}

struct AnimatorID<View: UIView, Value: SIMDRepresentable>: Hashable {
    let view: View
    let keypath: WritableKeyPath<View, Value>
}

private struct StateAnimator<Value: SIMDRepresentable>: AnyStateAnimator where Value.SIMDType.Scalar == CGFloat.NativeType {

    var animation: Motion.SpringAnimation<Value>

    var presentedValue: Value
    var dismissedValue: Value
    var currentValue: Value {
        get {
            animation.value
        }
        nonmutating set {
            animation.updateValue(to: newValue, postValueChanged: true)
        }
    }
    var currentVelocity: Value {
        get {
            animation.velocity
        }
        nonmutating set {
            animation.velocity = newValue
        }
    }

    func seekTo(position: TransitionEndPosition) {
        currentValue = position == .presented ? presentedValue : dismissedValue
    }

    func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void) {
        let value = position == .presented ? presentedValue : dismissedValue
        let threshold = max(1, animation.value.distance(between: value)) * 0.005
        animation.configure(stiffness: 300, damping: 30)
        animation.toValue = value
        animation.resolvingEpsilon = (threshold as? Value.SIMDType.EpsilonType) ?? 0.01
        animation.completion = completion
        animation.start()
    }

    func pause() {
        animation.stop()
    }

    func shift(progress: CGFloat) {
        let newValueVector = Double(progress) * (presentedValue.simdRepresentation() - dismissedValue.simdRepresentation()) + currentValue.simdRepresentation()
        currentValue = Value(newValueVector)
    }
}

struct TransitionAnimator {
    private var children: [AnyHashable: AnyStateAnimator]
    private var completion: (TransitionEndPosition) -> Void

    init(completion: @escaping (TransitionEndPosition) -> Void) {
        children = [:]
        self.completion = completion
    }

    mutating func add<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: WritableKeyPath<View, Value>, presentedValue: Value, dismissedValue: Value) where Value.SIMDType.Scalar == CGFloat.NativeType {
        let animation = SpringAnimation(initialValue: view[keyPath: keyPath])
        animation.configure(stiffness: 300, damping: 30)
        animation.onValueChanged { [weak view] value in
            view?[keyPath: keyPath] = value
        }
        let animator = StateAnimator(animation: animation, presentedValue: presentedValue, dismissedValue: dismissedValue)
        let animatorId = AnimatorID(view: view, keypath: keyPath)
        children[animatorId] = animator
    }

    private func animatorFor<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: WritableKeyPath<View, Value>) -> StateAnimator<Value>? {
        let animatorId = AnimatorID(view: view, keypath: keyPath)
        return children[animatorId] as? StateAnimator<Value>
    }

    func seekTo(position: TransitionEndPosition) {
        for child in children.values {
            child.seekTo(position: position)
        }
    }

    func animateTo(position: TransitionEndPosition) {
        let dispatchGroup = DispatchGroup()
        for child in children.values {
            dispatchGroup.enter()
            child.animateTo(position: position) {
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) {
            completion(position)
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
