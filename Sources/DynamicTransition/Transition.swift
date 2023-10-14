// Transition.swift
// Copyright © 2020 Noto. All rights reserved.

import UIKit

public protocol TransitionProvider {
    func transitionFor(presenting: Bool, otherViewController: UIViewController) -> Transition?
}

public protocol Transition {
    func animateTransition(context: TransitionContext)
}

public protocol TransitionContext {
    var from: UIViewController { get }
    var to: UIViewController { get }
    var container: UIView { get }
    var isPresenting: Bool { get }

    func completeTransition(_ didComplete: Bool)
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
