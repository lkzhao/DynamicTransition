//
//  MatchTransitionDetailView.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 5/25/24.
//

class MatchTransitionDetailView: ComponentRootView {
    let transition = MatchTransition()

    var imageName: String?
    var image: UIImage? {
        didSet {
            reloadComponent()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        componentView.contentInsetAdjustmentBehavior = .never

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        addGestureRecognizer(transition.horizontalDismissGestureRecognizer)
        addGestureRecognizer(transition.verticalDismissGestureRecognizer)
    }

    func reloadComponent() {
        guard let image else { return }
        componentView.component = VStack(spacing: 20, alignItems: .center) {
            Image(image).id("image").size(width: .fill, height: .aspectPercentage(image.size.height / image.size.width))
            VStack(spacing: 4, alignItems: .center) {
                Text("\(type(of: self))", font: .boldSystemFont(ofSize: 18))
                Text("Tap to go back", font: .systemFont(ofSize: 18)).textColor(.secondaryLabel)
            }
            ImageGrid().inset(h: 20)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        componentView.contentInset = UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: safeAreaInsets.bottom, right: safeAreaInsets.right)
    }

    @objc func didTap() {
        navigationController?.popView(animated: true)
    }

    func matchTransition() {
        navigationController?.pushView(MatchTransitionDetailView(), animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
}

extension MatchTransitionDetailView: TransitionProvider {
    func transitionFor(presenting: Bool, otherView: UIView) -> (any Transition)? {
        transition
    }
}

extension MatchTransitionDetailView: MatchTransitionDelegate {
    func matchedViewFor(transition: DynamicTransition.MatchTransition, otherView: UIView) -> UIView? {
        if transition.context?.foreground == self {
            return componentView.visibleView(id: "image")
        } else if let otherView = otherView as? MatchTransitionDetailView, let imageName = otherView.imageName {
            return componentView.visibleView(id: imageName)
        } else {
            return nil
        }
    }

    func matchedViewInsertionBelowTargetView(transition: DynamicTransition.MatchTransition) -> UIView? {
        nil
    }

    func matchTransitionWillBegin(transition: DynamicTransition.MatchTransition) {
        // extra animation
    }
}