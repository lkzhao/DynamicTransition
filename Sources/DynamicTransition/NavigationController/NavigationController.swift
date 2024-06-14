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
    private struct TransitionState {
        let context: NavigationTransitionContext
        let transition: Transition
        let source: [UIView]
        let target: [UIView]
    }

    private struct State {
        var children: [UIView]
        var transitions: [TransitionState] = []
        var nextAction: (NavigationAction, Bool)?

        var currentViews: [UIView] {
            transitions.last(where: { $0.context.isCompleting })?.target ?? children
        }

        var currentDisplayState: DisplayState {
            let newViews: [UIView] = currentViews
            let newStatusBarStyle = (newViews.last as? RootViewType)?.preferredStatusBarStyle ?? .default
            return DisplayState(views: newViews, preferredStatusBarStyle: newStatusBarStyle)
        }
    }

    private struct DisplayState {
        var views: [UIView]
        var preferredStatusBarStyle: UIStatusBarStyle
    }

    private enum NavigationAction {
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

    private enum Event {
        case navigate(NavigationAction, animated: Bool)
        case didUpdateTransition(NavigationTransitionContext)
    }

    private class NavigationTransitionContext: TransitionContext {
        let id = UUID()
        var container: UIView
        var from: UIView
        var to: UIView

        var isPresenting: Bool
        var isInteractive: Bool
        var isCompleting: Bool
        var isCompleted: Bool

        var onUpdate: (NavigationTransitionContext) -> Void

        init(container: UIView, isPresenting: Bool, from: UIView, to: UIView, isInteractive: Bool, onUpdate: @escaping (NavigationTransitionContext) -> Void) {
            self.container = container
            self.isPresenting = isPresenting
            self.from = from
            self.to = to
            self.onUpdate = onUpdate
            self.isInteractive = isInteractive
            self.isCompleting = true
            self.isCompleted = false
            (from as? RootViewType)?.willDisappear(animated: true)
            (to as? RootViewType)?.willAppear(animated: true)
        }

        func completeTransition() {
            guard !isCompleted else {
                assertionFailure("Transition is already completed")
                return
            }
            isCompleted = true
            if isCompleting {
                (from as? RootViewType)?.didDisappear(animated: true)
                (to as? RootViewType)?.didAppear(animated: true)
            } else {
                (to as? RootViewType)?.didDisappear(animated: true)
                (from as? RootViewType)?.didAppear(animated: true)
            }
            onUpdate(self)
        }

        func beginInteractiveTransition() {
            guard !isCompleted else {
                assertionFailure("Transition is already completed")
                return
            }
            isInteractive = true
        }

        func endInteractiveTransition(_ isCompleting: Bool) {
            guard !isCompleted else {
                assertionFailure("Transition is already completed")
                return
            }
            isInteractive = false
            if isCompleting != self.isCompleting {
                (from as? RootViewType)?.willAppear(animated: true)
                (to as? RootViewType)?.willDisappear(animated: true)
                self.isCompleting = isCompleting
                onUpdate(self)
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
            let source = displayState.views
            let target = navigationAction.target(from: source)
            guard target != source, let to = target.last, let from = source.last else { break }
            guard from != to else {
                // TODO: This might need more work. Will get overriden.
                state.children = target
                break
            }
            let isPresenting = target.count >= source.count
            let transition = animated ? transitionFor(isPresenting: isPresenting, from: from, to: to) : InstantTransition()

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
            let context = NavigationTransitionContext(container: view, isPresenting: isPresenting, from: from, to: to, isInteractive: isInteractiveStart) { [weak self] context in
                self?.process(.didUpdateTransition(context))
            }
            let transitionState = TransitionState(context: context, transition: transition, source: source, target: target)
            state.transitions.append(transitionState)

            runBlock = {
                transition.animateTransition(context: context)
                self.didUpdateViews()
            }
        case .didUpdateTransition(_):
            if state.transitions.allSatisfy({ $0.context.isCompleted }) {
                // all transition completed, cleanup
                let nextAction = state.nextAction
                let children = state.currentViews
                state.transitions = []
                state.children = children
                state.nextAction = nil
                runBlock = {
                    self.didUpdateViews()
                    if let (navigationAction, animated) = nextAction {
                        self.process(.navigate(navigationAction, animated: animated))
                    }
                }
            } else {
                runBlock = {
                    self.didUpdateViews()
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
        displayState = state.currentDisplayState
        view.setNeedsLayout()
//        printState()
    }

    public func updateStatusBarStyle() {
        didUpdateViews()
    }

    public func printState() {
        let views = displayState.views.map {
            "\(type(of: $0))"
        }
        let states = state.transitions.map {
            "\(type(of: $0.transition)): isPresenting=\($0.context.isPresenting) isCompleting=\($0.context.isCompleting) isCompleted=\($0.context.isCompleted)"
        }
        print("""
        --------------------------------
        Transitions:
        \(states.joined(separator: "\n"))

        Views:
        \(views.joined(separator: "\n"))
        --------------------------------
        """)
    }
}
