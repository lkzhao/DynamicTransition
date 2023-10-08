//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/7/23.
//

import UIKit
import BaseToolbox

class MatchTransitionRunner {
    let context: TransitionContext
    let completion: (Bool) -> Void

    var from: UIViewController { context.from }
    var to: UIViewController { context.to }
    var container: UIView { context.container }
    var isPresenting: Bool { context.isPresenting }
    var foreground: UIViewController { context.foreground }
    var background: UIViewController { context.background }
    var foregroundView: UIView { context.foregroundView }
    var backgroundView: UIView { context.backgroundView }

    let foregroundContainerView = MatchTransitionContainerView()

    var isTransitioningVertically: Bool

    var matchedSourceView: UIView?
    var matchedDestinationView: UIView?
    var sourceViewSnapshot: UIView?
    let overlayView = UIView().with {
        $0.backgroundColor = UIColor(dark: .black.withAlphaComponent(0.6), light: .black.withAlphaComponent(0.4))
    }

    var presentedState: ViewState = ViewState()
    var dismissedState: ViewState = ViewState()

    var scrollViewObserver: Any?

    init(context: TransitionContext,
         isTransitioningVertically: Bool,
         completion: @escaping (Bool) -> Void) {
        self.context = context
        self.isTransitioningVertically = isTransitioningVertically
        self.completion = completion

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

        calculatTargetStates()
    }

    func calculatTargetStates() {
        let defaultDismissedFrame = isTransitioningVertically ? container.bounds.offsetBy(dx: 0, dy: container.bounds.height) : container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
        let dismissedFrame = matchedSourceView.map {
            container.convert($0.bounds, from: $0)
        } ?? defaultDismissedFrame
        let presentedFrame = matchedDestinationView.map {
            container.convert($0.bounds, from: $0)
        } ?? container.bounds

        let isFullScreen = container.window?.convert(container.bounds, from: container) == container.window?.bounds
        presentedState = ViewState(foregroundContainerCornerRadius: isFullScreen ? UIScreen.main.displayCornerRadius : 0,
                                       foregroundContainerFrame: container.bounds,
                                       foregroundTranslation: .zero,
                                       foregroundRotation: 0,
                                       foregroundScale: 1,
                                       sourceViewFrame: presentedFrame,
                                       sourceViewAlpha: 0)

        let scaledSize = presentedFrame.size.size(fill: dismissedFrame.size)
        let scale = scaledSize.width / container.bounds.width
        let sizeOffset = -(scaledSize - dismissedFrame.size) / 2
        let originOffset = -presentedFrame.minY * scale
        let offsetX = -(1 - scale) / 2 * container.bounds.width
        let offsetY = -(1 - scale) / 2 * container.bounds.height
        let offset = CGPoint(
            x: offsetX + sizeOffset.width,
            y: offsetY + sizeOffset.height + originOffset)

        dismissedState = ViewState(foregroundContainerCornerRadius: matchedSourceView?.cornerRadius ?? 0,
                                       foregroundContainerFrame: dismissedFrame,
                                       foregroundTranslation: offset,
                                       foregroundRotation: 0,
                                       foregroundScale: scale,
                                       sourceViewFrame: dismissedFrame.bounds,
                                       sourceViewAlpha: 1)
    }

    struct ViewState {
        var foregroundContainerCornerRadius: CGFloat = .zero
        var foregroundContainerFrame: CGRect = .zero
        var foregroundTranslation: CGPoint = .zero
        var foregroundRotation: CGFloat = .zero
        var foregroundScale: CGFloat = .zero
        var sourceViewFrame: CGRect = .zero
        var sourceViewAlpha: CGFloat = .zero
    }

    var completingTransition: Bool?

    func completeTransition(shouldFinish: Bool) {
        completingTransition = shouldFinish
        let targetState: ViewState = isPresenting == shouldFinish ? presentedState : dismissedState
        apply(state: targetState, animated: true) { [completion] completed in
            if completed {
                completion(shouldFinish)
            }
        }
    }

    func apply(state: ViewState, animated: Bool, completion: ((Bool) -> Void)?) {
        let stiffness: Double = 350
        let damping: Double = 30
        foregroundContainerView.yaal.cornerRadius.updateTo(value: state.foregroundContainerCornerRadius, animated: animated, stiffness: stiffness, damping: damping)
        foregroundContainerView.yaal.size.updateTo(value: state.foregroundContainerFrame.size, animated: animated, stiffness: stiffness, damping: damping, threshold: 1.0, completion: completion)
        foregroundContainerView.yaal.center.updateTo(value: state.foregroundContainerFrame.center, animated: animated, stiffness: stiffness, damping: damping, threshold: 1.0)
        foregroundContainerView.yaal.rotation.updateTo(value: state.foregroundRotation, animated: animated, stiffness: stiffness, damping: damping)
        overlayView.yaal.alpha.updateTo(value: 1 - state.sourceViewAlpha, animated: animated, stiffness: stiffness, damping: damping)
        foregroundContainerView.yaal.shadowOpacity.updateTo(value: 1 - state.sourceViewAlpha, animated: animated, stiffness: stiffness, damping: damping)
        foregroundView.yaal.translation.updateTo(value: state.foregroundTranslation, animated: animated, stiffness: stiffness, damping: damping, threshold: 1.0)
        foregroundView.yaal.scale.updateTo(value: state.foregroundScale, animated: animated, stiffness: stiffness, damping: damping)
        sourceViewSnapshot?.yaal.size.updateTo(value: state.sourceViewFrame.size, animated: animated, stiffness: stiffness, damping: damping, threshold: 1.0)
        sourceViewSnapshot?.yaal.center.updateTo(value: state.sourceViewFrame.center, animated: animated, stiffness: stiffness, damping: damping, threshold: 1.0)
        sourceViewSnapshot?.yaal.alpha.updateTo(value: state.sourceViewAlpha, animated: animated, stiffness: stiffness, damping: damping)
    }

    func pause() {
        completingTransition = nil
        foregroundContainerView.yaal.cornerRadius.stop()
        foregroundContainerView.yaal.size.stop()
        foregroundContainerView.yaal.center.stop()
        foregroundView.yaal.translation.stop()
        foregroundView.yaal.scale.stop()
        sourceViewSnapshot?.yaal.size.stop()
        sourceViewSnapshot?.yaal.center.stop()
        sourceViewSnapshot?.yaal.alpha.stop()
    }

    func currentState() -> ViewState {
        ViewState(foregroundContainerCornerRadius: foregroundContainerView.cornerRadius,
                  foregroundContainerFrame: foregroundContainerView.frameWithoutTransform,
                  foregroundTranslation: foregroundView.yaal.translation.value.value,
                  foregroundRotation: foregroundView.yaal.rotation.value.value,
                  foregroundScale: foregroundView.yaal.scale.value.value,
                  sourceViewFrame: sourceViewSnapshot?.frameWithoutTransform ?? .zero,
                  sourceViewAlpha: sourceViewSnapshot?.alpha ?? 0)
    }

    func add(progress: CGFloat, newCenter: CGPoint, rotation: CGFloat) {
        let currentState = currentState()
        let targetState = isPresenting ? presentedState : dismissedState
        let sourceState = isPresenting ? dismissedState : presentedState
        let foregroundContainerCornerRadius = (targetState.foregroundContainerCornerRadius - sourceState.foregroundContainerCornerRadius) * progress + currentState.foregroundContainerCornerRadius
        let foregroundContainerFrame = (targetState.foregroundContainerFrame - sourceState.foregroundContainerFrame) * progress + currentState.foregroundContainerFrame
        let foregroundTranslation = (targetState.foregroundTranslation - sourceState.foregroundTranslation) * progress + currentState.foregroundTranslation
        let foregroundScale = (targetState.foregroundScale - sourceState.foregroundScale) * progress + currentState.foregroundScale
        let sourceViewFrame = (targetState.sourceViewFrame - sourceState.sourceViewFrame) * progress + currentState.sourceViewFrame
        let sourceViewAlpha = (targetState.sourceViewAlpha - sourceState.sourceViewAlpha) * progress + currentState.sourceViewAlpha

        let newState = ViewState(foregroundContainerCornerRadius: foregroundContainerCornerRadius,
                                 foregroundContainerFrame: CGRect(center: newCenter, size: foregroundContainerFrame.size),
                                 foregroundTranslation: foregroundTranslation,
                                 foregroundRotation: rotation,
                                 foregroundScale: foregroundScale,
                                 sourceViewFrame: sourceViewFrame,
                                 sourceViewAlpha: sourceViewAlpha)

        apply(state: newState, animated: false, completion: nil)
    }

    func onCompletion(finished: Bool) {
        if finished == isPresenting {
            container.addSubview(foregroundView)
        } else {
            container.addSubview(backgroundView)
        }
        scrollViewObserver = nil
        completingTransition = nil
        matchedSourceView?.isHidden = false
        overlayView.removeFromSuperview()
        foregroundContainerView.removeFromSuperview()
        context.completeTransition(finished)
    }

    func targetDidChange() {
        guard let completingTransition else { return }
        let oldDismissState = dismissedState
        calculatTargetStates()
        let newDismissState = dismissedState
        let diff = newDismissState.foregroundContainerFrame.center - oldDismissState.foregroundContainerFrame.center
        if diff != .zero {
            foregroundContainerView.center += diff
            foregroundContainerView.yaal.center.updateWithCurrentState()
        }
        completeTransition(shouldFinish: completingTransition)
    }
}
