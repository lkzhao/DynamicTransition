//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/7/23.
//

import Foundation
import UIKit
@_spi(CustomPresentation) import BaseToolbox

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

func setupCustomPresentation() {
    BaseToolbox.customPushMethod = { (view, viewController) in
        if let navigationController = view.parentNavigationController {
            navigationController.push(viewController, animated: true)
        } else if let navigationController = view.parentViewController?.navigationController {
            navigationController.pushViewController(viewController, animated: true)
        }
    }
    BaseToolbox.customDismissMethod = { (view, completion) in
        guard let parentViewController = view.parentViewController else {
            return
        }
        if let navVC = parentViewController.navigationController, navVC.viewControllers.count > 1 {
            navVC.popViewController(animated: true)
            completion?()
        } else if let navVC = parentViewController.parentNavigationController, navVC.viewControllers.count > 1 {
            navVC.popViewController(animated: true)
            completion?()
        } else {
            parentViewController.dismiss(animated: true, completion: completion)
        }
    }
}

extension UIView {
    fileprivate func findViewMatchType<T>(_ type: T.Type) -> T? {
        if let view = self as? T {
            return view
        } else {
            for child in subviews.reversed() {
                if let match = child.findViewMatchType(type) {
                    return match
                }
            }
        }
        return nil
    }
}

extension UIViewController {
    internal func findObjectMatchType<T>(_ type: T.Type) -> T? {
        if let match = findViewControllerMatchType(type) {
            return match
        }
        if let match = view.findViewMatchType(type) {
            return match
        }
        return nil
    }

    fileprivate func findViewControllerMatchType<T>(_ type: T.Type) -> T? {
        if let viewController = self as? T {
            return viewController
        } else {
            for child in children.reversed() {
                if let match = child.findViewControllerMatchType(type) {
                    return match
                }
            }
        }
        return nil
    }
}
