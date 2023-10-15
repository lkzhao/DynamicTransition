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
    let keypath: ReferenceWritableKeyPath<View, Value>
}

private class StateAnimator<Value: SIMDRepresentable>: AnyStateAnimator where Value.SIMDType.Scalar == Double {

    let animation: Motion.SpringAnimation<Value>

    var presentedValue: Value {
        didSet {
            if targetPosition == .presented {
                animation.toValue = presentedValue
            }
        }
    }
    var dismissedValue: Value {
        didSet {
            if targetPosition == .dismissed {
                animation.toValue = dismissedValue
            }
        }
    }
    var currentValue: Value {
        get {
            animation.value
        }
        set {
            animation.updateValue(to: newValue, postValueChanged: true)
        }
    }
    var currentVelocity: Value {
        get {
            animation.velocity
        }
        set {
            animation.velocity = newValue
        }
    }
    private(set) var targetPosition: TransitionEndPosition?

    init(animation: Motion.SpringAnimation<Value>) {
        self.animation = animation
        self.presentedValue = animation.value
        self.dismissedValue = animation.value
    }

    func seekTo(position: TransitionEndPosition) {
        currentValue = position == .presented ? presentedValue : dismissedValue
    }

    func animateTo(position: TransitionEndPosition, completion: @escaping () -> Void) {
        let value = position == .presented ? presentedValue : dismissedValue
        let threshold = max(1, animation.value.distance(between: value)) * 0.005
        let epsilon = (threshold as? Value.SIMDType.EpsilonType) ?? 0.01
        targetPosition = position
        if animation.value.simdRepresentation().approximatelyEqual(to: value.simdRepresentation(), epsilon: epsilon) {
            // value already there
            completion()
        } else {
            animation.configure(stiffness: 300, damping: 30)
            animation.toValue = value
            animation.resolvingEpsilon = epsilon
            animation.completion = completion
            animation.start()
        }
    }

    func pause() {
        targetPosition = nil
        animation.stop()
    }

    func shift(progress: CGFloat) {
        let newValueVector = Double(progress) * (presentedValue.simdRepresentation() - dismissedValue.simdRepresentation()) + currentValue.simdRepresentation()
        currentValue = Value(newValueVector)
    }
}

class TransitionAnimator {
    private var children: [AnyHashable: AnyStateAnimator]
    private var completion: (TransitionEndPosition) -> Void
    private var independent: Set<AnyHashable> = []

    private(set) var targetPosition: TransitionEndPosition? = nil
    var isAnimating: Bool {
        targetPosition != nil
    }

    init(completion: @escaping (TransitionEndPosition) -> Void) {
        children = [:]
        self.completion = completion
    }

    func set<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>, presentedValue: Value, dismissedValue: Value) where Value.SIMDType.Scalar == Double {
        self[view, keyPath].presentedValue = presentedValue
        self[view, keyPath].dismissedValue = dismissedValue
    }

    func setPresentedValue<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>, value: Value) where Value.SIMDType.Scalar == Double {
        self[view, keyPath].presentedValue = value
    }

    func setDismissedValue<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>, value: Value) where Value.SIMDType.Scalar == Double {
        self[view, keyPath].dismissedValue = value
    }

    func setCurrentValue<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>, value: Value) where Value.SIMDType.Scalar == Double {
        _ = independent.insert(AnimatorID(view: view, keypath: keyPath))
        self[view, keyPath].currentValue = value
    }

    func setVelocity<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>, velocity: Value) where Value.SIMDType.Scalar == Double {
        self[view, keyPath].animation.velocity = velocity
    }

    func currentValue<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) -> Value where Value.SIMDType.Scalar == Double {
        self[view, keyPath].currentValue
    }

    func presentedValue<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) -> Value where Value.SIMDType.Scalar == Double {
        self[view, keyPath].presentedValue
    }

    func dismissedValue<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) -> Value where Value.SIMDType.Scalar == Double {
        self[view, keyPath].dismissedValue
    }

    private subscript<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) -> StateAnimator<Value> {
        let key = AnimatorID(view: view, keypath: keyPath)
        if let animator = children[key] as? StateAnimator<Value> {
            return animator
        } else {
            let animation = SpringAnimation(initialValue: view[keyPath: keyPath])
            animation.configure(stiffness: 300, damping: 30)
            animation.onValueChanged { [weak view] value in
                view?[keyPath: keyPath] = value
            }
            let animator = StateAnimator(animation: animation)
            children[key] = animator
            return animator
        }
    }

    func seekTo(position: TransitionEndPosition) {
        for child in children.values {
            child.seekTo(position: position)
        }
    }

    func animateTo(position: TransitionEndPosition) {
        independent.removeAll()
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


    func pause() {
        targetPosition = nil
        for child in children.values {
            child.pause()
        }
    }

    func shift(progress: CGFloat) {
        for (key, child) in children where !independent.contains(key) {
            child.shift(progress: progress)
        }
    }
}
