//
//  MultiFlipHomeView.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 9/28/25.
//

import UIComponent

class MultiFlipHomeView: ComponentRootView {
    override func viewDidLoad() {
        super.viewDidLoad()
        componentView.component = VStack(spacing: 20, alignItems: .center) {
            Text("\(type(of: self))", font: .boldSystemFont(ofSize: 18))
            ViewComponent<MultiFlipCardCell>().size(width: 300, height: 200).tappableView {
                $0.navigationController?.pushView(MultiFlipDetailView())
            }
        }.inset(20)
    }

    @objc func didTap() {
        navigationController?.popView(animated: true)
    }
}

class MultiFlipDetailView: ComponentRootView {
    let transition = MultiFlipTransition()

    override func viewDidLoad() {
        super.viewDidLoad()
//        transition.response = 3.0
        backgroundColor = .init(white: 0.95, alpha: 1.0)

        addGestureRecognizer(transition.horizontalDismissGestureRecognizer)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))

        componentView.component =  VStack(spacing: 20, alignItems: .center) {
            Text("\(type(of: self))", font: .boldSystemFont(ofSize: 18))
        }.inset(20)
    }

    @objc func didTap() {
        navigationController?.popView(animated: true)
    }
}

extension MultiFlipDetailView: TransitionProvider {
    func transitionFor(presenting: Bool, otherView: UIView) -> (any Transition)? {
        transition
    }
}

class MultiFlipCardCell: ComponentView {
    override init(frame: CGRect) {
        super.init(frame: .zero)
        component = HStack(spacing: -70) {
            if let image = UIImage(named: "item1") {
                Image(image).size(width: 100, height: 120).cornerRadius(12).clipsToBounds(true).rotation(-0.2).background {
                    SwiftUIComponent {
                        BlurImageShadow(image: image)
                    }.fill()
                }
            }
            if let image = UIImage(named: "item2") {
                Image(image).size(width: 100, height: 120).cornerRadius(12).clipsToBounds(true).tag(1).zPosition(1).background {
                    SwiftUIComponent {
                        BlurImageShadow(image: image)
                    }.fill()
                }
            }
            if let image = UIImage(named: "item4") {
                Image(image).size(width: 100, height: 120).cornerRadius(12).clipsToBounds(true).rotation(0.2).background {
                    SwiftUIComponent {
                        BlurImageShadow(image: image)
                    }.fill()
                }
            }
        }
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension MultiFlipHomeView: MultiFlipTransitionDelegate {
    func multiFlipConfigFor(transition: DynamicTransition.MultiFlipTransition, otherView: UIView) -> DynamicTransition.MultiFlipConfig? {
        let cardCell = componentView.subviewMatching(type: MultiFlipCardCell.self)
        guard let cardCell, let mainView = cardCell.viewWithTag(1) else { return nil }
        return .init(sourceContainerView: cardCell, sourcePrimaryFlipView: mainView)
    }
    
    func multiFlipTransitionWillBegin(transition: DynamicTransition.MultiFlipTransition) {
        
    }
}
