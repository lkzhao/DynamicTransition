//
//  AdditiveAnimation.swift
//  
//
//  Created by Luke Zhao on 11/13/23.
//

import UIKit
import Motion

public class AdditiveAnimation<View: UIView, Value: SIMDRepresentable> {
    internal let target: AnimationTarget<View, Value>
    internal let animation: SpringAnimation<Value>

    public convenience init(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) {
        self.init(target: AnimationTarget(view: view, keyPath: keyPath))
    }

    internal init(target: AnimationTarget<View, Value>) {
        self.target = target
        animation = SpringAnimation(initialValue: .zero)
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

    public var toValue: Value {
        get {
            animation.toValue
        }
        set {
            animation.toValue = newValue
        }
    }

    public func animate(
        to toValue: Value,
        response: Double = 0.3,
        dampingRatio: Double = 1.0,
        completion: (() -> Void)? = nil
    ) {
        let threshold = max(0.1, self.value.distance(between: toValue)) * 0.005
        let epsilon = (threshold as? Value.SIMDType.EpsilonType) ?? 0.01
        if self.value.simdRepresentation().approximatelyEqual(to: toValue.simdRepresentation(), epsilon: epsilon) {
            completion?()
        } else {
            animation.configure(response: Value.SIMDType.Scalar(response),
                                dampingRatio: Value.SIMDType.Scalar(dampingRatio))
            animation.toValue = toValue
            animation.resolvingEpsilon = epsilon
            animation.completion = completion
            animation.start()
        }
    }

    public func stop() {
        animation.stop()
    }
}


private class AdditiveCummulator<View: UIView, Value: SIMDRepresentable> {
    let target: AnimationTarget<View, Value>

    var baseValue: Value
    var animations: [Motion.ValueAnimation<Value>] = []

    init(target: AnimationTarget<View, Value>) {
        self.target = target
        self.baseValue = target.value
    }

    func add(animation: Motion.ValueAnimation<Value>) {
        animation.onValueChanged { [weak self] value in
            self?.animationDidUpdate()
        }
        animations.append(animation)
    }

    func remove(animation: Motion.ValueAnimation<Value>) {
        animations = animations.filter { $0 != animation }
        animationDidUpdate()
    }

    func animationDidUpdate() {
        let valueSIMD = animations.reduce(baseValue.simdRepresentation(), { partialResult, anim in
            partialResult + anim.value.simdRepresentation()
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
        (children[animation.target]! as! AdditiveCummulator<View, Value>).add(animation: animation.animation)
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
        child.remove(animation: animation.animation)
        if child.animations.isEmpty {
            children[animation.target] = nil
        }
    }
}
