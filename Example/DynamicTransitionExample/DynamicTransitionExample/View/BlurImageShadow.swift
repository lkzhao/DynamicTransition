//
//  BlurImageShadow.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 9/28/25.
//

import SwiftUI

struct BlurImageShadow: View {
    let image: UIImage
    var body: some View {
        Image(uiImage: image).resizable().blur(radius: 30).opacity(0.5).offset(y: 10)
    }
}
