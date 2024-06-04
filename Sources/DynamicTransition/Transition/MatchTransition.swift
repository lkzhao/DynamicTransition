//
//  MatchTransition.swift
//
//
//  Created by Luke Zhao on 10/6/23.
//

import UIKit
import ScreenCorners
import BaseToolbox

public protocol MatchTransitionDelegate {
    /// Provide the matched view from the current object's own view hierarchy for the match transition
    func matchedViewFor(transition: MatchTransition, otherView: UIView) -> UIView?

    /// The matched view will be inserted below the returned view if provided
    func matchedViewInsertionBelowTargetView(transition: MatchTransition) -> UIView?

    /// Can be used to customize the transition and add extra animation to the animator
    func matchTransitionWillBegin(transition: MatchTransition)
}

public class TransitionPanGestureRecognizer: UIPanGestureRecognizer {}

/// A Transition that matches two items and transitions between them.
///
/// The foreground view will be masked to the item and expand as the transition
///
public class MatchTransition: InteractiveTransition {
    /// Dismiss gesture recognizer, add this to your view to support drag to dismiss
    public lazy var verticalDismissGestureRecognizer = TransitionPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
    }
    public lazy var horizontalDismissGestureRecognizer = TransitionPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
    }
    public lazy var horizontalEdgeDismissGestureRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.edges = .left
        $0.delegate = self
    }
    private lazy var interruptibleVerticalDismissGestureRecognizer = TransitionPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
    }
    private lazy var interruptibleHorizontalDismissGestureRecognizer = TransitionPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
    }
    private lazy var interruptibleTapRepresentGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap)).then {
        $0.delegate = self
    }

    let foregroundContainerView = ShadowContainerView()
    public private(set) var matchedSourceView: UIView?
    public private(set) var matchedDestinationView: UIView?
    public private(set) var sourceViewSnapshot: UIView?
    var scrollViewObservers: [Any] = []
    var overlayView: BlurOverlayView?
    var isMatched: Bool {
        matchedSourceView != nil
    }

    public override func canTransitionSimutanously(with transition: Transition) -> Bool {
        transition is MatchTransition
    }

    public override func setupTransition(context: any TransitionContext, animator: TransitionAnimator) {
        let container = context.container
        let foreground = context.foreground
        let background = context.background
        let foregroundDelegate = foreground as? MatchTransitionDelegate
        let backgroundDelegate = background as? MatchTransitionDelegate

        foregroundContainerView.frame = container.bounds
        foregroundContainerView.backgroundColor = foreground.backgroundColor

        background.frameWithoutTransform = container.bounds
        foreground.frameWithoutTransform = container.bounds
        overlayView = BlurOverlayView()
        overlayView?.frame = container.bounds
        overlayView?.isUserInteractionEnabled = true

        if background.window == nil {
            container.addSubview(background)
        }
        background.addSubview(overlayView!)
        background.addSubview(foregroundContainerView)
        foregroundContainerView.contentView.addSubview(foreground)
        foregroundContainerView.lockSafeAreaInsets = true

        context.to.setNeedsLayout()
        context.to.layoutIfNeeded()

        TransitionContainerTracker.shared.transitionStart(from: context.from, to: context.to)

        let matchedSourceView = backgroundDelegate?.matchedViewFor(transition: self, otherView: foreground)
        let matchedDestinationView = foregroundDelegate?.matchedViewFor(transition: self, otherView: background)

        self.matchedSourceView = matchedSourceView
        self.matchedDestinationView = matchedDestinationView

        if let matchedSourceView, let sourceViewSnapshot = matchedSourceView.snapshotView(afterScreenUpdates: true) {
            sourceViewSnapshot.isUserInteractionEnabled = false
            foreground.addSubview(sourceViewSnapshot)
            self.sourceViewSnapshot = sourceViewSnapshot
            matchedSourceView.isHidden = true
        }

        setupAnimation(context: context, animator: animator)

        if let targetView = backgroundDelegate?.matchedViewInsertionBelowTargetView(transition: self) {
            background.insertSubview(overlayView!, belowSubview: targetView)
            background.insertSubview(foregroundContainerView, belowSubview: targetView)
        }

        backgroundDelegate?.matchTransitionWillBegin(transition: self)
        foregroundDelegate?.matchTransitionWillBegin(transition: self)

        scrollViewObservers = (matchedSourceView?.flattendSuperviews.compactMap({ $0 as? UIScrollView }) ?? []).map {
            $0.observe(\UIScrollView.contentOffset, options: [.new, .old]) { [weak self] table, change in
                guard change.newValue != change.oldValue else { return }
                self?.targetDidChange()
            }
        }
    }

    func setupAnimation(context: any TransitionContext, animator: TransitionAnimator) {
        guard let dismissedFrame = calculateDismissedFrame() else { return }
        let container = context.container
        let backgroundView = context.background
        let foregroundView = context.foreground

        let presentedFrame: CGRect

        if isMatched {
            if let matchedDestinationView {
                presentedFrame = backgroundView.convert(matchedDestinationView.bounds, from: matchedDestinationView)
            } else {
                let fillHeight = dismissedFrame.size.size(fit: CGSize(width: container.bounds.width, height: .infinity)).height
                presentedFrame = CGRect(x: 0, y: 0, width: container.bounds.width, height: fillHeight)
            }
        } else {
            presentedFrame = container.bounds
        }

        let isFullScreen = container.window?.convert(container.bounds, from: container) == container.window?.bounds
        let presentedCornerRadius = isFullScreen ? UIScreen.main.displayCornerRadius : container.parentViewController?.sheetPresentationController?.preferredCornerRadius ?? 0
        let dismissedCornerRadius = matchedSourceView?.cornerRadius ?? presentedCornerRadius
        let containerPresentedFrame = container.bounds

        let scaledSize = presentedFrame.size.size(fill: dismissedFrame.size)
        let dismissedScale = scaledSize.width / presentedFrame.width
        let sizeOffset = CGPoint(-(scaledSize - dismissedFrame.size) / 2)
        let originOffset = -presentedFrame.origin * dismissedScale
        let scaleOffset = -(1 - dismissedScale) / 2 * CGPoint(container.bounds.size)
        let dismissedOffset = scaleOffset + sizeOffset + originOffset

        animator[overlayView!, \.progress].presentedValue = 1
        animator[foregroundContainerView, \UIView.shadowOpacity].dismissedValue = -1
        foregroundContainerView.cornerRadius = presentedCornerRadius
        animator[foregroundContainerView, \UIView.cornerRadius].dismissedValue = dismissedCornerRadius - presentedCornerRadius

        animator[foregroundContainerView, \UIView.bounds.size].dismissedValue = dismissedFrame.size - containerPresentedFrame.size
        animator[foregroundContainerView, \UIView.center].dismissedValue = dismissedFrame.center - containerPresentedFrame.center
        animator[foregroundContainerView, \UIView.rotation].dismissedValue = matchedSourceView?.rotation ?? 0
        animator[foregroundContainerView, \UIView.scale].dismissedValue = (matchedSourceView?.scale ?? 1) - 1
        animator[foregroundView, \UIView.translation].dismissedValue = dismissedOffset
        animator[foregroundView, \UIView.scale].dismissedValue = dismissedScale - 1

        if let sourceViewSnapshot {
            sourceViewSnapshot.frameWithoutTransform = CGRect(center: presentedFrame.center, size: dismissedFrame.size)
            sourceViewSnapshot.scale = 1 / dismissedScale
            animator[sourceViewSnapshot, \UIView.alpha].presentedValue = -1
        }
    }

    public override func animationWillStart(targetPosition: TransitionEndPosition) {
        guard let context else { return }
        let isPresenting = targetPosition == .presented
        if isPresenting {
            context.container.addGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
            context.container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
            interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        } else {
            interruptibleVerticalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
            interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
            context.container.addGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        }
        foregroundContainerView.isUserInteractionEnabled = isPresenting
        overlayView?.isUserInteractionEnabled = isPresenting
    }

    public override func cleanupTransition(endPosition: TransitionEndPosition) {
        guard let context else { return }
        let didPresent = endPosition == .presented
        let didComplete = didPresent == context.isPresenting

        if didPresent {
            // move foregroundView view out of the foregroundContainerView
            let foregroundView = context.foreground
            foregroundContainerView.superview?.insertSubview(foregroundView, aboveSubview: foregroundContainerView)
        }
        TransitionContainerTracker.shared.transitionEnd(from: context.from, to: context.to, completed: didComplete)

        scrollViewObservers.removeAll()
        matchedSourceView?.isHidden = false
        overlayView?.removeFromSuperview()
        foregroundContainerView.lockSafeAreaInsets = false
        foregroundContainerView.removeFromSuperview()
        self.sourceViewSnapshot?.removeFromSuperview()

        interruptibleVerticalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)

        self.sourceViewSnapshot = nil
        self.overlayView = nil
    }

    func targetDidChange() {
        guard let animator, let context, let targetPosition = animator.targetPosition, targetPosition == .dismissed, matchedSourceView?.window != nil, let newDismissedFrame = calculateDismissedFrame() else { return }
        let oldContainerCenter = animator[foregroundContainerView, \UIView.center].dismissedValue
        let newContainerCenter = newDismissedFrame.center - context.container.bounds.center
        animator[foregroundContainerView, \UIView.center].dismissedValue = newContainerCenter
        let diff = newContainerCenter - oldContainerCenter
        if diff != .zero {
            animator[foregroundContainerView, \UIView.center].value += diff
        }
    }

    func calculateDismissedFrame() -> CGRect? {
        guard let context else { return nil }
        let container = context.container
        if let matchedSourceView, let superview = matchedSourceView.superview {
            let frame = matchedSourceView.frameWithoutTransform
            return context.background.convert(frame, from: superview)
        }
        return container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
    }

    var totalTranslation: CGPoint = .zero
    @objc func handlePan(gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        func progressFrom(offset: CGPoint) -> CGFloat {
            guard let context else { return 0 }
            let container = context.container
            let maxAxis = max(container.bounds.width, container.bounds.height)
            let progress = (offset.x / maxAxis + offset.y / maxAxis) * 1.2
            return -progress
        }
        switch gr.state {
        case .began:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            beginInteractiveTransition()
            if context == nil, let vc = view.navigationController, vc.views.count > 1 {
                vc.popView(animated: true)
            }
            totalTranslation = .zero
        case .changed:
            guard let animator else { return }
            let translation = gr.translation(in: nil)
            gr.setTranslation(.zero, in: nil)
            totalTranslation += translation
            let progress = progressFrom(offset: translation)
            animator[foregroundContainerView, \UIView.center].isIndependent = true
            animator[foregroundContainerView, \UIView.rotation].isIndependent = true
            animator[foregroundContainerView, \UIView.center].value += translation * (isMatched ? 0.5 : 1.0)
            animator[foregroundContainerView, \UIView.rotation].value += translation.x * 0.0003
            animator.shift(progress: progress)
        default:
            guard let context, let animator else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            animator[foregroundContainerView, \UIView.center].velocity = velocity
            if isMatched {
                animator[foregroundContainerView, \UIView.rotation].dismissedValue = matchedSourceView?.rotation ?? 0
                animator[foregroundContainerView, \UIView.scale].dismissedValue = (matchedSourceView?.scale ?? 1) - 1
            } else {
                let angle = translationPlusVelocity / context.container.bounds.size
                let offset = angle / angle.distance(.zero) * 1.4 * context.container.bounds.size
                let targetOffset = context.container.bounds.center + offset
                let targetRotation = foregroundContainerView.rotation + translationPlusVelocity.x * 0.0001
                animator[foregroundContainerView, \UIView.center].dismissedValue = targetOffset - context.container.bounds.center
                animator[foregroundContainerView, \UIView.rotation].dismissedValue = targetRotation
            }
            animateTo(position: shouldDismiss ? .dismissed : .presented)
        }
    }

    @objc func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reverse()
    }
}

extension MatchTransition: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == interruptibleTapRepresentGestureRecognizer {
            return foregroundContainerView.point(inside: gestureRecognizer.location(in: foregroundContainerView), with: nil)
        }
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
            if velocity.y > abs(velocity.x) {
                return true
            }
        } else if gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer || gestureRecognizer == horizontalEdgeDismissGestureRecognizer {
            if velocity.x > abs(velocity.y) {
                return true
            }
        }
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer, let scrollView = otherGestureRecognizer.view as? UIScrollView, otherGestureRecognizer == scrollView.panGestureRecognizer {
            if scrollView.contentSize.height > scrollView.bounds.height, gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
                return scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1.0
            }
            if scrollView.contentSize.width > scrollView.bounds.width, gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
                return scrollView.contentOffset.x <= -scrollView.adjustedContentInset.left + 1.0
            }
            return true
        }
        return false
    }
}
