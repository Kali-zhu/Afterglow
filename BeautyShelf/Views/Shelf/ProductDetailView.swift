import SwiftUI
import SwiftData

/// 点开容器：容器从架子上放大到中央（matchedGeometryEffect），
/// 下方是数据、日期、最近 14 天使用点阵，以及唯一的主操作"用了一次"。
/// 估算型产品（口红、粉盒）可以直接用手指拖动液面设置剩余量。
struct ProductDetailView: View {
    @Bindable var product: Product
    var ns: Namespace.ID
    var close: () -> Void

    @Environment(AppCoordinator.self) var coordinator
    @Environment(\.modelContext) var context
    @State var uses = 0
    @State var revealed = false
    @State var dragLevel: Double? = nil
    @State var confirmDelete = false

    let containerSize = CGSize(width: 150, height: 244)

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 22) {
                    container
                        .padding(.top, 56)

                    VStack(spacing: 4) {
                        Text(product.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        if !product.brand.isEmpty {
                            Text(product.brand).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    stats
                    if product.measureMode == .estimate {
                        Label("上下拖动液面，调整估算的剩余量", systemImage: "hand.draw")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    datesCard
                    usageDots
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(revealed ? 1 : 0)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { useButton }

            topBar
        }
        .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.12)) { revealed = true } }
        .sensoryFeedback(.impact(weight: .light), trigger: uses)
        .sensoryFeedback(.selection, trigger: dragStep)
        .confirmationDialog("删除「\(product.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                let p = product
                close()
                withAnimation(Theme.spring) { context.delete(p) }
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    // MARK: 容器 + 拖动液面

    private var container: some View {
        ZStack(alignment: .top) {
            ContainerView(product: product, level: dragLevel, slosh: uses)
                .frame(width: containerSize.width, height: containerSize.height)
                .matchedGeometryEffect(id: "container-\(product.uid)", in: ns)
                .contentShape(Rectangle())
                .gesture(levelDrag, including: product.measureMode == .estimate ? GestureMask.all : GestureMask.subviews)
                .accessibilityValue(product.remainingText)
                .accessibilityAdjustableAction { direction in
                    guard product.measureMode == .estimate else { return }
                    switch direction {
                    case .increment: product.setEstimatedLevel(product.level + 0.05)
                    case .decrement: product.setEstimatedLevel(product.level - 0.05)
                    @unknown default: break
                    }
                }
            // 记录一次使用时，一滴液体从上方落入容器
            FallingDrop(tint: product.tint, trigger: uses, distance: containerSize.height * 0.55, size: 12)
                .offset(y: -10)
        }
    }

    private var levelDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let rect = ContainerGeometry.make(product.kind, in: CGRect(origin: .zero, size: containerSize)).vesselRect
                guard rect.height > 0 else { return }
                let l = (rect.maxY - value.location.y) / rect.height
                dragLevel = max(0, min(1, Double(l)))
            }
            .onEnded { _ in
                if let l = dragLevel {
                    withAnimation(Theme.spring) { product.setEstimatedLevel(l) }
                }
                dragLevel = nil
            }
    }

    /// 拖动时每跨过 5% 轻触一下
    private var dragStep: Int { dragLevel.map { Int($0 * 20) } ?? -1 }

    // MARK: 数据

    private var stats: some View {
        Grid(horizontalSpacing: 26, verticalSpacing: 4) {
            GridRow {
                stat("\(product.useCount)", "次")
                stat(remainingValue, remainingUnit)
                stat("\(abs(product.daysUntilExpiry))", product.daysUntilExpiry >= 0 ? "天" : "天前",
                     color: product.expiryState == .fresh ? .primary : product.expiryState.color)
            }
            GridRow {
                Text("已使用")
                Text("剩余")
                Text(product.daysUntilExpiry >= 0 ? "后过期" : "已过期")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已使用 \(product.useCount) 次，\(product.remainingText)，\(product.expiryText)")
    }

    private var remainingValue: String {
        if let dragLevel { return "\(Int((dragLevel * 100).rounded()))" }
        switch product.measureMode {
        case .volume: return Fmt.amount(product.remainingAmount)
        case .count: return "\(Int(product.remainingAmount.rounded()))"
        case .estimate: return "\(Int(product.remainingAmount.rounded()))"
        }
    }

    private var remainingUnit: String {
        switch product.measureMode {
        case .volume: return product.unit
        case .count: return "/\(Int(product.totalAmount.rounded())) 片"
        case .estimate: return "%"
        }
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

    // MARK: 日期

    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("开封", product.openedDate.map { Fmt.day($0) } ?? "还没开封（第一次使用时自动记录）")
            Divider()
            row("开封后保质", product.paoMonths.map { "\($0) 个月" } ?? "未填")
            Divider()
            row("包装到期日", Fmt.day(product.expiryDate))
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(product.expiryState.color).frame(width: 8, height: 8)
                Text("会在 \(Fmt.day(product.effectiveExpiry)) 过期（\(product.expiryBasis.text)）")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            if let price = product.price {
                Divider()
                row("价格", product.costPerUse.map { "\(Fmt.money(price)) · 每次 \(Fmt.money($0))" } ?? Fmt.money(price))
            }
            if product.backupStock > 0 {
                Divider()
                row("备用库存", "\(product.backupStock) 件")
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: 最近 14 天

    private var usageDots: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days: [Date] = (0..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let usedCount = days.filter { product.used(on: $0) }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("最近 14 天").font(.subheadline.weight(.semibold))
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    Circle()
                        .fill(product.used(on: day) ? product.tint : Color.primary.opacity(0.08))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(product.used(on: day) ? 0.15 : 0), lineWidth: 1))
                        .frame(width: 14, height: 14)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("14 天前")
                Spacer()
                Text("今天")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 14 天里用了 \(usedCount) 天")
    }

    // MARK: 操作

    private var useButton: some View {
        Button(action: logUse) {
            Text("用了一次")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .foregroundStyle(Color(uiColor: .systemBackground))
        .disabled(product.isFinished)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .opacity(revealed ? 1 : 0)
    }

    private var topBar: some View {
        VStack {
            HStack {
                Menu {
                    Button("编辑", systemImage: "pencil") { coordinator.editor = .edit(product) }
                    Button(product.needsRestock ? "移出补货清单" : "加入补货清单", systemImage: "cart") {
                        product.needsRestock.toggle()
                    }
                    Button("用完了", systemImage: "checkmark.circle") {
                        let p = product
                        close()
                        coordinator.finish(p)
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("更多操作")

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("关闭")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func logUse() {
        withAnimation(Theme.spring) { coordinator.logUse(product) }
        uses += 1
        // 用到见底：关闭详情，交给"倒空"动画
        if coordinator.finishing === product {
            close()
        }
    }
}
