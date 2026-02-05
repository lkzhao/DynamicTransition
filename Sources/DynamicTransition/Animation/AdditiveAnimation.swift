//
//  AdditiveAnimation.swift
//  
//
//  Created by Luke Zhao on 11/13/23.
//

import UIKit
import Motion

public class AdditiveAnimation<Target: AnyObject, Value: SIMDRepresentable> {
    internal let target: AnimationTarget<Target, Value>
    internal let offsetAnimation: SpringAnimation<Value>

    public convenience init(target: Target, keyPath: ReferenceWritableKeyPath<Target, Value>) {
        self.init(target: AnimationTarget(target: target, keyPath: keyPath))
    }

    internal init(target: AnimationTarget<Target, Value>) {
        self.target = target
        offsetAnimation = SpringAnimation(initialValue: .zero)
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
            offsetAnimation.value
        }
        set {
            offsetAnimation.updateValue(to: newValue, postValueChanged: true)
        }
    }

    public var velocity: Value {
        get {
            offsetAnimation.velocity
        }
        set {
            offsetAnimation.velocity = newValue
        }
    }

    public var targetOffsetValue: Value {
        get {
            offsetAnimation.toValue
        }
        set {
            offsetAnimation.toValue = newValue
        }
    }

    public func animate(
        toOffset: Value,
        response: Double = 0.3,
        dampingRatio: Double = 1.0,
        completion: (() -> Void)? = nil
    ) {
        let threshold = max(0.1, self.currentOffsetValue.distance(between: toOffset)) * 0.005
        let epsilon = (threshold as? Value.SIMDType.EpsilonType) ?? 0.01
        if self.currentOffsetValue.simdRepresentation().isApproximatelyEqual(to: toOffset.simdRepresentation(), epsilon: epsilon) {
            completion?()
        } else {
            offsetAnimation.configure(response: Value.SIMDType.Scalar(response),
                                dampingRatio: Value.SIMDType.Scalar(dampingRatio))
            offsetAnimation.toValue = toOffset
            offsetAnimation.resolvingEpsilon = epsilon
            offsetAnimation.completion = completion
            offsetAnimation.start()
        }
    }

    public func stop() {
        offsetAnimation.stop()
    }
}


private class AdditiveCummulator<View: AnyObject, Value: SIMDRepresentable> {
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

    func add<Target: AnyObject, Value: SIMDRepresentable>(animation: AdditiveAnimation<Target, Value>) {
        if children[animation.target] == nil {
            children[animation.target] = AdditiveCummulator(target: animation.target)
        }
        (children[animation.target]! as! AdditiveCummulator<Target, Value>).add(animation: animation.offsetAnimation)
    }

    func baseValue<Target: AnyObject, Value: SIMDRepresentable>(target: AnimationTarget<Target, Value>) -> Value {
        (children[target] as? AdditiveCummulator<Target, Value>)?.baseValue ?? target.value
    }

    func setBaseValue<Target: AnyObject, Value: SIMDRepresentable>(target: AnimationTarget<Target, Value>, value: Value) {
        if let cummulator = children[target] as? AdditiveCummulator<Target, Value> {
            cummulator.baseValue = value
        } else {
            target.value = value
        }
    }

    func remove<Target: AnyObject, Value: SIMDRepresentable>(animation: AdditiveAnimation<Target, Value>) {
        guard let child = children[animation.target] as? AdditiveCummulator<Target, Value> else { return }
        child.remove(animation: animation.offsetAnimation)
        if child.animations.isEmpty {
            children[animation.target] = nil
        }
    }
}
