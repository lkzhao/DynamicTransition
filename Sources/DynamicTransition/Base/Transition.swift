// Transition.swift
// Copyright © 2020 Noto. All rights reserved.

import UIKit

public protocol TransitionContext {
    var from: UIViewController { get }
    var to: UIViewController { get }
    var container: UIView { get }
    var isPresenting: Bool { get }

    func completeTransition(_ didComplete: Bool)
}

public protocol Transition {
    func animateTransition(context: TransitionContext)
}

public extension TransitionContext {
    var foreground: UIViewController {
        isPresenting ? to : from
    }
    var background: UIViewController {
        isPresenting ? from : to
    }
}
