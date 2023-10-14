//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/12/23.
//

import UIKit
import BaseToolbox
import Motion

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

        var animator = TransitionAnimator { position in
            self.didCompleteTransitionAnimation(position: position)
        }
        animator.add(view: foregroundView, keyPath: \.translationX, presentedValue: 0, dismissedValue: container.bounds.width)
        animator.add(view: overlayView, keyPath: \.alpha, presentedValue: 1, dismissedValue: 0)
        animator.seekTo(position: context.isPresenting ? .dismissed : .presented)

        self.context = context
        self.overlayView = overlayView
        self.animator = animator
        if !isInteractive {
            animator.animateTo(position: context.isPresenting ? .presented : .dismissed)
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
            isInteractive = true
            if context == nil {
                view.dismiss()
            } else {
                animator?.pause()
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
                context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
                context.foregroundView.isUserInteractionEnabled = false
                overlayView?.isUserInteractionEnabled = false
            }
            context.foregroundView.yaal.translationX.velocity.value = velocity.x
            animator.animateTo(position: shouldDismiss ? .dismissed : .presented)
        }
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

extension UIView {
    var translationX: CGFloat {
        get {
            value(forKeyPath: "layer.transform.translation.x") as? CGFloat ?? 0
        }
        set {
            setValue(newValue, forKeyPath: "layer.transform.translation.x")
        }
    }
}
