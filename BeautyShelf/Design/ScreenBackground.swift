import SwiftUI

/// 全 App 同一面"背景墙"：一层瓷白（浅色 #EEF1F4 / 深色纯黑），
/// 加几团很淡的、来自在用产品液体色的柔光。
///
/// 首页、藏品、空瓶、我的、日常流程、详情页都用它——换页面的时候，
/// 背景不该换一种气质；产品色只是轻轻透出来，不铺成一片。
struct ScreenBackground: View {
    /// 柔光的颜色（一般传几件在用产品的 `tint`，最多用前三个）
    var colors: [Color] = []

    var body: some View {
        ZStack {
            Theme.porcelain
            if !colors.isEmpty {
                AmbientGlow(colors: colors)
            }
        }
        .ignoresSafeArea()
    }
}
