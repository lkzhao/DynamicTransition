//
//  NavigationView.swift
//
//  Created by Luke Zhao on 10/6/23.
//

import UIKit
import BaseToolbox

enum NavigationEvent {
    enum NavigationAction {
        case push(UIViewController)
        case dismiss(UIViewController)
        case pop
        case set([UIViewController])

        func target(from source: [UIViewController]) -> [UIViewController] {
            switch self {
            case .push(let vc):
                return source + [vc]
            case .dismiss(let vc):
                guard let index = source.firstIndex(of: vc) else { return source }
                return source[0..<max(1, index)].array
            case .pop:
                return source[0..<max(1, source.count - 1)].array
            case .set(let vcs):
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
    var store: any EventStore<NavigationEvent>

    var isPresenting: Bool
    var isInteractive: Bool = false

    init(container: UIView, isPresenting: Bool, from: UIViewController, to: UIViewController, store: any EventStore<NavigationEvent>) {
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

open class NavigationController: UIViewController, SimpleStoreReceiver {
    struct State {
        struct TransitionState {
            var context: NavigationTransitionContext
            var transition: Transition
            var source: [UIViewController]
            var target: [UIViewController]
        }
        var children: [UIViewController]
        var transition: TransitionState?
        var nextAction: NavigationEvent.NavigationAction?
    }

    lazy var store = SimpleStore(target: self)
    var state: State {
        didSet {
            view.setNeedsLayout()
        }
    }

    public var viewControllers: [UIViewController] {
        return state.transition?.target ?? state.children
    }

    public init(rootViewController: UIViewController) {
        self.state = State(children: [rootViewController])
        super.init(nibName: nil, bundle: nil)
        addVC(state.children.last!)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func receive(_ event: NavigationEvent) {
        let action = process(event: event, state: &state)
        switch action {
        case .run(let block):
            block()
        case .none:
            break
        }
    }

    enum Action {
        case none
        case run(() -> ())
    }

    func process(event: NavigationEvent, state: inout State) -> Action {
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
            let isPush = target.count > source.count
            let foreground = isPush ? to : from
            let background = isPush ? from : to
            let transition: Transition = foreground.findObjectMatchType(TransitionProvider.self)?.transitionFor(presenting: isPush, otherViewController: background) ?? MatchTransition()
            let context = NavigationTransitionContext(container: view, isPresenting: isPush, from: from, to: to, store: store)
            state.transition = State.TransitionState(context: context, transition: transition, source: source, target: target)

            from.beginAppearanceTransition(false, animated: true)
            to.beginAppearanceTransition(true, animated: true)

            from.willMove(toParent: nil)
            addChild(to)
            view.addSubview(to.view)

            return .run {
                transition.animateTransition(context: context)
            }
        case .didCompleteTransition:
            guard let transitionState = state.transition else { return .none }
            state.transition = nil
            state.children = transitionState.target
            let nextAction = state.nextAction
            return .run { [store] in
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

    func addVC(_ vc: UIViewController) {
        guard vc.parent != self else { return }
        addChild(vc)
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
    }

    open func popViewController(animated: Bool) {
        store.send(.navigate(.pop))
    }

    open func popToRootViewController(animated: Bool) {
        guard let vc = viewControllers.first else { return }
        store.send(.navigate(.dismiss(vc)))
    }

    open func push(_ viewController: UIViewController, animated: Bool) {
        store.send(.navigate(.push(viewController)))
    }

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


public protocol TransitionProvider: UIViewController {
    func transitionFor(presenting: Bool, otherViewController: UIViewController) -> Transition?
}
