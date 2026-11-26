import SwiftUI

/// 架子上的一件：实物（抠图或插画）站在玻璃架板上 + 下方一行名字。
/// - 高度按 `shelfScale` 真实比例（15 ml 和 200 ml 高低错落），底边对齐架板
/// - 接触阴影；透明有色玻璃在架板上投下彩色焦散光
/// - 只在快到期 / 已过期 / 剩余不多时，名字前出现一个小圆点
/// 架板本身由 ShelfView 画在整行后面，卡片在 `stageHeight` 处留出架板的位置。
struct ProductCard: View {
    let product: Product
    /// 详情盖在上面时暂停液面动画
    var live: Bool = true
    /// 物件区域的高度（最高的物件 = shelfScale 1.0）
    var stageHeight: CGFloat = ProductCard.defaultStageHeight

    static let defaultStageHeight: CGFloat = 118
    /// 插画的宽高比（与详情页 150×244 一致）
    static let illustrationAspect: CGFloat = 150.0 / 244.0

    private var itemHeight: CGFloat { (stageHeight - 6) * CGFloat(product.shelfScale) }
    /// 标签模式下架子上永远是"画出来的容器 + 贴纸"，高度按插画的比例
    private var itemWidth: CGFloat { itemHeight * Self.illustrationAspect }

    var body: some View {
        VStack(spacing: 0) {
            stage
                .frame(height: stageHeight, alignment: .bottom)
            // 架板的位置（ShelfView 在整行后面画）
            Color.clear.frame(height: ShelfPlank.height - ShelfPlank.surface + 2)
            nameLine
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(product.brand.isEmpty ? product.name : "\(product.name)，\(product.brand)")
        .accessibilityValue(spokenValue)
        .accessibilityHint("轻点拿起来看详情，长按有更多操作")
        .accessibilityAddTraits(.isButton)
    }

    private var stage: some View {
        let width = itemWidth
        let shadowWidth = width * 0.92
        return ZStack(alignment: .bottom) {
            if product.kind == .bottle || product.kind == .jar,
               product.finish == .clear || product.finish == .frosted, product.level > 0.02 {
                CausticGlow(tint: product.tint, width: shadowWidth,
                            strength: (product.finish == .clear ? 1 : 0.5) * min(1, 0.4 + product.level))
                    .offset(y: ShelfPlank.surface + 2)
            }
            ContactShadow(width: shadowWidth)
                .offset(y: 2)
            ContainerView(product: product, animated: live)
                .frame(width: width, height: itemHeight)
                .frame(maxWidth: .infinity)
                .modifier(DetailTransitionSource(id: product.uid))
        }
        // 物件底边落在架板顶面的中间
        .offset(y: ShelfPlank.surface * 0.6)
    }

    private var nameLine: some View {
        HStack(spacing: 4) {
            if let status = ShelfStatus.of(product) {
                StatusDot(status: status)
            }
            Text(product.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    private var spokenValue: String {
        var parts = [product.remainingText, product.expiryText]
        if let s = ShelfStatus.of(product), s == .low { parts.append(s.spoken) }
        return parts.joined(separator: "，")
    }
}

/// 拿起来的源头：iOS 18 用导航缩放转场的源；iOS 17 用 matchedGeometryEffect
struct LiftSource: ViewModifier {
    let id: UUID
    let ns: Namespace.ID
    var isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content.matchedGeometryEffect(id: "container-\(id)", in: ns, isSource: isSource)
        }
        #else
        content.matchedGeometryEffect(id: "container-\(id)", in: ns, isSource: isSource)
        #endif
    }
}

/// 详情的呈现方式
enum LiftPresentation {
    /// iOS 18 + Xcode 16：全屏 + 系统缩放转场；否则浮层 + matchedGeometryEffect
    static var usesZoom: Bool {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) { return true }
        #endif
        return false
    }
}
