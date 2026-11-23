import SwiftUI
import SwiftData

/// 点开 = 把它从架子上"拿起来"：放大、带一点 3D 倾斜、投影变大变柔，背景压暗成磨砂。
/// iOS 18 由系统缩放转场带过来（ShelfView 的 DetailPresenter），iOS 17 用 matchedGeometryEffect。
/// 实物本身可以按形状操作来记一次使用（见 UseGestureHero），下方保留大按钮"用了一次"。
/// 估算型产品（口红、粉盒）用滑块调整剩余量。
struct ProductDetailView: View {
    @Bindable var product: Product
    var ns: Namespace.ID
    /// iOS 18 全屏缩放转场呈现（不用 matchedGeometryEffect）
    var zoomed: Bool
    var close: () -> Void

    @Environment(AppCoordinator.self) var coordinator
    @Environment(\.modelContext) var context
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// 每记一次（手势或按钮）+1：液面晃动、触感
    @State var uses = 0
    /// 只有按钮触发时 +1：实物自动演示一遍动作
    @State var buttonUses = 0
    @State var revealed = false
    @State var lifted = false
    @State var tilt: Double = 0
    @State var confirmDelete = false

    init(product: Product, ns: Namespace.ID, zoomed: Bool = false, close: @escaping () -> Void) {
        self.product = product
        self.ns = ns
        self.zoomed = zoomed
        self.close = close
    }

    private var heroSize: CGSize {
        product.cutout != nil ? CGSize(width: 230, height: 270) : CGSize(width: 150, height: 244)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
                .opacity(zoomed || revealed ? 1 : 0.0001)
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 22) {
                    hero
                        .padding(.top, 60)

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
                        estimateSlider
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
        .onAppear {
            MotionService.shared.begin()
            withAnimation(.easeOut(duration: 0.25).delay(0.12)) { revealed = true }
            pickUp()
        }
        .onDisappear { MotionService.shared.end() }
        .sensoryFeedback(.impact(weight: .light), trigger: uses)
        .sensoryFeedback(.selection, trigger: estimateStep)
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

    // MARK: 拿起来

    /// 先倾斜得多一点（被拿起的一瞬间），再落定在 2°
    private func pickUp() {
        guard !reduceMotion else {
            lifted = true
            return
        }
        withAnimation(Theme.lift) {
            lifted = true
            tilt = 9
        } completion: {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { tilt = 2 }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            UseGestureHero(product: product, size: heroSize, slosh: uses, demoTrigger: buttonUses) {
                logUse(fromGesture: true)
            }
            .modifier(HeroMatch(id: product.uid, ns: ns, enabled: !zoomed))
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: -0.4, z: 0), anchor: .bottom, perspective: 0.55)
            .background(alignment: .bottom) {
                // 投影：拿起来后变大、变柔、离得更远
                Ellipse()
                    .fill(Color.black.opacity(lifted ? 0.16 : 0.3))
                    .frame(width: heroSize.width * (lifted ? 0.85 : 0.65), height: lifted ? 26 : 8)
                    .blur(radius: lifted ? 16 : 3)
                    .offset(y: lifted ? 30 : 4)
                    .accessibilityHidden(true)
            }
            .scaleEffect(lifted ? 1 : 0.96, anchor: .bottom)

            if !product.isFinished {
                Text(gestureHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
            }
        }
    }

    private var gestureHint: String {
        UseGestureHero.hint(for: product)
    }

    // MARK: 估算剩余

    private var estimateBinding: Binding<Double> {
        Binding(get: { product.level },
                set: { product.setEstimatedLevel($0) })
    }

    /// 每跨过 5% 轻触一下
    private var estimateStep: Int { product.measureMode == .estimate ? Int((product.level * 20).rounded()) : -1 }

    private var estimateSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("估算剩余").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((product.level * 100).rounded()))%")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Slider(value: estimateBinding, in: 0...1, step: 0.05) {
                Text("估算剩余")
            } minimumValueLabel: {
                Image(systemName: "circle.dotted").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "circle.fill").accessibilityHidden(true)
            }
            .tint(product.tint.mixed(with: .black, 0.15))
            .accessibilityValue("约剩 \(Int((product.level * 100).rounded()))%")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

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
        Button { logUse(fromGesture: false) } label: {
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
                    Button(product.isPinned ? "从首页拿下" : "放到首页", systemImage: product.isPinned ? "star.slash" : "star") {
                        product.togglePin()
                        coordinator.dataChanged()
                    }
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

    private func logUse(fromGesture: Bool) {
        guard !product.isFinished else { return }
        withAnimation(Theme.spring) { coordinator.logUse(product) }
        uses += 1
        if !fromGesture { buttonUses += 1 }
        // 用到见底：关闭详情，交给"倒空"动画
        if coordinator.finishing === product {
            close()
        }
    }
}

/// iOS 17 浮层模式：和架子上那件共用 matchedGeometryEffect；iOS 18 缩放转场时关闭
struct HeroMatch: ViewModifier {
    let id: UUID
    let ns: Namespace.ID
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: "container-\(id)", in: ns)
        } else {
            content
        }
    }
}
