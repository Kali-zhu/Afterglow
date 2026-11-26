import SwiftUI

/// 产品的"实物"形象。
/// 默认是**标签模式**：画出来的容器做底，把抠图 / 照片当一枚圆形标签贴在瓶身上
/// （模板是自己的，图只是贴纸，不涉及把别人的瓶身图整张搬过来）。
/// `wholeCutout: true` 是**实物模式**：整张抠图，只用在详情页大图和倒空动画里。
struct ProductFigure: View {
    let product: Product
    /// 抠图解码的最长边像素
    var maxPixel: Int = 600
    /// 覆盖液面（空瓶显示 0）
    var level: Double? = nil
    var slosh: Int = 0
    var wholeCutout: Bool = false

    var body: some View {
        if wholeCutout, let data = product.cutout,
           let image = SharedStore.thumbnail(data, key: product.uid.uuidString, maxPixel: maxPixel) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            ContainerView(product: product, level: level, slosh: slosh, animated: false, wholeCutout: false)
                .aspectRatio(0.62, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}
