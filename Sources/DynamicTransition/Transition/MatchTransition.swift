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

    public private(set) var overlayView: BlurOverlayView?
    public private(set) var foregroundContainerView: ShadowContainerView?
    public private(set) var matchedSourceView: UIView?
    public private(set) var matchedDestinationView: UIView?
    public private(set) var sourceViewSnapshot: UIView?
    var scrollViewObservers: [Any] = []
    var isMatched: Bool {
        matchedSourceView != nil
    }

    public override func canTransitionSimutanously(with transition: Transition) -> Bool {
        transition is PushTransition || transition is MatchTransition
    }

    public override func setupTransition(context: any TransitionContext, animator: TransitionAnimator) {
        let container = context.container
        let foreground = context.foreground
        let background = context.background
        let foregroundDelegate = foreground as? MatchTransitionDelegate
        let backgroundDelegate = background as? MatchTransitionDelegate

        let overlayView = BlurOverlayView()
        let foregroundContainerView = ShadowContainerView()
        self.overlayView = overlayView
        self.foregroundContainerView = foregroundContainerView

        foregroundContainerView.frame = container.bounds
        foregroundContainerView.backgroundColor = foreground.backgroundColor

        background.frameWithoutTransform = container.bounds
        foreground.frameWithoutTransform = container.bounds
        overlayView.frame = container.bounds
        overlayView.isUserInteractionEnabled = true

        if background.window == nil {
            container.addSubview(background)
        }
        background.addSubview(overlayView)
        background.addSubview(foregroundContainerView)
        foregroundContainerView.contentView.addSubview(foreground)
        foreground.lockedSafeAreaInsets = container.safeAreaInsets

        context.to.setNeedsLayout()
        context.to.layoutIfNeeded()

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

        backgroundDelegate?.matchTransitionWillBegin(transition: self)
        foregroundDelegate?.matchTransitionWillBegin(transition: self)

        let scrollViews: [UIScrollView] = ((matchedSourceView?.flattendSuperviews ?? []) + (matchedDestinationView?.flattendSuperviews ?? [])).compactMap({ $0 as? UIScrollView })
        scrollViewObservers = scrollViews.map {
            $0.observe(\UIScrollView.contentOffset, options: [.new, .old]) { [weak self] table, change in
                guard change.newValue != change.oldValue else { return }
                self?.targetDidChange()
            }
        }
    }

    func setupAnimation(context: any TransitionContext, animator: TransitionAnimator) {
        guard let (dismissedFrame, presentedFrame) = calculateTargetFrames(), let overlayView, let foregroundContainerView else { return }
        let container = context.container
        let foregroundView = context.foreground

        let isFullScreen = container.window?.convert(container.bounds, from: container) == container.window?.bounds
        let presentedCornerRadius = isFullScreen ? UIScreen.main.displayCornerRadius : container.parentViewController?.sheetPresentationController?.preferredCornerRadius ?? 0
        let dismissedCornerRadius = matchedSourceView?.cornerRadius ?? presentedCornerRadius

        let scaledSize = presentedFrame.size.size(fill: dismissedFrame.size)
        let dismissedScale = scaledSize.width / presentedFrame.width
        let sizeOffset = CGPoint(-(scaledSize - dismissedFrame.size) / 2)
        let originOffset = -presentedFrame.origin * dismissedScale
        let scaleOffset = -(1 - dismissedScale) / 2 * CGPoint(container.bounds.size)
        let dismissedOffset = scaleOffset + sizeOffset + originOffset

        animator[overlayView, \.progress].presentedValue = 1
        animator[foregroundContainerView, \UIView.shadowOpacity].dismissedValue = 0
        animator[foregroundContainerView, \UIView.cornerRadius].presentedValue = presentedCornerRadius
        animator[foregroundContainerView, \UIView.cornerRadius].dismissedValue = dismissedCornerRadius

        animator[foregroundContainerView, \UIView.bounds.size].dismissedValue = dismissedFrame.size
        animator[foregroundContainerView, \UIView.center].dismissedValue = dismissedFrame.center
        animator[foregroundContainerView, \UIView.rotation].dismissedValue = matchedSourceView?.rotation ?? 0
        animator[foregroundContainerView, \UIView.scale].dismissedValue = matchedSourceView?.scale ?? 1
        animator[foregroundView, \UIView.translation].dismissedValue = dismissedOffset
        animator[foregroundView, \UIView.scale].dismissedValue = dismissedScale

        if let sourceViewSnapshot {
            sourceViewSnapshot.frameWithoutTransform = CGRect(center: presentedFrame.center, size: dismissedFrame.size)
            sourceViewSnapshot.scale = 1 / dismissedScale
            animator[sourceViewSnapshot, \UIView.alpha].presentedValue = 0
        }
    }

    public override func animationWillStart(targetPosition: TransitionEndPosition) {
        guard let context else { return }
        let isPresenting = targetPosition == .presented
        if isPresenting {
            if let overlayView, let foregroundContainerView {
                context.background.bringSubviewToFront(overlayView)
                context.background.bringSubviewToFront(foregroundContainerView)
            }
            context.container.addGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
            context.container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
            interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        } else {
            interruptibleVerticalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
            interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
            context.container.addGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        }
        foregroundContainerView?.isUserInteractionEnabled = isPresenting
        overlayView?.isUserInteractionEnabled = isPresenting
    }

    public override func cleanupTransition(endPosition: TransitionEndPosition) {
        guard let context else { return }
        let didPresent = endPosition == .presented

        if didPresent, let foregroundContainerView {
            // move foregroundView view out of the foregroundContainerView
            let foregroundView = context.foreground
            foregroundContainerView.superview?.insertSubview(foregroundView, aboveSubview: foregroundContainerView)
        }

        scrollViewObservers.removeAll()
        matchedSourceView?.isHidden = false
        overlayView?.removeFromSuperview()
        context.foreground.lockedSafeAreaInsets = nil
        foregroundContainerView?.removeFromSuperview()
        self.sourceViewSnapshot?.removeFromSuperview()

        interruptibleVerticalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)

        self.sourceViewSnapshot = nil
        self.overlayView = nil
        self.foregroundContainerView = nil
    }

    func targetDidChange() {
        guard let animator, let (newDismissedFrame, newPresentedFrame) = calculateTargetFrames() else { return }
        if animator.targetPosition == .dismissed, let foregroundContainerView, matchedSourceView?.window != nil {
            animator[foregroundContainerView, \UIView.center].setNewTargetValueAndApplyOffset(position: .dismissed, newValue: newDismissedFrame.center)
        }
        if animator.targetPosition == .presented, let sourceViewSnapshot, matchedDestinationView?.window != nil {
            animator[sourceViewSnapshot, \UIView.center].setNewTargetValueAndApplyOffset(position: .presented, newValue: newPresentedFrame.center)
        }
    }

    func calculateTargetFrames() -> (CGRect, CGRect)? {
        guard let context else { return nil }
        let container = context.container
        let dismissFrame: CGRect
        let presentFrame: CGRect

        if let matchedSourceView, let superview = matchedSourceView.superview {
            let frame = matchedSourceView.frameWithoutTransform
            dismissFrame = context.background.convert(frame, from: superview)
        } else {
            dismissFrame = container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
        }
        if isMatched {
            if let matchedDestinationView {
                presentFrame = context.foreground.convert(matchedDestinationView.bounds, from: matchedDestinationView)
            } else {
                let fillHeight = dismissFrame.size.size(fit: CGSize(width: container.bounds.width, height: .infinity)).height
                presentFrame = CGRect(x: 0, y: 0, width: container.bounds.width, height: fillHeight)
            }
        } else {
            presentFrame = container.bounds
        }
        return (dismissFrame, presentFrame)
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
            if context == nil, let navigationController = view.navigationController, navigationController.views.count > 1 {
                navigationController.popView(animated: true)
            }
            totalTranslation = .zero
        case .changed:
            guard let animator, let foregroundContainerView else { return }
            let translation = gr.translation(in: nil)
            gr.setTranslation(.zero, in: nil)
            totalTranslation += translation
            let progress = progressFrom(offset: translation)
            animator[foregroundContainerView, \UIView.center].isIndependent = true
            animator[foregroundContainerView, \UIView.rotation].isIndependent = true
            animator[foregroundContainerView, \UIView.center].currentValue += translation * (isMatched ? 0.5 : 1.0)
            animator[foregroundContainerView, \UIView.rotation].currentValue += translation.x * 0.0003
            animator.shift(progress: progress)
        default:
            guard let context, let animator, let foregroundContainerView else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            animator[foregroundContainerView, \UIView.center].velocity = velocity
            if isMatched {
                animator[foregroundContainerView, \UIView.rotation].dismissedValue = matchedSourceView?.rotation ?? 0
                animator[foregroundContainerView, \UIView.scale].dismissedValue = matchedSourceView?.scale ?? 1
            } else {
                let angle = translationPlusVelocity / context.container.bounds.size
                let offset = angle / angle.distance(.zero) * 1.4 * context.container.bounds.size
                let targetOffset = context.container.bounds.center + offset
                let targetRotation = foregroundContainerView.rotation + translationPlusVelocity.x * 0.0001
                animator[foregroundContainerView, \UIView.center].dismissedValue = targetOffset
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
        if gestureRecognizer == interruptibleTapRepresentGestureRecognizer, let foregroundContainerView {
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
            if scrollView.contentSize.height > scrollView.bounds.inset(by: scrollView.adjustedContentInset).height, gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
                return scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1.0
            }
            if scrollView.contentSize.width > scrollView.bounds.inset(by: scrollView.adjustedContentInset).width, gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
                return scrollView.contentOffset.x <= -scrollView.adjustedContentInset.left + 1.0
            }
            return true
        }
        return false
    }
}
