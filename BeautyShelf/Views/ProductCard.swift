import SwiftUI

/// 架子上的一个瓶子：瓶子本身 + 下方两行文字。没有卡片背景、没有统一阴影。
struct ProductCard: View {
    let product: Product
    var ns: Namespace.ID

    var body: some View {
        VStack(spacing: 8) {
            LiquidBottle(level: product.level, tint: product.tint)
                .frame(width: 64, height: 104)
                .matchedGeometryEffect(id: "bottle-\(product.id)", in: ns)
                .overlay(alignment: .topTrailing) { expiryDot }
            VStack(spacing: 1) {
                Text(product.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(product.brand)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(product.expiryText)
    }

    @ViewBuilder private var expiryDot: some View {
        if product.expiryState != .fresh {
            Circle().fill(product.expiryState.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Theme.porcelain, lineWidth: 2))
                .offset(x: 6, y: -2)
        }
    }
}
