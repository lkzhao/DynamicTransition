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

    var context: TransitionContext?
    var animator: TransitionAnimator?
    var overlayView: UIView?
    var isInteractive: Bool = false

    public var wantsInteractiveStart: Bool {
        isInteractive
    }

    public func animateTransition(context: TransitionContext) {
        let container = context.container
        let foregroundView = context.foregroundView
        let backgroundView = context.backgroundView
        let overlayView = UIView()
        overlayView.backgroundColor = .black.withAlphaComponent(0.4)
        overlayView.isUserInteractionEnabled = true
        overlayView.frame = container.bounds

        foregroundView.frame = container.bounds

        container.addSubview(backgroundView)
        container.addSubview(overlayView)
        container.addSubview(foregroundView)
        container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)

        foregroundView.setNeedsLayout()
        foregroundView.layoutIfNeeded()
        foregroundView.lockSafeAreaInsets = true

        let animator = TransitionAnimator { position in
            self.didCompleteTransitionAnimation(position: position)
        }
        animator[foregroundView, \.translationX].presentedValue = 0
        animator[foregroundView, \.translationX].dismissedValue = container.bounds.width
        animator[overlayView, \.alpha].presentedValue = 1
        animator[overlayView, \.alpha].dismissedValue = 0
        animator.seekTo(position: context.isPresenting ? .dismissed : .presented)

        self.context = context
        self.overlayView = overlayView
        self.animator = animator
        if !isInteractive {
            animator.animateTo(position: context.isPresenting ? .presented : .dismissed)
            if !context.isPresenting {
                onDismissStarts()
            }
        }
    }

    func didCompleteTransitionAnimation(position: TransitionEndPosition) {
        guard let context else { return }
        let didPresent = position == .presented
        self.animator = nil
        self.context = nil
        self.isInteractive = false
        self.overlayView?.removeFromSuperview()
        context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.foregroundView.lockSafeAreaInsets = false
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
            if shouldDismiss {
                onDismissStarts()
            }
            animator[context.foregroundView, \.translationX].velocity = velocity.x
            animator.animateTo(position: shouldDismiss ? .dismissed : .presented)
            context.endInteractiveTransition(shouldDismiss != context.isPresenting)
        }
    }

    func onDismissStarts() {
        guard let context else { return }
        context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.foregroundView.isUserInteractionEnabled = false
        overlayView?.isUserInteractionEnabled = false
    }
}


extension PushTransition: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
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
