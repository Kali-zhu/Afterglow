import SwiftUI
import UIKit

/// 全 App 的玻璃材质：磨砂底 + 一层很淡的液体色晕染 + 一道 1pt 的高光边 + 柔和投影。
///
/// 今日的手记卡、藏品总览、空瓶统计都用它。玻璃在这里不是装饰，
/// 而是把"妆台"这个主题一路延伸下去：物件站在玻璃架上，信息也装在玻璃里。
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    /// 液体色：让这张卡靠近"它讲的这件产品"的颜色
    var tint: Color? = nil
    /// 更厚的一层（背后没有太多内容时用），默认 ultraThin
    var strong: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        return content.background {
            shape
                .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
                                         : AnyShapeStyle(strong ? Material.regular : Material.ultraThin))
                .overlay {
                    if let tint {
                        shape
                            .fill(LinearGradient(colors: [tint.opacity(dark ? 0.24 : 0.17),
                                                          tint.opacity(0.015)],
                                                 startPoint: .topTrailing, endPoint: .bottomLeading))
                            .blendMode(dark ? .plusLighter : .normal)
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(dark ? 0.22 : 0.85),
                                                Color.white.opacity(dark ? 0.03 : 0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                }
                .clipShape(shape)
                .shadow(color: Color.black.opacity(dark ? 0.45 : 0.06), radius: 16, x: 0, y: 8)
        }
    }
}

extension View {
    /// 玻璃卡片。`tint` 传产品自己的液体色，卡片就会带上一点它的颜色。
    func glassPanel(cornerRadius: CGFloat = 22, tint: Color? = nil, strong: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tint: tint, strong: strong))
    }
}

/// 背景里的几团柔光：颜色取自在用的产品，很淡，只是让背景不是一块死板的白/黑。
struct AmbientGlow: View {
    var colors: [Color] = []

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<min(3, colors.count), id: \.self) { index in
                    Circle()
                        .fill(colors[index])
                        .frame(width: side * 0.85, height: side * 0.85)
                        .blur(radius: 110)
                        .opacity(reduceTransparency ? 0.06 : (scheme == .dark ? 0.20 : 0.14))
                        .offset(x: offsets[index].x * geo.size.width,
                                y: offsets[index].y * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var offsets: [CGPoint] {
        [CGPoint(x: -0.30, y: -0.10), CGPoint(x: 0.34, y: 0.14), CGPoint(x: 0.00, y: 0.58)]
    }
}

/// 玻璃卡里的一组数字：大号圆体数 + 单位 + 一行说明，数字变化时会滚动。
struct StatReadout: View {
    let value: String
    var unit: String? = nil
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
