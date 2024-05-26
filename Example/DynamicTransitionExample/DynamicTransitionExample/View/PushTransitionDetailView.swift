//
//  PushTransitionDetailView.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 5/25/24.
//

class PushTransitionDetailView: ComponentRootView {
    let transition = PushTransition()

    override func viewDidLoad() {
        super.viewDidLoad()
        componentView.component = VStack(spacing: 10, alignItems: .center) {
            Text("\(type(of: self))", font: .boldSystemFont(ofSize: 18))
            HStack(spacing: 10, alignItems: .center) {
                Text("Push Another", font: .systemFont(ofSize: 18)).flex()
                Image(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)).tintColor(.label)
            }.inset(h: 20).size(height: 70).tappableView { [unowned self] in
                pushTransition()
            }.borderColor(.separator).borderWidth(1).cornerCurve(.continuous).cornerRadius(16)

            Spacer()
            Text("Tap anywhere to go back", font: .systemFont(ofSize: 18)).textColor(.secondaryLabel)
        }.inset(20)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        addGestureRecognizer(transition.horizontalDismissGestureRecognizer)
    }

    @objc func didTap() {
        navigationController?.popView(animated: true)
    }

    func pushTransition() {
        navigationController?.pushView(PushTransitionDetailView(), animated: true)
    }
}

extension PushTransitionDetailView: TransitionProvider {
    func transitionFor(presenting: Bool, otherView: UIView) -> (any Transition)? {
        transition
    }
}
