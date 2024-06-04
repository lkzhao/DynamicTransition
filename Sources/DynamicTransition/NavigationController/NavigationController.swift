//
//  NavigationView.swift
//
//
//  Created by Luke Zhao on 10/6/23.
//

import UIKit
import BaseToolbox

public protocol NavigationControllerDelegate: AnyObject {
    func navigationControllerDidUpdate(views: [UIView])
}

open class NavigationController: UIViewController {
    private struct State {
        struct TransitionState {
            var context: NavigationTransitionContext
            var transition: Transition
            var source: [UIView]
            var target: [UIView]
        }
        var children: [UIView]
        var transitions: [TransitionState] = []
        var nextAction: (Event.NavigationAction, Bool)?
    }

    private struct DisplayState {
        var views: [UIView]
        var preferredStatusBarStyle: UIStatusBarStyle
    }

    private enum Event {
        enum NavigationAction {
            case push(UIView)
            case dismiss(UIView)
            case pop
            case popToRoot
            case set([UIView])

            func target(from source: [UIView]) -> [UIView] {
                switch self {
                case .push(let vc):
                    return source + [vc]
                case .dismiss(let vc):
                    guard let index = source.firstIndex(of: vc) else {
                        assertionFailure("The View doesn't exist in the NavigationController's stack")
                        return source
                    }
                    return source[0..<max(1, index)].array
                case .pop:
                    return source[0..<max(1, source.count - 1)].array
                case .popToRoot:
                    return [source.first!]
                case .set(let vcs):
                    guard !vcs.isEmpty else {
                        assertionFailure("Cannot set empty view controllers to NavigationController")
                        return source
                    }
                    return vcs
                }
            }
        }

        case navigate(NavigationAction, animated: Bool)
        case didCompleteTransition(NavigationTransitionContext)
        case didCancelTransition(NavigationTransitionContext)
    }

    private class NavigationTransitionContext: TransitionContext {
        weak var navigationController: NavigationController?
        let id = UUID()
        var container: UIView
        var from: UIView
        var to: UIView

        var isPresenting: Bool
        var isInteractive: Bool
        var isCompleting: Bool

        init(container: UIView, isPresenting: Bool, from: UIView, to: UIView, isInteractive: Bool, navigationController: NavigationController) {
            self.container = container
            self.isPresenting = isPresenting
            self.from = from
            self.to = to
            self.navigationController = navigationController
            self.isInteractive = isInteractive
            self.isCompleting = true
        }

        func completeTransition(_ didComplete: Bool) {
            navigationController?.process(didComplete ? .didCompleteTransition(self) : .didCancelTransition(self))
        }

        func beginInteractiveTransition() {
            isInteractive = true
        }

        func endInteractiveTransition(_ isCompleting: Bool) {
            isInteractive = false
            if isCompleting != self.isCompleting {
                self.isCompleting = isCompleting
                navigationController?.didUpdateViews()
            }
        }
    }

    public weak var delegate: NavigationControllerDelegate?

    public var defaultTransition: Transition = PushTransition()

    private var state: State

    private var displayState: DisplayState {
        didSet {
            if displayState.preferredStatusBarStyle != oldValue.preferredStatusBarStyle {
                UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.setNeedsStatusBarAppearanceUpdate()
                }
            }
            if displayState.views != oldValue.views {
                delegate?.navigationControllerDidUpdate(views: displayState.views)
            }
        }
    }

    public var views: [UIView] {
        displayState.views
    }

    public var topView: UIView {
        displayState.views.last!
    }

    public init(rootView: UIView) {
        self.state = State(children: [rootView])
        self.displayState = DisplayState(views: [rootView], preferredStatusBarStyle: (rootView as? RootViewType)?.preferredStatusBarStyle ?? .default)
        setupCustomPresentation()
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .systemBackground
        view.addSubview(rootView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open func transitionFor(isPresenting: Bool, from: UIView, to: UIView) -> Transition {
        let foreground = isPresenting ? to : from
        let background = isPresenting ? from : to
        return (foreground as? TransitionProvider)?.transitionFor(presenting: isPresenting, otherView: background) ?? defaultTransition
    }

    private func process(_ event: Event) {
        var state = state
        var runBlock: (() -> Void)? = nil

        switch event {
        case .navigate(let navigationAction, let animated):
            print(navigationAction)
            let source = displayState.views
            let target = navigationAction.target(from: source)
            guard target != source, let to = target.last, let from = source.last else { break }
            guard from != to else {
                state.children = target
                break
            }
            let isPresenting = target.count >= source.count
            let transition = animated ? transitionFor(isPresenting: isPresenting, from: from, to: to) : NoTransition()

            if let transitionState = state.transitions.first(where: { $0.transition === transition }) {
                // the transition is already running
                if transitionState.target == source, transitionState.source == target {
                    // reverse the transition
                    transitionState.transition.reverse()
                }
                // otherwise just ignore
                break
            }

            guard state.transitions.isEmpty || state.transitions.allSatisfy({ $0.transition.canTransitionSimutanously(with: transition) && transition.canTransitionSimutanously(with: $0.transition) }) else {
                // can't transition simutanously
                state.nextAction = (navigationAction, animated)
                break
            }

            let isInteractiveStart = transition.wantsInteractiveStart
            let context = NavigationTransitionContext(container: view, isPresenting: isPresenting, from: from, to: to, isInteractive: isInteractiveStart, navigationController: self)
            let transitionState = State.TransitionState(context: context, transition: transition, source: source, target: target)
            state.transitions.append(transitionState)

            runBlock = {
                (from as? RootViewType)?.willDisappear(animated: true)
                (to as? RootViewType)?.willAppear(animated: true)
                transition.animateTransition(context: context)
                self.didUpdateViews()
            }
        case .didCompleteTransition(let context):
            guard let index = state.transitions.firstIndex(where: { $0.context.id == context.id }) else { break }
            let transitionState = state.transitions.remove(at: index)
            state.children = transitionState.target
            let nextAction = state.nextAction
            state.nextAction = nil
            runBlock = {
                self.view.setNeedsLayout()
                if let source = transitionState.source.last {
                    (source as? RootViewType)?.didDisappear(animated: true)
                }
                if let target = transitionState.target.last {
                    (target as? RootViewType)?.didAppear(animated: true)
                }
                self.didUpdateViews()
                if let (navigationAction, animated) = nextAction {
                    self.process(.navigate(navigationAction, animated: animated))
                }
            }
        case .didCancelTransition(let context):
            guard let index = state.transitions.firstIndex(where: { $0.context.id == context.id }) else { break }
            let transitionState = state.transitions.remove(at: index)
            state.children = transitionState.source
            let nextAction = state.nextAction
            state.nextAction = nil
            runBlock = {
                self.view.setNeedsLayout()
                if let target = transitionState.target.last {
                    (target as? RootViewType)?.willDisappear(animated: false)
                    (target as? RootViewType)?.didDisappear(animated: false)
                }
                if let source = transitionState.source.last {
                    (source as? RootViewType)?.didAppear(animated: true)
                }
                self.didUpdateViews()
                if let (navigationAction, animated) = nextAction {
                    self.process(.navigate(navigationAction, animated: animated))
                }
            }
        }

        self.state = state
        runBlock?()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for subview in view.subviews {
            subview.frameWithoutTransform = view.bounds
        }
    }

    // MARK: - Appearance methods

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (topView as? RootViewType)?.willAppear(animated: animated)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        (topView as? RootViewType)?.didAppear(animated: animated)
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        (topView as? RootViewType)?.didDisappear(animated: animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        (topView as? RootViewType)?.willDisappear(animated: animated)
    }

    // MARK: - Navigation methods

    open func pushView(_ view: UIView, animated: Bool = true) {
        process(.navigate(.push(view), animated: animated))
    }

    open func popView(animated: Bool = true) {
        process(.navigate(.pop, animated: animated))
    }

    open func popToRootView(animated: Bool = true) {
        process(.navigate(.popToRoot, animated: animated))
    }

    open func dismissToView(_ view: UIView, animated: Bool = true) {
        process(.navigate(.dismiss(view), animated: animated))
    }

    open func setViews(_ views: [UIView], animated: Bool = true) {
        process(.navigate(.set(views), animated: animated))
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        displayState.preferredStatusBarStyle
    }

    private func didUpdateViews() {
        let newViews: [UIView] = state.transitions.last(where: { $0.context.isCompleting })?.target ?? state.children
        let newStatusBarStyle = (newViews.last as? RootViewType)?.preferredStatusBarStyle ?? .default
        displayState = DisplayState(views: newViews, preferredStatusBarStyle: newStatusBarStyle)
    }
}
