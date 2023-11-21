// Transition.swift
// Copyright © 2020 Noto. All rights reserved.

import UIKit

public protocol TransitionProvider {
    func transitionFor(presenting: Bool, otherView: UIView) -> Transition?
}

public protocol RootViewType: UIView {
    func willAppear(animated: Bool)
    func didAppear(animated: Bool)
    func willDisappear(animated: Bool)
    func didDisappear(animated: Bool)

    var preferredStatusBarStyle: UIStatusBarStyle { get }
}

extension RootViewType {
    func willAppear(animated: Bool) {}
    func didAppear(animated: Bool) {}
    func willDisappear(animated: Bool) {}
    func didDisappear(animated: Bool) {}

    var preferredStatusBarStyle: UIStatusBarStyle { .default }
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

    // Optional. Reverse the transition if possible.
    // This method needs to call `context.beginInteractiveTransition()` and
    // `context.endInteractiveTransition(_ isCompleting: Bool)`
    // if it can execute the reversal
    func reverse()
}

extension Transition {
    public var wantsInteractiveStart: Bool { false }
    public func canTransitionSimutanously(with transition: Transition) -> Bool { false }
    public func reverse() {
        // no-op
    }
}

public protocol TransitionContext {
    var from: UIView { get }
    var to: UIView { get }
    var container: UIView { get }
    var isPresenting: Bool { get }

    func completeTransition(_ didComplete: Bool)

    // interactive
    func beginInteractiveTransition()
    func endInteractiveTransition(_ isCompleting: Bool)
}

public extension TransitionContext {
    var foreground: UIView {
        isPresenting ? to : from
    }
    var background: UIView {
        isPresenting ? from : to
    }
}
