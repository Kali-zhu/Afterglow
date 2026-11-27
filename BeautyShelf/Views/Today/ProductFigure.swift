import SwiftUI

/// 产品的"实物"形象：有抠图就直接用抠图（透明底 PNG）——它们本身就是"贴纸"；
/// 没有抠图时画出容器（有照片则把照片当圆形标签贴在瓶身上）。
/// 今日托盘、首页、挑选页、空瓶记分享图都用它。
struct ProductFigure: View {
    let product: Product
    /// 抠图解码的最长边像素
    var maxPixel: Int = 600
    /// 覆盖液面（空瓶显示 0）
    var level: Double? = nil
    var slosh: Int = 0

    var body: some View {
        if let data = product.cutout,
           let image = SharedStore.thumbnail(data, key: product.uid.uuidString, maxPixel: maxPixel) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            ContainerView(product: product, level: level, slosh: slosh, animated: false)
                .aspectRatio(0.62, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}
