import SwiftUI

/// 产品的"实物"形象：有抠图就显示抠图（透明底 PNG），否则用容器插画 ContainerView。
/// 今日托盘、空瓶记分享图都用它。
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
