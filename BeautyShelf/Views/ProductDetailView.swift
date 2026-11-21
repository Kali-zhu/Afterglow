import SwiftUI

/// 点开瓶子：瓶子从架子上放大到中央（matchedGeometryEffect），
/// 下方是数据和唯一的主操作"用了一次"。
struct ProductDetailView: View {
    @Bindable var product: Product
    var ns: Namespace.ID
    var close: () -> Void
    @State private var uses = 0
    @State private var revealed = false
    @State private var dropFalling = false

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("关闭")

            VStack(spacing: 24) {
                Spacer()
                ZStack(alignment: .top) {
                    LiquidBottle(level: product.level, tint: product.tint, slosh: uses)
                        .frame(width: 150, height: 244)
                        .matchedGeometryEffect(id: "bottle-\(product.id)", in: ns)
                    // 记录一次使用时，一滴液体从瓶口滴落
                    Circle().fill(product.tint)
                        .frame(width: 12, height: 12)
                        .offset(y: dropFalling ? 300 : 30)
                        .opacity(dropFalling ? 0 : (uses > 0 ? 1 : 0))
                }

                VStack(spacing: 4) {
                    Text(product.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text(product.brand).font(.subheadline).foregroundStyle(.secondary)
                }

                Grid(horizontalSpacing: 28) {
                    GridRow {
                        stat("\(product.useCount)", "次")
                        stat(amountText, product.unit)
                        stat("\(abs(product.daysUntilExpiry))", product.daysUntilExpiry >= 0 ? "天后过期" : "天前已过期",
                             color: product.expiryState == .fresh ? .primary : product.expiryState.color)
                    }
                    GridRow {
                        Text("已使用").gridCellColumns(1)
                        Text("剩余")
                        Text(product.expiryDate.formatted(.dateTime.year().month().day()))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: logUse) {
                    Text(product.remainingAmount > 0 ? "用了一次" : "已经用完")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .disabled(product.remainingAmount <= 0)
                .sensoryFeedback(.impact(weight: .light), trigger: uses)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
            .opacity(revealed ? 1 : 0)

            VStack {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("关闭")
                }
                Spacer()
            }
            .padding(20)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.12)) { revealed = true } }
    }

    private var amountText: String {
        product.remainingAmount.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(product.remainingAmount))" : String(format: "%.1f", product.remainingAmount)
    }

    private func logUse() {
        dropFalling = false
        withAnimation(Theme.spring) { product.logUse(); uses += 1 }
        withAnimation(.easeIn(duration: 0.45)) { dropFalling = true }
    }

    private func stat(_ value: String, _ unit: String, color: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(color)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}
