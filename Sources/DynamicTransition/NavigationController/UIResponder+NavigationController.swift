//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/9/23.
//

import UIKit

public extension UIResponder {
    @objc var parentNavigationController: NavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let current = current as? NavigationController {
                return current
            }
            responder = current.next
        }
        return nil
    }
}
