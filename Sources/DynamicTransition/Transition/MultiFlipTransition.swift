//
//  File.swift
//  DynamicTransition
//
//  Created by Luke Zhao on 9/28/25.
//

import UIKit
import ScreenCorners
import BaseToolbox
import Motion


public struct MultiFlipConfig {
    public var sourceContainerView: UIView?
    public var sourcePrimaryFlipView: UIView
    public init(sourceContainerView: UIView, sourcePrimaryFlipView: UIView) {
        self.sourceContainerView = sourceContainerView
        self.sourcePrimaryFlipView = sourcePrimaryFlipView
    }
}

public protocol MultiFlipTransitionDelegate {
    func multiFlipConfigFor(transition: MultiFlipTransition, otherView: UIView) -> MultiFlipConfig?

    /// Can be used to customize the transition and add extra animation to the animator
    func multiFlipTransitionWillBegin(transition: MultiFlipTransition)
}

/// A Transition that matches two items and transitions between them.
///
/// The foreground view will be masked to the item and expand as the transition
///
public class MultiFlipTransition: InteractiveTransition {
    public lazy var horizontalDismissGestureRecognizer = TransitionPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
    }
    public lazy var horizontalEdgeDismissGestureRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.edges = .left
        $0.delegate = self
    }
    private lazy var interruptibleHorizontalDismissGestureRecognizer = TransitionPanGestureRecognizer(target: self, action: #selector(handlePan(gr:))).then {
        $0.delegate = self
    }
    private lazy var interruptibleTapRepresentGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap)).then {
        $0.delegate = self
    }

    public private(set) var overlayView: BlurOverlayView?
    public private(set) var foregroundContainerView: MultiFlipContainerView?
    public private(set) var flipConfig: MultiFlipConfig?

    var isMatched: Bool {
        flipConfig != nil
    }

    public override func canTransitionSimutanously(with transition: Transition) -> Bool {
        transition is MultiFlipTransition
    }

    public override func setupTransition(context: any TransitionContext, animator: TransitionAnimator) {
        let container = context.container
        let foreground = context.foreground
        let background = context.background
        let backgroundDelegate = background as? MultiFlipTransitionDelegate

        let overlayView = BlurOverlayView()
        let foregroundContainerView = MultiFlipContainerView()
        self.overlayView = overlayView
        self.foregroundContainerView = foregroundContainerView
        self.flipConfig = backgroundDelegate?.multiFlipConfigFor(transition: self, otherView: foreground)

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
        foregroundContainerView.backgroundView = flipConfig?.sourcePrimaryFlipView
        foregroundContainerView.foregroundView = foreground
        foreground.lockedSafeAreaInsets = container.safeAreaInsets
        flipConfig?.sourcePrimaryFlipView.isHidden = true

        context.to.setNeedsLayout()
        context.to.layoutIfNeeded()

        setupAnimation(context: context, animator: animator)

        backgroundDelegate?.multiFlipTransitionWillBegin(transition: self)
    }

    func setupAnimation(context: any TransitionContext, animator: TransitionAnimator) {
        guard let overlayView, let foregroundContainerView else { return }
        let container = context.container

        let isFullScreen = container.window?.convert(container.bounds, from: container) == container.window?.bounds
        let presentedCornerRadius = isFullScreen ? UIScreen.main.displayCornerRadius : container.parentViewController?.sheetPresentationController?.preferredCornerRadius ?? 0
        let dismissedCornerRadius = flipConfig?.sourcePrimaryFlipView.cornerRadius ?? presentedCornerRadius

        let dismissedFrame: CGRect
        if let matchedSourceView = flipConfig?.sourcePrimaryFlipView {
            dismissedFrame = container.convert(matchedSourceView.bounds, from: matchedSourceView)
        } else {
            dismissedFrame = container.bounds
        }

        foregroundContainerView.zPosition = 400
        animator[overlayView, \.progress].presentedValue = 1

        // corner radius
        animator[foregroundContainerView, \UIView.cornerRadius].presentedValue = presentedCornerRadius
        animator[foregroundContainerView, \UIView.cornerRadius].dismissedValue = dismissedCornerRadius

        // frame
        animator[foregroundContainerView, \UIView.bounds.size].dismissedValue = dismissedFrame.size
        animator[foregroundContainerView, \UIView.center].dismissedValue = dismissedFrame.center

        // progress
        animator[foregroundContainerView, \MultiFlipContainerView.progress].dismissedValue = 0
        animator[foregroundContainerView, \MultiFlipContainerView.progress].presentedValue = 1

        let otherSubviews = (flipConfig?.sourceContainerView?.subviews ?? []).filter { $0 != flipConfig?.sourcePrimaryFlipView }
        let otherImageViews = otherSubviews.filter { $0 is UIImageView }
        let otherNonImageViews = otherSubviews.filter { !($0 is UIImageView) }
        for (i, view) in otherImageViews.enumerated() {
            let secondaryContainerView = SecondaryFlipContainerView()
            let transform = view.transform
            view.transform = .identity
            secondaryContainerView.progressDelay = CGFloat(otherSubviews.count - i) * 0.001
            secondaryContainerView.progressScale = CGFloat(i) * 0.5 + 1.0
            secondaryContainerView.frameWithoutTransform = container.convert(view.bounds, from: view)
            secondaryContainerView.transform = transform
            view.transform = transform
            secondaryContainerView.baseRotation = transform.rotation
            secondaryContainerView.backgroundView = view
            secondaryContainerView.zPosition = 300
            secondaryContainerView.autoresizingMask = []
            secondaryContainerView.translatesAutoresizingMaskIntoConstraints = false
            context.background.addSubview(secondaryContainerView)

            animator[secondaryContainerView, \SecondaryFlipContainerView.progress].dismissedValue = 0
            animator[secondaryContainerView, \SecondaryFlipContainerView.progress].presentedValue = 1
            view.isHidden = true

            animator.addCompletion { position in
                view.isHidden = false
                secondaryContainerView.removeFromSuperview()
            }
        }
        for view in otherNonImageViews {
            animator[view, \UIView.alpha].dismissedValue = 1
            animator[view, \UIView.alpha].presentedValue = 0
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
            context.container.addGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
            interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)
        } else {
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
            foregroundContainerView.foregroundView = nil
            let foregroundView = context.foreground
            foregroundView.isHidden = false
            foregroundContainerView.superview?.insertSubview(foregroundView, aboveSubview: foregroundContainerView)
        }

        flipConfig?.sourcePrimaryFlipView.isHidden = false
        overlayView?.removeFromSuperview()
        context.foreground.lockedSafeAreaInsets = nil
        foregroundContainerView?.removeFromSuperview()

        interruptibleHorizontalDismissGestureRecognizer.view?.removeGestureRecognizer(interruptibleHorizontalDismissGestureRecognizer)
        interruptibleTapRepresentGestureRecognizer.view?.removeGestureRecognizer(interruptibleTapRepresentGestureRecognizer)

        self.overlayView = nil
        self.foregroundContainerView = nil
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
            animator[foregroundContainerView, \UIView.center].currentValue += translation * (isMatched ? 0.3 : 1.0)
            animator.shift(progress: progress)
        default:
            guard let context, let animator, let foregroundContainerView else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity / 2
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            animator[foregroundContainerView, \UIView.center].velocity = velocity
            if isMatched {
                animator[foregroundContainerView, \UIView.scale].dismissedValue = flipConfig?.sourcePrimaryFlipView.scale ?? 1
            } else {
                let angle = translationPlusVelocity / context.container.bounds.size
                let offset = angle / angle.distance(.zero) * 1.4 * context.container.bounds.size
                let targetOffset = context.container.bounds.center + offset
                animator[foregroundContainerView, \UIView.center].dismissedValue = targetOffset
            }
            animateTo(position: shouldDismiss ? .dismissed : .presented)
        }
    }

    @objc func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reverse()
    }
}

extension MultiFlipTransition: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == interruptibleTapRepresentGestureRecognizer, let foregroundContainerView {
            return foregroundContainerView.point(inside: gestureRecognizer.location(in: foregroundContainerView), with: nil)
        }
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer || gestureRecognizer == horizontalEdgeDismissGestureRecognizer {
            if velocity.x > abs(velocity.y) {
                return true
            }
        }
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer, let scrollView = otherGestureRecognizer.view as? UIScrollView, otherGestureRecognizer == scrollView.panGestureRecognizer {
            if scrollView.contentSize.width > scrollView.bounds.inset(by: scrollView.adjustedContentInset).width, gestureRecognizer == interruptibleHorizontalDismissGestureRecognizer || gestureRecognizer == horizontalDismissGestureRecognizer {
                return scrollView.contentOffset.x <= -scrollView.adjustedContentInset.left + 1.0
            }
            return true
        }
        return false
    }
}


public class MultiFlipContainerView: UIView {

    var rotated: Bool = false
    var progress: CGFloat = 0 {
        didSet {
            let rotation = Motion.EasingFunction.easeOut.solveInterpolatedValue(-.pi...0, fraction: progress)
            let sinProgress = sin(progress * .pi)
            let tilt = sinProgress * 0.15
            layer.transform = .identity.translatedBy(z: progress * 1000).withPerspective(m34: 1 / 1000)
                .translatedBy(x: sinProgress * 200, y: sinProgress * 20)
                .rotatedBy(tilt)
                .rotatedBy(y: rotation)
            rotated = abs(rotation - tilt) > .pi / 2
            foregroundView?.isHidden = rotated
            backgroundSnapshot?.isHidden = !rotated
            contentView.transform = .identity.scaledBy(x: !rotated ? 1 : -1)
            shadowOpacity = progress * 0.5
            setNeedsLayout()
        }
    }

    var backgroundSnapshot: UIView?
    var backgroundView: UIView? {
        didSet {
            guard let backgroundView else { return }
            backgroundSnapshot = backgroundView.snapshotView(afterScreenUpdates: true)
            backgroundSnapshot?.bounds = backgroundView.bounds
            contentView.addSubview(backgroundSnapshot!)
            setNeedsLayout()
        }
    }

    var foregroundView: UIView? {
        didSet {
            guard let foregroundView else { return }
            foregroundView.autoresizingMask = []
            foregroundView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(foregroundView)
            setNeedsLayout()
        }
    }

    public let contentView = UIView()

    public override var cornerRadius: CGFloat {
        didSet {
            contentView.cornerRadius = cornerRadius
        }
    }

    public override var frameWithoutTransform: CGRect {
        didSet {
            recalculateShadowPath()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(contentView)
        cornerCurve = .continuous
        contentView.cornerCurve = .continuous
        contentView.autoresizingMask = []
        contentView.autoresizesSubviews = false
        contentView.clipsToBounds = true
        shadowColor = UIColor(dark: .black, light: .black.withAlphaComponent(0.6))
        shadowRadius = 48
        shadowOpacity = 1.0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func recalculateShadowPath() {
        shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let targetSize = foregroundView?.bounds.size ?? CGSize(width: 1, height: 1)
        let sourceSize = backgroundView?.bounds.size ?? CGSize(width: 1, height: 1)
        let width = !rotated ? targetSize.width * (bounds.height / targetSize.height) : sourceSize.width * (bounds.height / sourceSize.height)
        contentView.frameWithoutTransform = CGRect(center: bounds.center, size: CGSize(width: width, height: bounds.height))

        if let foregroundView {
            let foregroundSize = foregroundView.bounds.size
            foregroundView.scale = foregroundSize.size(fill: contentView.bounds.size).width / foregroundSize.width
            foregroundView.center = contentView.bounds.center
        }

        if let backgroundSnapshot {
            backgroundSnapshot.frameWithoutTransform = contentView.bounds
        }
    }
}

public class SecondaryFlipContainerView: UIView {
    var baseRotation: CGFloat = 0
    var progressDelay: CGFloat = 0
    var progressScale: CGFloat = 1.0
    var progress: CGFloat = 0 {
        didSet {
            let t = ((progress - progressDelay) * progressScale / (1 - progressDelay)).clamp(0, 1)
            let rotation = Motion.EasingFunction.easeOut.solveInterpolatedValue(0...(CGFloat.pi * 0.5), fraction: t)
            isHidden = rotation >= .pi / 2
            layer.transform = .identity.withPerspective(m34: 1 / 1000)
                .scaledBy(1.0 + t * 2.5)
                .translatedBy(x: t * 400, y: t * 150)
                .rotatedBy(baseRotation + t * 1.2)
                .rotatedBy(y: rotation)
        }
    }

    var backgroundSnapshot: UIView?
    var backgroundView: UIView? {
        didSet {
            guard let backgroundView else { return }
            backgroundSnapshot = backgroundView.snapshotView(afterScreenUpdates: true)
            addSubview(backgroundSnapshot!)
            setNeedsLayout()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if let backgroundSnapshot {
            backgroundSnapshot.frameWithoutTransform = bounds
        }
    }
}
