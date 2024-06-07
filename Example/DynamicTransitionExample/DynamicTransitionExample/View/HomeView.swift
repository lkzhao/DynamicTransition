//
//  HomeView.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 5/25/24.
//

class HomeView: ComponentRootView {
    override func viewDidLoad() {
        super.viewDidLoad()
        componentView.component = VStack(spacing: 20, alignItems: .center) {
            Text("\(type(of: self))", font: .boldSystemFont(ofSize: 18))
            HStack(spacing: 10, alignItems: .center) {
                Text("Push Transition", font: .systemFont(ofSize: 18)).flex()
                Image(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)).tintColor(.label)
            }.inset(h: 20).size(height: 70).tappableView { [unowned self] in
                pushTransition()
            }.borderColor(.separator).borderWidth(1).cornerCurve(.continuous).cornerRadius(16)

            Text("This example is intentionally slow to demo the interactivity during transition", font: .systemFont(ofSize: 18)).textColor(.secondaryLabel).textAlignment(.center)
            ImageGrid()
        }.inset(20)
    }

    func pushTransition() {
        navigationController?.pushView(PushTransitionDetailView(), animated: true)
    }
}

extension HomeView: MatchTransitionDelegate {
    func matchedViewFor(transition: DynamicTransition.MatchTransition, otherView: UIView) -> UIView? {
        guard let otherView = otherView as? MatchTransitionDetailView, let imageName = otherView.imageName else { return nil }
        return componentView.visibleView(id: imageName)
    }

    func matchTransitionWillBegin(transition: DynamicTransition.MatchTransition) {
        // extra animation
    }
}
