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
        let backgroundView = ContainerManager.shared.containerViewFor(viewController: background)
        let foregroundView = ContainerManager.shared.containerViewFor(viewController: foreground)

        foregroundContainerView.frame = container.bounds
        foregroundContainerView.backgroundColor = foreground.view.backgroundColor

        backgroundView.frameWithoutTransform = container.bounds
        foregroundView.frameWithoutTransform = container.bounds
        overlayView.frame = container.bounds
        overlayView.isUserInteractionEnabled = true

        container.addSubview(backgroundView)
        backgroundView.addSubview(overlayView)
        backgroundView.addSubview(foregroundContainerView)
        foregroundContainerView.contentView.addSubview(foregroundView)
        foregroundContainerView.lockSafeAreaInsets = true

        ContainerManager.shared.startTransition(viewController: background)
        ContainerManager.shared.startTransition(viewController: foreground)

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
            if !context.isPresenting {
                onDismissStarts()
            }
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
        let dismissedScale = scaledSize.width / container.bounds.width
        let sizeOffset = -(scaledSize - dismissedFrame.size) / 2
        let originOffset = -presentedFrame.minY * dismissedScale
        let dismissedOffsetX = -(1 - dismissedScale) / 2 * container.bounds.width
        let dismissedOffsetY = -(1 - dismissedScale) / 2 * container.bounds.height
        let dismissedOffset = CGPoint(
            x: dismissedOffsetX + sizeOffset.width,
            y: dismissedOffsetY + sizeOffset.height + originOffset)

        let foregroundView = context.foregroundView

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
            animator[sourceViewSnapshot, \.bounds.size].dismissedValue = dismissedFrame.size
            animator[sourceViewSnapshot, \.center].presentedValue = presentedFrame.center
            animator[sourceViewSnapshot, \.center].dismissedValue = dismissedFrame.bounds.center
            animator[sourceViewSnapshot, \.alpha].presentedValue = 0
            animator[sourceViewSnapshot, \.alpha].dismissedValue = 1
        }
    }

    func didCompleteTransitionAnimation(position: TransitionEndPosition) {
        guard let context else { return }
        let duration = CACurrentMediaTime() - startTime
        let didPresent = position == .presented

        ContainerManager.shared.endTransition(viewController: context.background, didShow: !didPresent)
        ContainerManager.shared.endTransition(viewController: context.foreground, didShow: didPresent)
        if didPresent {
            context.container.addSubview(ContainerManager.shared.containerViewFor(viewController: context.foreground))
            if !ContainerManager.shared.isContainerInUsed(viewController: context.background) {
                ContainerManager.shared.containerViewFor(viewController: context.background).removeFromSuperview()
                ContainerManager.shared.cleanupContainer(viewController: context.background)
            }
        } else {
            if !ContainerManager.shared.isContainerInUsed(viewController: context.foreground) {
                ContainerManager.shared.containerViewFor(viewController: context.foreground).removeFromSuperview()
                ContainerManager.shared.cleanupContainer(viewController: context.foreground)
            }
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
        let oldContainerCenter = animator[foregroundContainerView, \.center].dismissedValue
        calculateEndStates()
        let newContainerCenter = animator[foregroundContainerView, \.center].dismissedValue
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
            if shouldDismiss {
                onDismissStarts()
            }
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
            animator.animateTo(position: shouldDismiss ? .dismissed : .presented)
            context.endInteractiveTransition(shouldDismiss != context.isPresenting)
        }
    }

    func onDismissStarts() {
        guard let context else { return }
        context.container.removeGestureRecognizer(interruptibleVerticalDismissGestureRecognizer)
        context.container.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        foregroundContainerView.isUserInteractionEnabled = false
        overlayView.isUserInteractionEnabled = false
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

    var containers: [UIViewController: ContainerContext] = [:]

    func containerViewFor(viewController: UIViewController) -> UIView {
        self[viewController].container
    }

    func startTransition(viewController: UIViewController) {
        self[viewController].transitionCount += 1
        if viewController.view.superview != self[viewController].container {
            self[viewController].container.insertSubview(viewController.view, at: 0)
            self[viewController].container.setNeedsLayout()
            self[viewController].container.layoutIfNeeded()
        }
    }

    func endTransition(viewController: UIViewController, didShow: Bool) {
        self[viewController].transitionCount -= 1
        self[viewController].presentedCount += didShow ? 1 : -1
    }

    func isContainerInUsed(viewController: UIViewController) -> Bool {
        self[viewController].transitionCount > 0 || self[viewController].presentedCount > 0
    }

    func cleanupContainer(viewController: UIViewController) {
        containers[viewController] = nil
    }

    subscript(viewController: UIViewController) -> ContainerContext {
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
