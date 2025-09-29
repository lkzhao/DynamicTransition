//
//  AdditiveAnimation.swift
//  
//
//  Created by Luke Zhao on 11/13/23.
//

import UIKit
import Motion

public class AdditiveAnimation<View: UIView, Value: SIMDRepresentable> {

    public enum AdditiveAnimationConfig {
        case spring(response: Double, dampingRatio: Double)
        case curve(easingFunction: EasingFunction<Value.SIMDType>, duration: Double)
    }

    internal let target: AnimationTarget<View, Value>
    internal var valueAnimation: ValueAnimation<Value>

    internal var onValueChanged: (() -> Void)?

    public convenience init(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) {
        self.init(target: AnimationTarget(view: view, keyPath: keyPath))
    }

    internal init(target: AnimationTarget<View, Value>) {
        self.target = target
        self.valueAnimation = BasicAnimation()
        valueAnimation.onValueChanged { [weak self] value in
            self?.onValueChanged?()
        }
        AdditiveAnimationManager.shared.add(animation: self)
    }

    deinit {
        AdditiveAnimationManager.shared.remove(animation: self)
    }

    public var baseValue: Value {
        get {
            AdditiveAnimationManager.shared.baseValue(target: target)
        }
        set {
            AdditiveAnimationManager.shared.setBaseValue(target: target, value: newValue)
        }
    }
    
    public var currentOffsetValue: Value {
        get {
            valueAnimation.value
        }
        set {
            valueAnimation.updateValue(to: newValue, postValueChanged: true)
        }
    }

    public var velocity: Value {
        get {
            valueAnimation.velocity
        }
        set {
            valueAnimation.velocity = newValue
        }
    }

    public var targetOffsetValue: Value {
        get {
            valueAnimation.toValue
        }
        set {
            valueAnimation.toValue = newValue
        }
    }

    public func animate(
        toOffset: Value,
        configuration: AdditiveAnimationConfig = .spring(response: 0.3, dampingRatio: 1.0),
        completion: (() -> Void)? = nil
    ) {
        let threshold = max(0.1, self.currentOffsetValue.distance(between: toOffset)) * 0.005
        let epsilon = (threshold as? Value.SIMDType.EpsilonType) ?? 0.01
        if self.currentOffsetValue.simdRepresentation().isApproximatelyEqual(to: toOffset.simdRepresentation(), epsilon: epsilon) {
            completion?()
        } else {
            switch configuration {
            case .spring(let response, let dampingRatio):
                let springAnimation = SpringAnimation<Value>()
                springAnimation.configure(response: Value.SIMDType.Scalar(response),
                                          dampingRatio: Value.SIMDType.Scalar(dampingRatio))
                springAnimation.updateValue(to: currentOffsetValue, postValueChanged: false)
                springAnimation.toValue = toOffset
                springAnimation.resolvingEpsilon = epsilon
                springAnimation.completion = completion
                springAnimation.onValueChanged { [weak self] value in
                    self?.onValueChanged?()
                }
                valueAnimation = springAnimation
                springAnimation.start()
            case .curve(let easingFunction, let duration):
                let animation = BasicAnimation<Value>()
                animation.easingFunction = easingFunction
                animation.duration = duration
                animation.toValue = toOffset
                animation.updateValue(to: currentOffsetValue, postValueChanged: false)
                animation.onValueChanged { [weak self] value in
                    self?.onValueChanged?()
                }
                animation.completion = completion
                valueAnimation = animation
                animation.start()
            }
        }
    }

    public func stop() {
        valueAnimation.stop()
        AdditiveAnimationManager.shared.remove(animation: self)
    }
}

struct WeakBox<T: AnyObject>: Hashable {
    weak var value: T?

    init(value: T) {
        self.value = value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(value!))
    }

    static func == (lhs: WeakBox<T>, rhs: WeakBox<T>) -> Bool {
        return lhs.value === rhs.value
    }
}

private class AdditiveCummulator<View: UIView, Value: SIMDRepresentable> {
    let target: AnimationTarget<View, Value>

    var baseValue: Value
    var animations: [WeakBox<AdditiveAnimation<View, Value>>] = []

    init(target: AnimationTarget<View, Value>) {
        self.target = target
        self.baseValue = target.value
    }

    func add(animation: AdditiveAnimation<View, Value>) {
        animations.removeAll(where: { $0.value == nil })
        animations.append(.init(value: animation))
        animation.onValueChanged = { [weak self] in
            self?.animationDidUpdate()
        }
    }

    func remove(animation: AdditiveAnimation<View, Value>) {
        animations = animations.filter { $0.value !== animation }
        animationDidUpdate()
    }

    func animationDidUpdate() {
        let valueSIMD = animations.reduce(baseValue.simdRepresentation(), { partialResult, anim in
            partialResult + (anim.value?.valueAnimation.value.simdRepresentation() ?? .zero)
        })
        target.value = Value(valueSIMD)
    }
}

private class AdditiveAnimationManager {
    static let shared = AdditiveAnimationManager()
    var children: [AnyHashable: Any] = [:]

    func add<View:UIView, Value: SIMDRepresentable>(animation: AdditiveAnimation<View, Value>) {
        if children[animation.target] == nil {
            children[animation.target] = AdditiveCummulator(target: animation.target)
        }
        (children[animation.target]! as! AdditiveCummulator<View, Value>).add(animation: animation)
    }

    func baseValue<View:UIView, Value: SIMDRepresentable>(target: AnimationTarget<View, Value>) -> Value {
        (children[target] as? AdditiveCummulator<View, Value>)?.baseValue ?? target.value
    }

    func setBaseValue<View:UIView, Value: SIMDRepresentable>(target: AnimationTarget<View, Value>, value: Value) {
        if let cummulator = children[target] as? AdditiveCummulator<View, Value> {
            cummulator.baseValue = value
        } else {
            target.value = value
        }
    }

    func remove<View: UIView, Value: SIMDRepresentable>(animation: AdditiveAnimation<View, Value>) {
        guard let child = children[animation.target] as? AdditiveCummulator<View, Value> else { return }
        child.remove(animation: animation)
        if child.animations.isEmpty {
            children[animation.target] = nil
        }
    }
}
