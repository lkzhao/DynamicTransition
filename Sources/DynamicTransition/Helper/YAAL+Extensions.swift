//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/9/23.
//

import UIKit
import YetAnotherAnimationLibrary

extension Yaal where Base: UIView {
    var frameWithoutTransform: MixAnimation<CGRect> {
        return animationFor(key: "frameWithoutTransform",
                            getter: { [weak base] in base?.frameWithoutTransform },
                            setter: { [weak base] in base?.frameWithoutTransform = $0 })
    }
    var size: MixAnimation<CGSize> {
        return animationFor(key: "size",
                            getter: { [weak base] in base?.bounds.size },
                            setter: { [weak base] in base?.bounds.size = $0 })
    }
    var cornerRadius: MixAnimation<CGFloat> {
        return animationFor(key: "cornerRadius",
                            getter: { [weak base] in base?.cornerRadius },
                            setter: { [weak base] in base?.cornerRadius = $0 })
    }
    var shadowOpacity: MixAnimation<CGFloat> {
        return animationFor(key: "shadowOpacity",
                            getter: { [weak base] in base?.shadowOpacity },
                            setter: { [weak base] in base?.shadowOpacity = $0 })
    }
}

extension MixAnimation {
    func updateTo(value: Value, animated: Bool, stiffness: Double? = nil, damping: Double? = nil, threshold: CGFloat = 0.001, completion: ((Bool) -> ())? = nil) {
        if animated {
            self.animateTo(value, stiffness: stiffness, damping: damping, threshold: threshold, completionHandler: completion)
        } else {
            self.setTo(value)
            completion?(true)
        }
    }
}
