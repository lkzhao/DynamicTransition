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

    public var reversed: Self {
        switch self {
        case .dismissed:
            return .presented
        case .presented:
            return .dismissed
        }
    }
}

public class TransitionAnimator {
    private var children: [AnyHashable: AnyTransitionPropertyAnimator] = [:]
    private var completions: [(TransitionEndPosition) -> Void] = []

    public private(set) var targetPosition: TransitionEndPosition? = nil
    public var isAnimating: Bool {
        targetPosition != nil
    }

    public init() {
    }

    public subscript<View: UIView, Value: SIMDRepresentable>(view: View, keyPath: ReferenceWritableKeyPath<View, Value>) -> TransitionPropertyAnimator<View, Value> {
        let target = AnimationTarget(view: view, keyPath: keyPath)
        if let animator = children[target] as? TransitionPropertyAnimator<View, Value> {
            return animator
        } else {
            let animator = TransitionPropertyAnimator<View, Value>(target: target)
            children[target] = animator
            return animator
        }
    }

    public func addCompletion(_ block: @escaping (TransitionEndPosition) -> Void) {
        completions.append(block)
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
            for completion in self?.completions.reversed() ?? [] {
                completion(position)
            }
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
