//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/7/23.
//

import Foundation
import UIKit
@_spi(CustomPresentation) import BaseToolbox

func setupCustomPresentation() {
    BaseToolbox.customPushMethod = { (view, viewController) in
        if let navigationController = view.parentNavigationController {
            navigationController.pushViewController(viewController, animated: true)
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

extension UIView {
    private static var lockedSafeAreaInsets: [UIView: UIEdgeInsets] = [:]

    private static let swizzleSafeAreaInsets: Void = {
        guard let originalMethod = class_getInstanceMethod(UIView.self, #selector(getter: safeAreaInsets)),
              let swizzledMethod = class_getInstanceMethod(UIView.self, #selector(getter: swizzled_safeAreaInsets))
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    var lockSafeAreaInsets: Bool {
        get {
            Self.lockedSafeAreaInsets[self] != nil
        }
        set {
            _ = UIView.swizzleSafeAreaInsets
            Self.lockedSafeAreaInsets[self] = newValue ? safeAreaInsets : nil
        }
    }

    @objc var swizzled_safeAreaInsets: UIEdgeInsets {
        if !Self.lockedSafeAreaInsets.isEmpty,
            let lockedInsetSuperview = superviewPassing(test: { Self.lockedSafeAreaInsets[$0] != nil }),
            let superviewInset = Self.lockedSafeAreaInsets[lockedInsetSuperview] {
            let frame = lockedInsetSuperview.convert(bounds, from: self)
            let superviewBounds = lockedInsetSuperview.bounds.inset(by: superviewInset)
            return UIEdgeInsets(top: max(0, superviewBounds.minY - frame.minY),
                                left: max(0, superviewBounds.minX - frame.minX),
                                bottom: max(0, frame.maxY - superviewBounds.maxY),
                                right: max(0, frame.maxX - superviewBounds.maxX))
        }
        return self.swizzled_safeAreaInsets
    }
}
