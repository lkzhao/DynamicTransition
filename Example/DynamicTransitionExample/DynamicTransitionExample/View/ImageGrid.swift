//
//  ImageGrid.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 5/25/24.
//

struct ImageGrid: ComponentBuilder {
    var onTap: (Int) -> Void
    func build() -> some Component {
        Waterfall(columns: 2, spacing: 10) {
            for i in 1...5 {
                let imageName = "item\(i)"
                let image = UIImage(named: imageName)!
                Image(image)
                    .size(width: .fill, height: .aspectPercentage(image.size.height / image.size.width))
                    .tappableView {
                        onTap(i)
                    }
                    .cornerRadius(16)
                    .cornerCurve(.continuous)
                    .clipsToBounds(true)
                    .id(imageName)
            }
        }
    }
}
