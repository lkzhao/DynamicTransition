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

            Text("This example is intentionally slow to demo the interactivity during transition", font: .systemFont(ofSize: 18)).textColor(.secondaryLabel).textAlignment(.center)

            VStack(spacing: 8) {
                HStack(spacing: 10, alignItems: .center) {
                    Text("Push Transition", font: .systemFont(ofSize: 18)).flex()
                    Image(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)).tintColor(.label)
                }.inset(h: 20).size(height: 70).tappableView { [unowned self] in
                    navigationController?.pushView(PushTransitionDetailView(), animated: true)
                }.borderColor(.separator).borderWidth(1).cornerCurve(.continuous).cornerRadius(16)

                HStack(spacing: 10, alignItems: .center) {
                    Text("Match Transition", font: .systemFont(ofSize: 18)).flex()
                    Image(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)).tintColor(.label)
                }.inset(h: 20).size(height: 70).tappableView { [unowned self] in
                    navigationController?.pushView(MatchTransitionDetailView(), animated: true)
                }.borderColor(.separator).borderWidth(1).cornerCurve(.continuous).cornerRadius(16)

                HStack(spacing: 10, alignItems: .center) {
                    Text("Page Flip Transition", font: .systemFont(ofSize: 18)).flex()
                    Image(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)).tintColor(.label)
                }.inset(h: 20).size(height: 70).tappableView { [unowned self] in
                    navigationController?.pushView(PageFlipDetailView(), animated: true)
                }.borderColor(.separator).borderWidth(1).cornerCurve(.continuous).cornerRadius(16)

                HStack(spacing: 10, alignItems: .center) {
                    Text("Multi Flip Transition", font: .systemFont(ofSize: 18)).flex()
                    Image(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)).tintColor(.label)
                }.inset(h: 20).size(height: 70).tappableView { [unowned self] in
                    navigationController?.pushView(MultiFlipHomeView(), animated: true)
                }.borderColor(.separator).borderWidth(1).cornerCurve(.continuous).cornerRadius(16)
            }
        }.inset(20)
    }
}
