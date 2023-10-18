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
        var transitions: [TransitionState] = []
        var nextAction: Event.NavigationAction?

        var viewControllers: [UIViewController] {
            if let transition = transitions.last(where: { $0.context.isCompleting }) {
                return transition.target
            } else {
                return children
            }
        }
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
        case didCompleteTransition(NavigationTransitionContext)
        case didCancelTransition(NavigationTransitionContext)
    }

    class NavigationTransitionContext: TransitionContext {
        let id = UUID()
        var container: UIView
        var from: UIViewController
        var to: UIViewController
        var store: any EventStore<Event>

        var isPresenting: Bool
        var isInteractive: Bool
        var isCompleting: Bool

        init(container: UIView, isPresenting: Bool, from: UIViewController, to: UIViewController, isInteractive: Bool, store: any EventStore<Event>) {
            self.container = container
            self.isPresenting = isPresenting
            self.from = from
            self.to = to
            self.store = store
            self.isInteractive = isInteractive
            self.isCompleting = true
        }

        func completeTransition(_ didComplete: Bool) {
            store.send(didComplete ? .didCompleteTransition(self) : .didCancelTransition(self))
        }

        func beginInteractiveTransition() {
            isInteractive = true
        }

        func endInteractiveTransition(_ isCompleting: Bool) {
            isInteractive = false
            self.isCompleting = isCompleting
        }
    }

    enum Action {
        case none
        case run(() -> ())
    }

    lazy var store = Store(target: self)

    var state: State

    public var viewControllers: [UIViewController] {
        state.viewControllers
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
            let source = state.viewControllers
            let target = navigationAction.target(from: source)
            guard target != source, let to = target.last, let from = source.last else { return .none }
            guard from != to else {
                state.children = target
                return .none
            }
            let isPresenting = target.count > source.count
            let foreground = isPresenting ? to : from
            let background = isPresenting ? from : to
            let transition: Transition = foreground.findObjectMatchType(TransitionProvider.self)?.transitionFor(presenting: isPresenting, otherViewController: background) ?? PushTransition()

            if let transitionState = state.transitions.first(where: { $0.transition === transition }) {
                // the transition is already running
                if transitionState.target == source, transitionState.source == target {
                    // reverse the transition
                    transitionState.transition.reverse()
                }
                // otherwise just ignore
                return .none
            }

            guard state.transitions.isEmpty || state.transitions.allSatisfy({ $0.transition.canTransitionSimutanously(with: transition) && transition.canTransitionSimutanously(with: $0.transition) }) else {
                // can't transition simutanously
                state.nextAction = navigationAction
                return .none
            }

            let isInteractiveStart = transition.wantsInteractiveStart
            let context = NavigationTransitionContext(container: view, isPresenting: isPresenting, from: from, to: to, isInteractive: isInteractiveStart, store: store)
            let transitionState = State.TransitionState(context: context, transition: transition, source: source, target: target)
            state.transitions.append(transitionState)

            return .run {
                from.beginAppearanceTransition(false, animated: true)
                to.beginAppearanceTransition(true, animated: true)

                from.willMove(toParent: nil)
                self.addChild(to)
                transition.animateTransition(context: context)
            }
        case .didCompleteTransition(let context):
            guard let index = state.transitions.firstIndex(where: { $0.context.id == context.id }) else { return .none }
            let transitionState = state.transitions.remove(at: index)
            state.children = transitionState.target
            let nextAction = state.nextAction
            state.nextAction = nil
            return .run {
                self.view.setNeedsLayout()
                if let source = transitionState.source.last {
                    source.removeFromParent()
                    source.endAppearanceTransition()
                }
                if let target = transitionState.target.last {
                    target.didMove(toParent: self)
                    target.endAppearanceTransition()
                }
                if let nextAction {
                    self.store.send(.navigate(nextAction))
                }
            }
        case .didCancelTransition(let context):
            guard let index = state.transitions.firstIndex(where: { $0.context.id == context.id }) else { return .none }
            let transitionState = state.transitions.remove(at: index)
            state.children = transitionState.source
            let nextAction = state.nextAction
            state.nextAction = nil
            return .run {
                self.view.setNeedsLayout()
                if let target = transitionState.target.last {
                    target.beginAppearanceTransition(false, animated: false)
                    target.removeFromParent()
                    target.endAppearanceTransition()
                }
                if let source = transitionState.source.last {
                    source.didMove(toParent: self)
                    source.endAppearanceTransition()
                }
                if let nextAction {
                    self.store.send(.navigate(nextAction))
                }
            }
        }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for subview in view.subviews {
            subview.frameWithoutTransform = view.bounds
        }
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
