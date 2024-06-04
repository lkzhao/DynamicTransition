//
//  ExampleNavigationController.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 6/4/24.
//

import DynamicTransition

class ExampleNavigationController: NavigationController {
    override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionBegan(motion, with: event)
        if motion == .motionShake {
            printState()
        }
    }
}
