//
//  MatchTransitionContainerView.swift
//  
//
//  Created by Luke Zhao on 10/9/23.
//

import UIKit

class MatchTransitionContainerView: UIView {
    let contentView = UIView()

    override var cornerRadius: CGFloat {
        didSet {
            contentView.cornerRadius = cornerRadius
        }
    }

    override var frameWithoutTransform: CGRect {
        didSet {
            recalculateShadowPath()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(contentView)
        cornerCurve = .continuous
        contentView.cornerCurve = .continuous
        contentView.autoresizingMask = []
        contentView.autoresizesSubviews = false
        contentView.clipsToBounds = true
        shadowColor = UIColor(dark: .black, light: .black.withAlphaComponent(0.4))
        shadowRadius = 36
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
    }

    func recalculateShadowPath() {
        shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
    }
}
