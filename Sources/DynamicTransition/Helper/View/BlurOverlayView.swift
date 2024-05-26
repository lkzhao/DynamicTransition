//
//  BlurOverlayView.swift
//
//  Created by Luke Zhao on 11/2/23.
//

import UIKit
import BaseToolbox

class BlurOverlayView: UIView {
    let effectView = UIVisualEffectView(effect: nil)
    let animator = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut)
    let overlayView = UIView().then {
        $0.backgroundColor = UIColor.systemBackground
    }
    var progress: CGFloat = 0.0 {
        didSet {
            let progress = progress.clamp(0.0, 1.0)
            animator.fractionComplete = progress * 0.5
            overlayView.alpha = progress
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        animator.addAnimations {
            self.effectView.effect = UIBlurEffect(style: .systemChromeMaterial)
        }
        animator.startAnimation()
        animator.pauseAnimation()
        addSubview(effectView)
        addSubview(overlayView)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            animator.stopAnimation(true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frameWithoutTransform = bounds
        overlayView.frameWithoutTransform = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
