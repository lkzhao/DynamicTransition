//
//  PageFlipDetailView.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 9/28/25.
//

class PageFlipDetailView: ComponentRootView {
    let transition = PageFlipTransition()

    var imageIndex: Int? {
        didSet {
            reloadComponent()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        transition.response = 3.0

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        addGestureRecognizer(transition.horizontalDismissGestureRecognizer)

        reloadComponent()
    }

    func reloadComponent() {
        componentView.component = VStack(spacing: 20, alignItems: .center) {
            if let imageIndex, let image = UIImage(named: "item\(imageIndex)") {
                Image(image).id("image").size(width: .fill, height: .aspectPercentage(image.size.height / image.size.width))
            }
            VStack(spacing: 4, alignItems: .center) {
                Text("\(type(of: self))", font: .boldSystemFont(ofSize: 18))
                Text("Tap to go back", font: .systemFont(ofSize: 18)).textColor(.secondaryLabel)
            }
            ImageGrid { [weak self] in
                let view = PageFlipDetailView()
                view.imageIndex = $0
                self?.navigationController?.pushView(view, animated: true)
            }.inset(h: 20)
        }
    }

    @objc func didTap() {
        navigationController?.popView(animated: true)
    }
}

extension PageFlipDetailView: TransitionProvider {
    func transitionFor(presenting: Bool, otherView: UIView) -> (any Transition)? {
        transition
    }
}

extension PageFlipDetailView: PageFlipTransitionDelegate {
    func pageFlipTransitionWillBegin(transition: DynamicTransition.PageFlipTransition) {
    }
    
    func matchedViewFor(transition: DynamicTransition.PageFlipTransition, otherView: UIView) -> UIView? {
        if transition.context?.foreground == self {
            return componentView.visibleView(id: "image")
        } else if let otherView = otherView as? PageFlipDetailView, let imageIndex = otherView.imageIndex {
            return componentView.visibleView(id: "item\(imageIndex)")
        } else {
            return nil
        }
    }
}
