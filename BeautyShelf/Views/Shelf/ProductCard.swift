import SwiftUI

/// 架子上的一件：容器本身 + 下方两行文字。没有卡片背景、没有统一阴影。
struct ProductCard: View {
    let product: Product
    var ns: Namespace.ID
    var isSource: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            ContainerView(product: product)
                .frame(width: 64, height: 104)
                .matchedGeometryEffect(id: "container-\(product.uid)", in: ns, isSource: isSource)
                .overlay(alignment: .topTrailing) {
                    ExpiryDot(state: product.expiryState).offset(x: 6, y: -2)
                }
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name)，\(product.brand)")
        .accessibilityValue("\(product.remainingText)，\(product.expiryText)")
        .accessibilityHint("轻点查看详情，长按有更多操作")
        .accessibilityAddTraits(.isButton)
    }
}
