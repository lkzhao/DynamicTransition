//
//  ViewController.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 10/7/23.
//

import UIKit
import UIComponent
import Kingfisher
import DynamicTransition

class ComponentViewController: UIViewController {
    let componentView = ComponentScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(componentView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        componentView.frame = view.bounds
    }
}

class HomeViewController: ComponentViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        componentView.component = Waterfall(columns: 2, spacing: 1) {
            for image in ImageData.testImages {
                ViewComponent<ImageView>().imageData(image)
                    .size(width: .fill, height: .aspectPercentage(image.size.height / image.size.width))
                    .onTap { [unowned self] _ in
                        self.didTap(image: image)
                    }
            }
        }
    }

    func didTap(image: ImageData) {
        UIImpactFeedbackGenerator().impactOccurred(intensity: 0.5)
        let detailVC = CloseupViewController()
        detailVC.image = image
        parentNavigationController?.push(detailVC, animated: true)
    }
}

extension HomeViewController: MatchTransitionDelegate {
    func matchedViewFor(transition: TransitionContext, otherViewController: UIViewController) -> UIView? {
        guard let closeupVC = otherViewController as? CloseupViewController else { return nil }
        return componentView.findSubview { view in
            (view as? ImageView)?.imageData?.id == closeupVC.image.id
        }
    }
}

class CloseupViewController: ComponentViewController {
    let transition = MatchTransition()
    let imageView = ImageView()
    var image: ImageData! {
        didSet {
            imageView.imageData = image
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        componentView.clipsToBounds = false
        componentView.contentInsetAdjustmentBehavior = .never
        transition.options.onDragStart = { _ in
            UIImpactFeedbackGenerator().impactOccurred(intensity: 0.5)
        }
//        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapBG)))
        view.addGestureRecognizer(transition.verticalDismissGestureRecognizer)
        view.addGestureRecognizer(transition.horizontalDismissGestureRecognizer)
        componentView.component = VStack(spacing: 1) {
            imageView
                .size(width: .fill, height: .aspectPercentage(image.size.height / image.size.width))
            Waterfall(columns: 2, spacing: 1) {
                for image in ImageData.testImages {
                    ViewComponent<ImageView>().imageData(image)
                        .size(width: .fill, height: .aspectPercentage(image.size.height / image.size.width))
                        .onTap { [unowned self] _ in
                            self.didTap(image: image)
                        }
                }
            }
        }
    }
    @objc func didTapBG() {
        parentNavigationController?.popViewController(animated: true)
    }

    func didTap(image: ImageData) {
        UIImpactFeedbackGenerator().impactOccurred(intensity: 0.5)
        let detailVC = CloseupViewController()
        detailVC.image = image
        parentNavigationController?.push(detailVC, animated: true)
    }
}

extension CloseupViewController: TransitionProvider {
    func transitionFor(presenting: Bool, otherViewController: UIViewController) -> Transition? {
        transition
    }
}

class ImageView: TappableView {
    let imageView = UIImageView()
    var imageData: ImageData? {
        didSet {
            guard let imageData, imageData != oldValue else { return }
            imageView.kf.setImage(with: imageData.url)
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        component = imageView.fill()
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func snapshotView(afterScreenUpdates afterUpdates: Bool) -> UIView? {
        let view = UIImageView(frame: frame)
        view.image = imageView.image
        return view
    }
}

extension CloseupViewController: MatchTransitionDelegate {
    func matchedViewFor(transition: TransitionContext, otherViewController: UIViewController) -> UIView? {
        if let otherViewController = otherViewController as? CloseupViewController, transition.background == self {
            return componentView.findSubview { view in
                view != self.imageView && (view as? ImageView)?.imageData?.id == otherViewController.image.id
            }
        } else {
            return imageView
        }
    }
}
