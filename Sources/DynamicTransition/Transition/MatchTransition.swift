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
    /// Allow the transition to dismiss vertically via its `verticalDismissGestureRecognizer`
    public var canDismissVertically = true

    /// Allow the transition to dismiss horizontally via its `horizontalDismissGestureRecognizer`
    public var canDismissHorizontally = true

    /// If `true`, the `verticalDismissGestureRecognizer` & `horizontalDismissGestureRecognizer`  will be automatically added to the foreground view during presentation
    public var automaticallyAddDismissGestureRecognizer: Bool = true

    /// How much the foreground container moves when user drag across screen. This can be any value above or equal to 0.
    /// Default is 0.5, which means when user drag across the screen from left to right, the container move 50% of the screen.
    public var dragTranslationFactor: CGPoint = CGPoint(x: 0.5, y: 0.5)

    public var onDragStart: ((MatchTransition) -> ())?
}

extension MixAnimation {
    func updateTo(value: Value, animated: Bool, stiffness: Double? = nil, damping: Double? = nil, threshold: CGFloat = 0.001, completion: ((Bool) -> ())? = nil) {
        if animated {
            self.animateTo(value, stiffness: stiffness, damping: damping, threshold: threshold, completionHandler: completion)
        } else {
            self.setTo(value)
            completion?(true)
        }
    }
}
extension Yaal where Base: UIView {
    public var frameWithoutTransform: MixAnimation<CGRect> {
        return animationFor(key: "frameWithoutTransform",
                            getter: { [weak base] in base?.frameWithoutTransform },
                            setter: { [weak base] in base?.frameWithoutTransform = $0 })
    }
    public var size: MixAnimation<CGSize> {
        return animationFor(key: "size",
                            getter: { [weak base] in base?.bounds.size },
                            setter: { [weak base] in base?.bounds.size = $0 })
    }
    public var cornerRadius: MixAnimation<CGFloat> {
        return animationFor(key: "cornerRadius",
                            getter: { [weak base] in base?.cornerRadius },
                            setter: { [weak base] in base?.cornerRadius = $0 })
    }
    public var shadowOpacity: MixAnimation<CGFloat> {
        return animationFor(key: "shadowOpacity",
                            getter: { [weak base] in base?.shadowOpacity },
                            setter: { [weak base] in base?.shadowOpacity = $0 })
    }
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
            if options.automaticallyAddDismissGestureRecognizer {
                front.addGestureRecognizer(verticalDismissGestureRecognizer)
                front.addGestureRecognizer(horizontalDismissGestureRecognizer)
            }
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
            if runner.matchedSourceView != nil {
                let maxAxis = max(container.bounds.width, container.bounds.height)
                let progress = (offset.x / maxAxis + offset.y / maxAxis) * 1.5
                return runner.isPresenting ? -progress : progress
            } else {
                let progress = isTransitioningVertically ? offset.y / container.bounds.height : offset.x / container.bounds.width
                return runner.isPresenting ? -progress : progress
            }
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
            let newCenter = runner.foregroundContainerView.center + translation * options.dragTranslationFactor
            let rotation = runner.foregroundContainerView.yaal.rotation.value.value + translation.x * 0.0003
            runner.add(progress: progress, newCenter: newCenter, rotation: rotation)
        default:
            guard let runner else { return }
            let velocity = gr.velocity(in: nil)
            let translationPlusVelocity = totalTranslation + velocity
            let shouldDismiss = translationPlusVelocity.x + translationPlusVelocity.y > 80
            let shouldFinish = runner.isPresenting ? !shouldDismiss : shouldDismiss
            if shouldDismiss {
                interruptibleVerticalDismissGestureRecognizer.isEnabled = false
                interruptibleHorizontalDismissGestureRecognizer.isEnabled = false
                runner.foregroundContainerView.isUserInteractionEnabled = false
                runner.overlayView.isUserInteractionEnabled = false
            }
            runner.foregroundContainerView.yaal.center.velocity.value = velocity
            runner.completeTransition(shouldFinish: shouldFinish)
        }
    }
}

extension MatchTransition: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
//        guard gestureRecognizer.view?.canBeDismissed == true else { return false }
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = gestureRecognizer.velocity(in: nil)
        if gestureRecognizer == interruptibleVerticalDismissGestureRecognizer || gestureRecognizer == verticalDismissGestureRecognizer {
            let vertical = options.canDismissVertically && velocity.y > abs(velocity.x)
            isTransitioningVertically = true
            return vertical
        } else {
            let horizontal = options.canDismissHorizontally && velocity.x > abs(velocity.y)
            isTransitioningVertically = false
            return horizontal
        }
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
    let contentView = UIView()

    override var cornerRadius: CGFloat {
        didSet {
            contentView.cornerRadius = cornerRadius
        }
    }

    override var frameWithoutTransform: CGRect {
        didSet {
            recalculateShadowPath()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(contentView)
        cornerCurve = .continuous
        contentView.cornerCurve = .continuous
        contentView.autoresizingMask = []
        contentView.autoresizesSubviews = false
        contentView.clipsToBounds = true
        shadowColor = UIColor(dark: .black, light: .black.withAlphaComponent(0.4))
        shadowRadius = 36
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
    }

    func recalculateShadowPath() {
        shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
    }
}

protocol Arithmetic {
    static func +(lhs: Self, rhs: Self) -> Self
    static func -(lhs: Self, rhs: Self) -> Self
    static func *(lhs: Self, rhs: Self) -> Self
    static func /(lhs: Self, rhs: Self) -> Self
    static func *(lhs: Self, rhs: CGFloat) -> Self
    static func /(lhs: Self, rhs: CGFloat) -> Self
}

extension CGFloat : Arithmetic {}
extension CGSize : Arithmetic {}
extension CGPoint : Arithmetic {}
extension CGRect : Arithmetic {
    static func + (lhs: Self, rhs: Self) -> Self {
        CGRect(origin: lhs.origin + rhs.origin, size: lhs.size + rhs.size)
    }
    static func - (lhs: Self, rhs: Self) -> Self {
        CGRect(origin: lhs.origin - rhs.origin, size: lhs.size - rhs.size)
    }
    static func * (lhs: CGRect, rhs: CGRect) -> CGRect {
        CGRect(origin: lhs.origin * rhs.origin, size: lhs.size * rhs.size)
    }
    static func / (lhs: CGRect, rhs: CGRect) -> CGRect {
        CGRect(origin: lhs.origin / rhs.origin, size: lhs.size / rhs.size)
    }
}
