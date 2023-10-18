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
    private lazy var interruptibleTapRepresentGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap)).then {
        $0.delegate = self
    }

    private var context: TransitionContext?
    private var animator: TransitionAnimator?
    private var isInteractive: Bool = false
    
    let foregroundContainerView = ShadowContainerView()
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

    public var wantsInteractiveStart: Bool {
        isInteractive
    }

    public func canTransitionSimutanously(with transition: Transition) -> Bool {
        transition is MatchTransition
    }

    public func animateTransition(context: TransitionContext) {
        guard self.context == nil else {
            return
        }
        self.context = context

        CATransaction.begin()
        let container = context.container
        let foreground = context.foreground
        let background = context.background
        let backgroundView = ContainerManager.shared.containerViewFor(viewController: background)
        let foregroundView = ContainerManager.shared.containerViewFor(viewController: foreground)

        foregroundContainerView.frame = container.bounds
        foregroundContainerView.backgroundColor = foreground.view.backgroundColor

        backgroundView.frameWithoutTransform = container.bounds
        foregroundView.frameWithoutTransform = container.bounds
        overlayView.frame = container.bounds
        overlayView.isUserInteractionEnabled = true

        if backgroundView.window == nil {
            container.addSubview(backgroundView)
        }
        backgroundView.addSubview(overlayView)
        backgroundView.addSubview(foregroundContainerView)
        foregroundContainerView.contentView.addSubview(foregroundView)
        foregroundContainerView.lockSafeAreaInsets = true

        ContainerManager.shared.startTransition(viewController: background, isSource: context.isPresenting)
        ContainerManager.shared.startTransition(viewController: foreground, isSource: !context.isPresenting)

        let matchedDestinationView = context.foreground.findObjectMatchType(MatchTransitionDelegate.self)?
            .matchedViewFor(transition: context, otherViewController: context.background)
        let matchedSourceView = context.background.findObjectMatchType(MatchTransitionDelegate.self)?
            .matchedViewFor(transition: context, otherViewController: context.foreground)

        self.matchedSourceView = matchedSourceView
        self.matchedDestinationView = matchedDestinationView

        if let matchedSourceView, let sourceViewSnapshot = matchedSourceView.snapshotView(afterScreenUpdates: true) {
            sourceViewSnapshot.isUserInteractionEnabled = false
            foregroundView.addSubview(sourceViewSnapshot)
            self.sourceViewSnapshot = sourceViewSnapshot
            matchedSourceView.isHidden = true
            if let parentScrollView = matchedSourceView.superview as? UIScrollView {
                scrollViewObserver = parentScrollView.observe(\UIScrollView.contentOffset, options: .new) { table, change in
                    self.targetDidChange()
                }
            }
        }

        let animator = TransitionAnimator { position in
            self.didCompleteTransitionAnimation(position: position)
        }
        self.animator = animator

        calculateEndStates()

        animator.seekTo(position: context.isPresenting ? .dismissed : .presented)
        CATransaction.commit()

        if !isInteractive {
            animateTo(position: context.isPresenting ? .presented : .dismissed)
        }
    }

    public func reverse() {
        guard let context, let targetPosition = animator?.targetPosition else { return }
        let isPresenting = targetPosition.reversed == .presented
        beginInteractiveTransition()
        animateTo(position: targetPosition.reversed)
        context.endInteractiveTransition(context.isPresenting == isPresenting)
    }

    func calculateDismissedFrame() -> CGRect? {
        guard let context else { return nil }
        let container = context.container
        let backgroundView = ContainerManager.shared.containerViewFor(viewController: context.background)
        let dismissedFrame = matchedSourceView.map {
            backgroundView.convert($0.bounds, from: $0)
        } ?? container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
        return dismissedFrame
    }

    func calculateEndStates() {
        guard let context, let animator, let dismissedFrame = calculateDismissedFrame() else { return }
        let container = context.container
        let backgroundView = ContainerManager.shared.containerViewFor(viewController: context.background)
        let foregroundView = ContainerManager.shared.containerViewFor(viewController: context.foreground)

        let presentedFrame = isMatched ? matchedDestinationView.map {
            backgroundView.convert($0.bounds, from: $0)
        } ?? container.bounds : container.bounds

        let isFullScreen = container.window?.convert(container.bounds, from: container) == container.window?.bounds
        let presentedCornerRadius = isFullScreen ? UIScreen.main.displayCornerRadius : 0
        let dismissedCornerRadius = matchedSourceView?.cornerRadius ?? presentedCornerRadius
        let containerPresentedFrame = container.bounds
        let containerDismissedFrame = dismissedFrame

        let scaledSize = presentedFrame.size.size(fill: dismissedFrame.size)
        let dismissedScale = scaledSize.width / container.bounds.width
        let sizeOffset = -(scaledSize - dismissedFrame.size) / 2
        let originOffset = -presentedFrame.minY * dismissedScale
        let dismissedOffsetX = -(1 - dismissedScale) / 2 * container.bounds.width
        let dismissedOffsetY = -(1 - dismissedScale) / 2 * container.bounds.height
        let dismissedOffset = CGPoint(
            x: dismissedOffsetX + sizeOffset.width,
            y: dismissedOffsetY + sizeOffset.height + originOffset)

        animator[overlayView, \.alpha].presentedValue = 1
        animator[overlayView, \.alpha].dismissedValue = 0
        animator[foregroundContainerView, \.shadowOpacity].presentedValue = 1
        animator[foregroundContainerView, \.shadowOpacity].dismissedValue = 0
        animator[foregroundContainerView, \.cornerRadius].presentedValue =  presentedCornerRadius
        animator[foregroundContainerView, \.cornerRadius].dismissedValue = dismissedCornerRadius
        animator[foregroundContainerView, \.bounds.size].presentedValue =  containerPresentedFrame.size
        animator[foregroundContainerView, \.bounds.size].dismissedValue = containerDismissedFrame.size
        animator[foregroundContainerView, \.center].presentedValue =  containerPresentedFrame.center
        animator[foregroundContainerView, \.center].dismissedValue = containerDismissedFrame.center
        animator[foregroundView, \.translation].presentedValue =  .zero
        animator[foregroundView, \.translation].dismissedValue = dismissedOffset
        animator[foregroundView, \.scale].presentedValue = 1
        animator[foregroundView, \.scale].dismissedValue = dismissedScale

        if let sourceViewSnapshot {
            animator[sourceViewSnapshot, \.bounds.size].presentedValue = presentedFrame.size
            animator[sourceViewSnapshot, \.bounds.size].dismissedValue = presentedFrame.size
            animator[sourceViewSnapshot, \.center].presentedValue = presentedFrame.center
            animator[sourceViewSnapshot, \.center].dismissedValue = presentedFrame.center
            animator[sourceViewSnapshot, \.alpha].presentedValue = 0
            animator[sourceViewSnapshot, \.alpha].dismissedValue = 1
        }
    }

    func didCompleteTransitionAnimation(position: TransitionEndPosition) {
        guard let context else { return }
        let didPresent = position == .presented
        let didComplete = didPresent == context.isPresenting

        ContainerManager.shared.endTransition(viewController: context.background, didShow: !didPresent, didComplete: didComplete)
        ContainerManager.shared.endTransition(viewController: context.foreground, didShow: didPresent, didComplete: didComplete)
        if didPresent {
            // move foregroundView view out of the foregroundContainerView
            let foregroundView = ContainerManager.shared.containerViewFor(viewController: context.foreground)
            foregroundContainerView.superview?.insertSubview(foregroundView, aboveSubview: foregroundContainerView)
        }
        ContainerManager.shared.cleanupContainers()
        scrollViewObserver = nil
        matchedSourceView?.isHidden = false
        overlayView.removeFromSuperview()
        foregroundContainerView.lockSafeAreaInsets = false
        foregroundContainerView.removeFromSuperview()
        self.sourceViewSnapshot?.removeFromSuperview()

        interruptibleVerticalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)

        self.animator = nil
        self.context = nil
        self.isInteractive = false
        self.sourceViewSnapshot = nil

        context.completeTransition(didComplete)
    }

    func targetDidChange() {
        guard let animator, let targetPosition = animator.targetPosition, targetPosition == .dismissed, let newDismissedFrame = calculateDismissedFrame() else { return }
        let oldContainerCenter = animator[foregroundContainerView, \.center].dismissedValue
        let newContainerCenter = newDismissedFrame.center
        animator[foregroundContainerView, \.center].dismissedValue = newContainerCenter
        let diff = newContainerCenter - oldContainerCenter
        if diff != .zero {
            let newCenter = foregroundContainerView.center + diff
            animator[foregroundContainerView, \.center].value = newCenter
        }
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
            animator[foregroundContainerView, \.center].isIndependent = true
            animator[foregroundContainerView, \.rotation].isIndependent = true
            animator[foregroundContainerView, \.center].value += translation * (isMatched ? 0.5 : 1.0)
            animator[foregroundContainerView, \.rotation].value += translation.x * 0.0003
            animator.shift(progress: progress)
        default:
            guard let context, let animator else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            animator[foregroundContainerView, \.center].velocity = velocity
            if isMatched {
                animator[foregroundContainerView, \.rotation].presentedValue = 0
                animator[foregroundContainerView, \.rotation].dismissedValue = 0
            } else {
                let angle = translationPlusVelocity / context.container.bounds.size
                let offset = angle / angle.distance(.zero) * 1.4 * context.container.bounds.size
                let targetOffset = context.container.bounds.center + offset
                let targetRotation = foregroundContainerView.rotation + translationPlusVelocity.x * 0.0001
                animator[foregroundContainerView, \.center].dismissedValue = targetOffset
                animator[foregroundContainerView, \.rotation].dismissedValue = targetRotation
            }
            animateTo(position: shouldDismiss ? .dismissed : .presented)
            context.endInteractiveTransition(shouldDismiss != context.isPresenting)
        }
    }

    @objc func handleTap() {
        options.onDragStart?(self)
        reverse()
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
        interruptibleVerticalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        context.container.addGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        foregroundContainerView.isUserInteractionEnabled = false
        overlayView.isUserInteractionEnabled = false
    }

    func onPresentStarts() {
        guard let context else { return }
        context.container.addGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        context.container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        foregroundContainerView.isUserInteractionEnabled = true
        overlayView.isUserInteractionEnabled = true
    }
}

extension MatchTransition: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == interruptibleTapRepresentGestureRecognizer {
            return foregroundContainerView.point(inside: gestureRecognizer.location(in: foregroundContainerView), with: nil)
        }
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
            if velocity.y > abs(velocity.x) {
                return true
            }
        } else if gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
            if velocity.x > abs(velocity.y) {
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

class MatchTransitionContainerView: UIView {
    var childController: UIViewController

    init(viewController: UIViewController) {
        childController = viewController
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        childController.view.frameWithoutTransform = bounds
    }
}

class ContainerManager {
    static let shared = ContainerManager()

    class ContainerContext {
        let container: MatchTransitionContainerView
        var presentedCount: Int = 0
        var transitionCount: Int = 0
        init(viewController: UIViewController) {
            container = MatchTransitionContainerView(viewController: viewController)
        }
    }

    private var containers: [UIViewController: ContainerContext] = [:]

    func containerViewFor(viewController: UIViewController) -> UIView {
        self[viewController].container
    }

    func startTransition(viewController: UIViewController, isSource: Bool) {
        self[viewController].transitionCount += 1
        if isSource, self[viewController].presentedCount == 0 {
            self[viewController].presentedCount = 1 // source should be already presented
        }
        if viewController.view.superview != self[viewController].container {
            self[viewController].container.insertSubview(viewController.view, at: 0)
            self[viewController].container.setNeedsLayout()
            self[viewController].container.layoutIfNeeded()
        }
    }

    func endTransition(viewController: UIViewController, didShow: Bool, didComplete: Bool) {
        self[viewController].transitionCount -= 1
        self[viewController].presentedCount += didComplete ? didShow ? 1 : -1 : 0
    }

    func cleanupContainers() {
        var toBeRemoved: [UIViewController] = []
        var toKeepContainers: Set<UIView> = containers.values.map {
            $0.container
        }.set
        for (vc, context) in containers {
            if context.transitionCount <= 0 && context.presentedCount <= 0 {
                toBeRemoved.append(vc)
                toKeepContainers.remove(context.container)
            }
        }
        for toBeRemove in toBeRemoved {
            guard let context = containers[toBeRemove] else { continue }
            for childToKeep in context.container.subviews.filter({ toKeepContainers.contains($0) }) {
                context.container.superview?.insertSubview(childToKeep, aboveSubview: context.container)
            }
            context.container.removeFromSuperview()
            containers[toBeRemove] = nil
        }
    }

    private subscript(viewController: UIViewController) -> ContainerContext {
        get {
            if containers[viewController] == nil {
                containers[viewController] = ContainerContext(viewController: viewController)
            }
            return containers[viewController]!
        }
        set {
            containers[viewController] = newValue
        }
    }
}
