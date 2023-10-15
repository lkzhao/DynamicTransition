//
//  MatchTransition.swift
//
//  Created by Luke Zhao on 10/6/23.
//

import UIKit
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

    private var context: TransitionContext?
    private var animator: TransitionAnimator?
    private var isInteractive: Bool = false
    private var startTime: TimeInterval = 0
    
    let foregroundContainerView = MatchTransitionContainerView()
    var matchedSourceView: UIView?
    var matchedDestinationView: UIView?
    var sourceViewSnapshot: UIView?
    var scrollViewObserver: Any?
    let overlayView = UIView().with {
        $0.backgroundColor = UIColor(dark: .black.withAlphaComponent(0.6), light: .black.withAlphaComponent(0.4))
    }
    var isMatched: Bool {
        matchedSourceView != nil
    }

    public func animateTransition(context: TransitionContext) {
        print("Start transition isPresenting: \(context.isPresenting)")
        guard self.context == nil else {
            return
        }
        startTime = CACurrentMediaTime()
        self.context = context

        CATransaction.begin()
        let container = context.container
        let foreground = context.foreground
        let background = context.background

        foregroundContainerView.frame = container.bounds
        foregroundContainerView.backgroundColor = foreground.view.backgroundColor

        container.addSubview(background.view)
        container.addSubview(overlayView)
        container.addSubview(foregroundContainerView)
        foregroundContainerView.contentView.addSubview(foreground.view)

        overlayView.isUserInteractionEnabled = true
        overlayView.frame = container.bounds
        foreground.view.frame = container.bounds
        foreground.view.setNeedsLayout()
        foreground.view.layoutIfNeeded()
        foregroundContainerView.lockSafeAreaInsets = true

        let matchedDestinationView = context.foreground.findObjectMatchType(MatchTransitionDelegate.self)?
            .matchedViewFor(transition: context, otherViewController: context.background)
        let matchedSourceView = context.background.findObjectMatchType(MatchTransitionDelegate.self)?
            .matchedViewFor(transition: context, otherViewController: context.foreground)

        self.matchedSourceView = matchedSourceView
        self.matchedDestinationView = matchedDestinationView

        if let matchedSourceView, let sourceViewSnapshot = matchedSourceView.snapshotView(afterScreenUpdates: true) {
            foregroundContainerView.contentView.addSubview(sourceViewSnapshot)
            self.sourceViewSnapshot = sourceViewSnapshot
            matchedSourceView.isHidden = true
            if let parentScrollView = matchedSourceView.superview as? UIScrollView {
                scrollViewObserver = parentScrollView.observe(\UIScrollView.contentOffset, options: .new) { table, change in
                    self.targetDidChange()
                }
            }
        }

        container.addGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)

        let animator = TransitionAnimator { position in
            self.didCompleteTransitionAnimation(position: position)
        }
        self.animator = animator

        calculateEndStates()

        animator.seekTo(position: context.isPresenting ? .dismissed : .presented)
        CATransaction.commit()

        if !isInteractive {
            animator.animateTo(position: context.isPresenting ? .presented : .dismissed)
        }
    }

    func calculateEndStates() {
        guard let context, let animator else { return }
        let container = context.container
        let defaultDismissedFrame = isTransitioningVertically ? container.bounds.offsetBy(dx: 0, dy: container.bounds.height) : container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
        let dismissedFrame = matchedSourceView.map {
            container.convert($0.bounds, from: $0)
        } ?? defaultDismissedFrame
        let presentedFrame = isMatched ? matchedDestinationView.map {
            container.convert($0.bounds, from: $0)
        } ?? container.bounds : container.bounds

        let isFullScreen = container.window?.convert(container.bounds, from: container) == container.window?.bounds
        let presentedCornerRadius = isFullScreen ? UIScreen.main.displayCornerRadius : 0
        let dismissedCornerRadius = matchedSourceView?.cornerRadius ?? presentedCornerRadius
        let containerPresentedFrame = container.bounds
        let containerDismissedFrame = dismissedFrame

        let scaledSize = presentedFrame.size.size(fill: dismissedFrame.size)
        let scale = scaledSize.width / container.bounds.width
        let sizeOffset = -(scaledSize - dismissedFrame.size) / 2
        let originOffset = -presentedFrame.minY * scale
        let offsetX = -(1 - scale) / 2 * container.bounds.width
        let offsetY = -(1 - scale) / 2 * container.bounds.height
        let offset = CGPoint(
            x: offsetX + sizeOffset.width,
            y: offsetY + sizeOffset.height + originOffset)

        let foregroundView = context.foregroundView

        animator.set(view: overlayView, keyPath: \.alpha, presentedValue: 1, dismissedValue: 0)
        animator.set(view: foregroundContainerView, keyPath: \.shadowOpacity, presentedValue: 1, dismissedValue: 0)
        animator.set(view: foregroundContainerView, keyPath: \.cornerRadius, presentedValue: presentedCornerRadius, dismissedValue: dismissedCornerRadius)
        animator.set(view: foregroundContainerView, keyPath: \.bounds.size, presentedValue: containerPresentedFrame.size, dismissedValue: containerDismissedFrame.size)
        animator.set(view: foregroundContainerView, keyPath: \.center, presentedValue: containerPresentedFrame.center, dismissedValue: containerDismissedFrame.center)
        animator.set(view: foregroundView, keyPath: \.translation, presentedValue: .zero, dismissedValue: offset)
        animator.set(view: foregroundView, keyPath: \.scale, presentedValue: 1, dismissedValue: scale)
        if let sourceViewSnapshot {
            animator.set(view: sourceViewSnapshot, keyPath: \.bounds.size, presentedValue: presentedFrame.size, dismissedValue: dismissedFrame.size)
            animator.set(view: sourceViewSnapshot, keyPath: \.center, presentedValue: presentedFrame.center, dismissedValue: dismissedFrame.bounds.center)
            animator.set(view: sourceViewSnapshot, keyPath: \.alpha, presentedValue: 0, dismissedValue: 1)
        }
    }

    func didCompleteTransitionAnimation(position: TransitionEndPosition) {
        guard let context else { return }
        let duration = CACurrentMediaTime() - startTime
        let didPresent = position == .presented

        if didPresent {
            context.container.addSubview(context.foregroundView)
        } else {
            context.container.addSubview(context.backgroundView)
        }
        scrollViewObserver = nil
        matchedSourceView?.isHidden = false
        overlayView.removeFromSuperview()
        foregroundContainerView.lockSafeAreaInsets = false
        foregroundContainerView.removeFromSuperview()

        verticalDismissGestureRecognizer.isEnabled = true
        horizontalDismissGestureRecognizer.isEnabled = true
        context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.container.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)

        self.animator = nil
        self.context = nil
        self.isInteractive = false
        self.sourceViewSnapshot = nil

        print("Complete transition didPresent:\(didPresent) duration:\(duration)")
        context.completeTransition(didPresent == context.isPresenting)
    }

    func targetDidChange() {
        guard let animator, let targetPosition = animator.targetPosition, targetPosition == .dismissed else { return }
        let oldContainerCenter = animator.dismissedValue(view: foregroundContainerView, keyPath: \.center)
        calculateEndStates()
        let newContainerCenter = animator.dismissedValue(view: foregroundContainerView, keyPath: \.center)
        let diff = newContainerCenter - oldContainerCenter
        if diff != .zero {
            let newCenter = foregroundContainerView.center + diff
            animator.setCurrentValue(view: foregroundContainerView, keyPath: \.center, value: newCenter)
        }
    }

    func beginInteractiveTransition() {
        isInteractive = true
        animator?.pause()
    }

    var totalTranslation: CGPoint = .zero
    @objc func handlePan(gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        func progressFrom(offset: CGPoint) -> CGFloat {
            guard let context else { return 0 }
            let container = context.container
            let maxAxis = max(container.bounds.width, container.bounds.height)
            let progress = (offset.x / maxAxis + offset.y / maxAxis) * 1.5
            return -progress
        }
        switch gr.state {
        case .began:
            options.onDragStart?(self)
            beginInteractiveTransition()
            if context == nil {
                if let vc = view.parentNavigationController, vc.viewControllers.count > 1 {
                    vc.popViewController(animated: true)
                }
            }
            totalTranslation = .zero
        case .changed:
            guard let animator else { return }
            let translation = gr.translation(in: nil)
            gr.setTranslation(.zero, in: nil)
            totalTranslation += translation
            let progress = progressFrom(offset: translation)
            if isMatched {
                let newCenter = foregroundContainerView.center + translation * 0.5
                let newRotation = foregroundContainerView.rotation + translation.x * 0.0003
                animator.setCurrentValue(view: foregroundContainerView, keyPath: \.center, value: newCenter)
                animator.setCurrentValue(view: foregroundContainerView, keyPath: \.rotation, value: newRotation)
            } else {
                let newCenter = foregroundContainerView.center + translation
                let newRotation = foregroundContainerView.rotation + translation.x * 0.0003
                animator.setCurrentValue(view: foregroundContainerView, keyPath: \.center, value: newCenter)
                animator.setCurrentValue(view: foregroundContainerView, keyPath: \.rotation, value: newRotation)
            }
            animator.shift(progress: progress)
        default:
            guard let context, let animator else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            if shouldDismiss {
                context.container.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
                context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
                foregroundContainerView.isUserInteractionEnabled = false
                overlayView.isUserInteractionEnabled = false
            }
            if isMatched {
                animator.setVelocity(view: foregroundContainerView, keyPath: \.center, velocity: velocity)
                animator.set(view: foregroundContainerView, keyPath: \.rotation, presentedValue: 0, dismissedValue: 0)
            } else {
                animator.setVelocity(view: foregroundContainerView, keyPath: \.center, velocity: velocity)
                let angle = translationPlusVelocity / context.container.bounds.size
                let targetOffset = angle / angle.distance(.zero) * 1.4 * context.container.bounds.size
                let targetRotation = foregroundContainerView.rotation + translationPlusVelocity.x * 0.0001
                animator.setDismissedValue(view: foregroundContainerView, keyPath: \.center, value: context.container.bounds.center + targetOffset)
                animator.setDismissedValue(view: foregroundContainerView, keyPath: \.rotation, value: targetRotation)
            }
            animator.animateTo(position: shouldDismiss ? .dismissed : .presented)
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
