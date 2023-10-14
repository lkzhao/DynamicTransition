//
//  MatchTransition.swift
//
//  Created by Luke Zhao on 10/6/23.
//

import UIKit
import YetAnotherAnimationLibrary
import ScreenCorners
import BaseToolbox

public protocol MatchTransitionDelegate {
    /// Provide the matched view from the current object's own view hierarchy for the match transition
    func matchedViewFor(transition: TransitionContext, otherViewController: UIViewController) -> UIView?
}

public struct MatchTransitionOptions {
    public var onDragStart: ((MatchTransition) -> ())?
}

/// A Transition that matches two items and transitions between them.
///
/// The foreground view will be masked to the item and expand as the transition
/// progress. This transition is interruptible if `isUserInteractionEnabled` is set to true.
///
open class MatchTransition: NSObject, Transition {
    /// Global transition options
    public static var defaultOptions = MatchTransitionOptions()

    /// Transition options
    open var options = MatchTransition.defaultOptions

    /// Dismiss gesture recognizer, add this to your view to support drag to dismiss
    open lazy var verticalDismissGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
        if #available(iOS 13.4, *) {
            $0.allowedScrollTypesMask = .all
        }
    }
    open lazy var horizontalDismissGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
        if #available(iOS 13.4, *) {
            $0.allowedScrollTypesMask = .all
        }
    }
    private lazy var interruptibleVerticalDismissGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
        if #available(iOS 13.4, *) {
            $0.allowedScrollTypesMask = .all
        }
    }
    private lazy var interruptibleHorizontalDismissGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
        if #available(iOS 13.4, *) {
            $0.allowedScrollTypesMask = .all
        }
    }

    var isTransitioningVertically = false

    private var runner: MatchTransitionRunner?
    private var isInteractive: Bool = false
    private var startTime: TimeInterval = 0

    public func animateTransition(context: TransitionContext) {
        print("Start transition isPresenting: \(context.isPresenting)")
        guard runner == nil else {
            return
        }
        let front = context.foreground.view!
        startTime = CACurrentMediaTime()

        CATransaction.begin()
        let runner = MatchTransitionRunner(context: context,
                                           isTransitioningVertically: isTransitioningVertically) { [weak self] finished in
            self?.didCompleteTransition(finished: finished)
        }
        self.runner = runner
        if context.isPresenting {
            interruptibleVerticalDismissGestureRecognizer.isEnabled = true
            interruptibleHorizontalDismissGestureRecognizer.isEnabled = true
            runner.container.addGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
            runner.container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
            verticalDismissGestureRecognizer.isEnabled = false
            horizontalDismissGestureRecognizer.isEnabled = false
            runner.apply(state: runner.dismissedState, animated: false, completion: nil)
        } else {
            runner.apply(state: runner.presentedState, animated: false, completion: nil)
        }
        CATransaction.commit()
        if !isInteractive {
            runner.completeTransition(shouldFinish: true)
        }
    }

    func didCompleteTransition(finished: Bool) {
        let duration = CACurrentMediaTime() - startTime
        let runner = runner
        isInteractive = false
        self.runner = nil
        verticalDismissGestureRecognizer.isEnabled = true
        horizontalDismissGestureRecognizer.isEnabled = true
        delay {
            print("Complete transition finished:\(finished) duration:\(duration)")
            runner?.onCompletion(finished: finished)
        }
    }

    func beginInteractiveTransition() {
        isInteractive = true
        runner?.pause()
    }

    var totalTranslation: CGPoint = .zero
    @objc func handlePan(gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        func progressFrom(offset: CGPoint) -> CGFloat {
            guard let runner else { return 0 }
            let container = runner.container
            let maxAxis = max(container.bounds.width, container.bounds.height)
            let progress = (offset.x / maxAxis + offset.y / maxAxis) * 1.5
            return runner.isPresenting ? -progress : progress
        }
        switch gr.state {
        case .began:
            options.onDragStart?(self)
            beginInteractiveTransition()
            if runner == nil {
                if let vc = view.parentNavigationController, vc.viewControllers.count > 1 {
                    vc.popViewController(animated: true)
                }
            }
            totalTranslation = .zero
        case .changed:
            guard let runner else { return }
            let translation = gr.translation(in: nil)
            gr.setTranslation(.zero, in: nil)
            totalTranslation += translation
            let progress = progressFrom(offset: translation)
            if runner.isMatched {
                let newCenter = runner.foregroundContainerView.center + translation * 0.5
                let rotation = runner.foregroundContainerView.yaal.rotation.value.value + translation.x * 0.0003
                runner.add(progress: progress, newCenter: newCenter, rotation: rotation)
            } else {
                let newCenter = runner.foregroundContainerView.center + translation
                let rotation = runner.foregroundContainerView.yaal.rotation.value.value + translation.x * 0.0003
                runner.add(progress: progress, newCenter: newCenter, rotation: rotation)
            }
        default:
            guard let runner else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            let shouldFinish = runner.isPresenting ? !shouldDismiss : shouldDismiss
            if shouldDismiss {
                interruptibleVerticalDismissGestureRecognizer.isEnabled = false
                interruptibleHorizontalDismissGestureRecognizer.isEnabled = false
                runner.foregroundContainerView.isUserInteractionEnabled = false
                runner.overlayView.isUserInteractionEnabled = false
            }
            if runner.isMatched {
                runner.foregroundContainerView.yaal.center.velocity.value = velocity
            } else {
                runner.foregroundContainerView.yaal.center.velocity.value = velocity
                let angle = translationPlusVelocity / runner.container.bounds.size
                let targetOffset = angle / angle.distance(.zero) * 1.4 * runner.container.bounds.size
                let targetRotation = runner.foregroundContainerView.yaal.rotation.value.value + translationPlusVelocity.x * 0.0001
                runner.dismissedState.foregroundContainerFrame = runner.container.bounds + targetOffset
                runner.dismissedState.foregroundContainerRotation = targetRotation
            }
            runner.completeTransition(shouldFinish: shouldFinish)
        }
    }
}

extension MatchTransition: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
            if velocity.y > abs(velocity.x) {
                isTransitioningVertically = true
                return true
            }
        } else if gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
            if velocity.x > abs(velocity.y) {
                isTransitioningVertically = false
                return true
            }
        }
        return false
    }

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer, let scrollView = otherGestureRecognizer.view as? UIScrollView, otherGestureRecognizer == scrollView.panGestureRecognizer {
            if scrollView.contentSize.height > scrollView.bounds.height, gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
                return scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
            }
            return true
        }
        return false
    }
}
