//
//  NoTransition.swift
//  
//
//  Created by Luke Zhao on 5/25/24.
//

import Foundation

public class NoTransition: NSObject, Transition {
    public func animateTransition(context: TransitionContext) {
        let container = context.container
        let from = context.from
        let to = context.to

        to.frame = container.bounds
        container.addSubview(to)
        to.setNeedsLayout()
        to.layoutIfNeeded()

        from.removeFromSuperview()
        context.completeTransition()
    }
}
