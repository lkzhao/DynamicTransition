//
//  ComponentRootView.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 5/25/24.
//

class ComponentRootView: UIView, RootViewType {
    let componentView = ComponentScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        viewDidLoad()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func viewDidLoad() {
        backgroundColor = .systemBackground
        componentView.contentInsetAdjustmentBehavior = .always
        addSubview(componentView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        componentView.frame = bounds
    }


    // MARK: - RootViewType
    /// Conforming to RootViewType is optional, but it allows you to receive lifecycle events and customize status bar style

    func willAppear(animated: Bool) {

    }

    func didAppear(animated: Bool) {

    }

    func willDisappear(animated: Bool) {

    }

    func didDisappear(animated: Bool) {

    }

    var preferredStatusBarStyle: UIStatusBarStyle {
        .default
    }
}

