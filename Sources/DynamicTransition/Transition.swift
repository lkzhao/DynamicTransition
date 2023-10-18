// Transition.swift
// Copyright © 2020 Noto. All rights reserved.

import UIKit

public protocol TransitionProvider {
    func transitionFor(presenting: Bool, otherViewController: UIViewController) -> Transition?
}

public protocol Transition: AnyObject {
    // Required
    func animateTransition(context: TransitionContext)

    // Optional. Does the animation wants interactive start.
    // If true, then the transition doesn't require to call `context.beginInteractiveTransition()`
    // but it has to call `context.endInteractiveTransition(_ isCompleting: Bool)` when the interactive transition ends.
    // Default: false
    var wantsInteractiveStart: Bool { get }

    // Optional. Simutanous transition
    // Whether or not the transition can be performed simutanously with another transition
    // Default: false
    func canTransitionSimutanously(with transition: Transition) -> Bool

    func reverse()
}

extension Transition {
    public var wantsInteractiveStart: Bool { false }
    public func canTransitionSimutanously(with transition: Transition) -> Bool { false }
}

public protocol TransitionContext {
    var from: UIViewController { get }
    var to: UIViewController { get }
    var container: UIView { get }
    var isPresenting: Bool { get }

    func completeTransition(_ didComplete: Bool)

    // interactive
    func beginInteractiveTransition()
    func endInteractiveTransition(_ isCompleting: Bool)
}

public extension TransitionContext {
    var foreground: UIViewController {
        isPresenting ? to : from
    }
    var background: UIViewController {
        isPresenting ? from : to
    }
    var foregroundView: UIView {
        foreground.view
    }
    var backgroundView: UIView {
        background.view
    }
}
