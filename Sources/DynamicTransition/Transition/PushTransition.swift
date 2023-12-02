//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/12/23.
//

import UIKit
import BaseToolbox

open class PushTransition: NSObject, Transition {
    open lazy var horizontalDismissGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
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

    public var context: TransitionContext?
    public var animator: TransitionAnimator?
    public var overlayView: UIView?
    public var isInteractive: Bool = false
    public var applyVelocity: Bool = true

    open var wantsInteractiveStart: Bool {
        isInteractive
    }

    open func canTransitionSimutanously(with transition: Transition) -> Bool {
        transition is PushTransition
    }

    open func animateTransition(context: TransitionContext) {
        let container = context.container
        let foregroundView = context.foreground
        let backgroundView = context.background
        let overlayView = UIView()
        overlayView.backgroundColor = .black.withAlphaComponent(0.4)
        overlayView.isUserInteractionEnabled = true
        overlayView.frame = container.bounds

        foregroundView.frame = container.bounds

        if foregroundView.superview == container {
            container.insertSubview(backgroundView, belowSubview: foregroundView)
        } else if backgroundView.superview != container {
            container.addSubview(backgroundView)
        }
        container.insertSubview(overlayView, aboveSubview: backgroundView)
        container.insertSubview(foregroundView, aboveSubview: overlayView)
        container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)

        foregroundView.setNeedsLayout()
        foregroundView.layoutIfNeeded()
        foregroundView.lockSafeAreaInsets = true

        let animator = TransitionAnimator()
        animator.addCompletion { position in
            self.didCompleteTransitionAnimation(position: position)
        }
        self.context = context
        self.overlayView = overlayView
        self.animator = animator
        
        animator[foregroundView, \.translationX].dismissedValue = container.bounds.width
        animator[overlayView, \.alpha].dismissedValue = -1

        transitionWillBegin()

        animator.seekTo(position: context.isPresenting ? .dismissed : .presented)

        if !isInteractive {
            animateTo(position: context.isPresenting ? .presented : .dismissed)
        }
    }

    open func transitionWillBegin() {

    }

    public func reverse() {
        guard let context, let targetPosition = animator?.targetPosition else { return }
        let isPresenting = targetPosition.reversed == .presented
        beginInteractiveTransition()
        animateTo(position: targetPosition.reversed)
        context.endInteractiveTransition(context.isPresenting == isPresenting)
    }

    func didCompleteTransitionAnimation(position: TransitionEndPosition) {
        guard let context else { return }
        let didPresent = position == .presented
        self.animator = nil
        self.context = nil
        self.isInteractive = false
        self.overlayView?.removeFromSuperview()
        context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.foreground.lockSafeAreaInsets = false
        if didPresent {
            context.background.removeFromSuperview()
        } else {
            context.foreground.removeFromSuperview()
        }
        context.completeTransition(didPresent == context.isPresenting)
    }

    func beginInteractiveTransition() {
        isInteractive = true
        animator?.pause()
        context?.beginInteractiveTransition()
    }

    var totalTranslation: CGPoint = .zero
    @objc func handlePan(gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        func progressFrom(offset: CGPoint) -> CGFloat {
            guard let context else { return 0 }
            let container = context.container
            let progress = offset.x / container.bounds.width
            return -progress
        }
        switch gr.state {
        case .began:
            beginInteractiveTransition()
            if context == nil {
                view.dismiss()
            }
            totalTranslation = .zero
        case .changed:
            guard let animator else { return }
            let translation = gr.translation(in: nil)
            gr.setTranslation(.zero, in: nil)
            totalTranslation += translation
            let progress = progressFrom(offset: translation)
            animator.shift(progress: progress)
        default:
            guard let context, let animator else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x > 80
            if applyVelocity {
                animator[context.foreground, \.translationX].velocity = velocity.x
            }
            animateTo(position: shouldDismiss ? .dismissed : .presented)
            context.endInteractiveTransition(shouldDismiss != context.isPresenting)
        }
    }

    func animateTo(position: TransitionEndPosition) {
        guard let animator else {
            assertionFailure()
            return
        }
        switch position {
        case .dismissed:
            onDismissStarts()
        case .presented:
            onPresentStarts()
        }
        animator.animateTo(position: position)
    }

    func onDismissStarts() {
        guard let context else { return }
        interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.foreground.isUserInteractionEnabled = false
        overlayView?.isUserInteractionEnabled = false
    }

    func onPresentStarts() {
        guard let context else { return }
        context.container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.foreground.isUserInteractionEnabled = true
        overlayView?.isUserInteractionEnabled = true
    }
}


extension PushTransition: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer.view?.navigationController?.views.count ?? 0 >= 2, gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
            if velocity.x > abs(velocity.y) {
                return true
            }
        }
        return false
    }

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer, let scrollView = otherGestureRecognizer.view as? UIScrollView, otherGestureRecognizer == scrollView.panGestureRecognizer {
            return true
        }
        return false
    }
}
