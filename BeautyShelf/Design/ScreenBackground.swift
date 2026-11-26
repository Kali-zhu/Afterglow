import SwiftUI

/// 全 App 同一面"背景墙"：一层瓷白（浅色 #EEF1F4 / 深色纯黑），
/// 加几团很淡的、来自在用产品液体色的柔光。
///
/// 首页、藏品、空瓶、我的、日常流程、详情页都用它——换页面的时候，
/// 背景不该换一种气质；产品色只是轻轻透出来，不铺成一片。
struct ScreenBackground: View {
    /// 柔光的颜色（一般传几件在用产品的 `tint`）
    var colors: [Color] = []

    /// 取色规则（ROADMAP B10）：最多三团、各自去饱和 60%、太像的只留一团。
    /// 产品多了背景才不会打架，也不会抢东西。
    private var glow: [Color] {
        var out: [Color] = []
        for raw in colors {
            let c = raw.desaturated(0.6)
            if out.contains(where: { isSameHue($0, c) }) { continue }
            out.append(c)
            if out.count == 3 { break }
        }
        return out
    }

    private func isSameHue(_ a: Color, _ b: Color) -> Bool {
        let x = a.rgba, y = b.rgba
        return abs(x.r - y.r) < 0.08 && abs(x.g - y.g) < 0.08 && abs(x.b - y.b) < 0.08
    }

    var body: some View {
        ZStack {
            Theme.porcelain
            if !glow.isEmpty {
                AmbientGlow(colors: glow)
            }
        }
        .ignoresSafeArea()
    }
}
