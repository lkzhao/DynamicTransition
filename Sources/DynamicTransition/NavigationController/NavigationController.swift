//
//  NavigationView.swift
//
//  Created by Luke Zhao on 10/6/23.
//

import UIKit
import BaseToolbox

open class NavigationController: UIViewController, EventReceiver {
    struct State {
        struct TransitionState {
            var context: NavigationTransitionContext
            var transition: Transition
            var source: [UIViewController]
            var target: [UIViewController]
        }
        var children: [UIViewController]
        var transition: TransitionState?
        var nextAction: Event.NavigationAction?
    }

    enum Event {
        enum NavigationAction {
            case push(UIViewController)
            case dismiss(UIViewController)
            case pop
            case popToRoot
            case set([UIViewController])

            func target(from source: [UIViewController]) -> [UIViewController] {
                switch self {
                case .push(let vc):
                    return source + [vc]
                case .dismiss(let vc):
                    guard let index = source.firstIndex(of: vc) else {
                        assertionFailure("The ViewController doesn't exist in the NavigationController's stack")
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

        case navigate(NavigationAction)
        case didCompleteTransition
        case didCancelTransition
    }

    class NavigationTransitionContext: TransitionContext {
        var container: UIView
        var from: UIViewController
        var to: UIViewController
        var store: any EventStore<Event>

        var isPresenting: Bool
        var isInteractive: Bool = false

        init(container: UIView, isPresenting: Bool, from: UIViewController, to: UIViewController, store: any EventStore<Event>) {
            self.container = container
            self.isPresenting = isPresenting
            self.from = from
            self.to = to
            self.store = store
        }

        func completeTransition(_ didComplete: Bool) {
            store.send(didComplete ? .didCompleteTransition : .didCancelTransition)
        }
    }

    enum Action {
        case none
        case run(() -> ())
    }

    lazy var store = Store(target: self)

    var state: State

    public var viewControllers: [UIViewController] {
        state.transition?.target ?? state.children
    }

    public init(rootViewController: UIViewController) {
        self.state = State(children: [rootViewController])
        setupCustomPresentation()
        super.init(nibName: nil, bundle: nil)
        addChild(rootViewController)
        view.addSubview(rootViewController.view)
        rootViewController.didMove(toParent: self)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func receive(_ event: Event) {
        let action = process(event: event, state: &state)
        switch action {
        case .run(let block):
            block()
        case .none:
            break
        }
    }

    func process(event: Event, state: inout State) -> Action {
        switch event {
        case .navigate(let navigationAction):
            let source = state.children
            let target = navigationAction.target(from: source)
            guard state.transition == nil else {
                state.nextAction = navigationAction
                return .none
            }
            state.nextAction = nil
            guard target != source, let to = target.last, let from = source.last else { return .none }
            guard from != to else {
                state.children = target
                return .none
            }
            let isPresenting = target.count > source.count
            let foreground = isPresenting ? to : from
            let background = isPresenting ? from : to
            let transition: Transition = foreground.findObjectMatchType(TransitionProvider.self)?.transitionFor(presenting: isPresenting, otherViewController: background) ?? MatchTransition()
            let context = NavigationTransitionContext(container: view, isPresenting: isPresenting, from: from, to: to, store: store)
            state.transition = State.TransitionState(context: context, transition: transition, source: source, target: target)

            return .run {
                from.beginAppearanceTransition(false, animated: true)
                to.beginAppearanceTransition(true, animated: true)

                from.willMove(toParent: nil)
                self.addChild(to)
                self.view.addSubview(to.view)
                transition.animateTransition(context: context)
            }
        case .didCompleteTransition:
            guard let transitionState = state.transition else { return .none }
            state.transition = nil
            state.children = transitionState.target
            let nextAction = state.nextAction
            return .run { [store] in
                self.view.setNeedsLayout()
                transitionState.source.last?.view.removeFromSuperview()
                transitionState.source.last?.removeFromParent()
                transitionState.target.last?.didMove(toParent: self)
                transitionState.source.last?.endAppearanceTransition()
                transitionState.target.last?.endAppearanceTransition()

                if let nextAction {
                    store.send(.navigate(nextAction))
                }
            }
        case .didCancelTransition:
            guard let transitionState = state.transition else { return .none }
            state.transition = nil
            state.children = transitionState.source
            let nextAction = state.nextAction
            return .run { [store] in
                self.view.setNeedsLayout()
                transitionState.target.last?.beginAppearanceTransition(false, animated: false)
                transitionState.target.last?.view.removeFromSuperview()
                transitionState.target.last?.removeFromParent()
                transitionState.source.last?.didMove(toParent: self)
                transitionState.source.last?.endAppearanceTransition()
                transitionState.target.last?.endAppearanceTransition()

                if let nextAction {
                    store.send(.navigate(nextAction))
                }
            }
        }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let topVC = children.last, state.transition == nil else { return }
        topVC.view.frameWithoutTransform = view.bounds
    }

    // MARK: - navigation methods

    open func pushViewController(_ viewController: UIViewController, animated: Bool) {
        store.send(.navigate(.push(viewController)))
    }

    open func popViewController(animated: Bool) {
        store.send(.navigate(.pop))
    }

    open func popToRootViewController(animated: Bool) {
        store.send(.navigate(.popToRoot))
    }

    open func dismissToViewController(_ viewController: UIViewController, animated: Bool) {
        store.send(.navigate(.dismiss(viewController)))
    }

    open func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        store.send(.navigate(.set(viewControllers)))
    }

    // MARK: - override child UIViewController methods

    open override var childForStatusBarStyle: UIViewController? {
        viewControllers.last
    }

    open override var childForStatusBarHidden: UIViewController? {
        viewControllers.last
    }

    open override var childForHomeIndicatorAutoHidden: UIViewController? {
        viewControllers.last
    }

    open override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        viewControllers.last
    }

    open override var childViewControllerForPointerLock: UIViewController? {
        viewControllers.last
    }
}
