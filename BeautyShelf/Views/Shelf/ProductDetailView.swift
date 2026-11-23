import SwiftUI
import SwiftData

/// 点开 = 把它从架子上"拿起来"：放大、带一点 3D 倾斜、投影变大变柔，背景压暗成磨砂。
/// 这是全 App 唯一的"使用页"：首页、藏品、空瓶、近期记录点任何一件产品都打开它。
/// iOS 18 由 ProductDetailPresenter 的系统缩放转场带过来，iOS 17 用 matchedGeometryEffect。
/// 实物本身可以按形状操作来记一次使用（见 UseGestureHero），下方保留大按钮"用了一次"。
/// 估算型产品（口红、粉盒）用滑块调整剩余量。
struct ProductDetailView: View {
    @Bindable var product: Product
    /// iOS 17 的 matchedGeometryEffect 用；iOS 18 走系统缩放转场，这里可以为 nil
    var ns: Namespace.ID? = nil
    /// iOS 18 全屏缩放转场呈现（不用 matchedGeometryEffect）
    var zoomed: Bool = false
    var close: () -> Void

    @Environment(AppCoordinator.self) var coordinator
    @Environment(\.modelContext) var context
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var scheme
    /// 每记一次（手势或按钮）+1：液面晃动、触感
    @State var uses = 0
    /// 只有按钮触发时 +1：实物自动演示一遍动作
    @State var buttonUses = 0
    @State var revealed = false
    @State var lifted = false
    @State var tilt: Double = 0
    @State var confirmDelete = false
    /// 这一次记给哪个时段：默认当前时段（15:00 前早间，之后晚间）
    @State var slot: RoutineSlot = SharedStore.currentSlot()
    /// 刚记下：按钮短暂变成"已记下"，并给出撤销
    @State var recorded = false
    @State var resetTask: Task<Void, Never>? = nil

    init(product: Product, ns: Namespace.ID? = nil, zoomed: Bool = false, close: @escaping () -> Void) {
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
            backdrop
                .opacity(zoomed || revealed ? 1 : 0.0001)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 22) {
                    hero
                        .padding(.top, 60)

                    VStack(spacing: 4) {
                        Text(product.name)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        if !product.brand.isEmpty {
                            Text(product.brand).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    stats
                    expiryLine
                    if product.measureMode == .estimate {
                        estimateSlider
                    }
                    usageDots
                    slotToggles
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(revealed ? 1 : 0)
            }
            .scrollIndicators(.hidden)
            // 底部按钮自己一块安全区：不会被 Home Indicator 挡住，也不跟着内容滚走
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background {
                        LinearGradient(colors: [stage.opacity(0), stage.opacity(0.9), stage],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .opacity(revealed ? 1 : 0)
            }

            topBar
        }
        .onAppear {
            MotionService.shared.begin()
            withAnimation(.easeOut(duration: 0.25).delay(0.12)) { revealed = true }
            pickUp()
        }
        .onDisappear {
            MotionService.shared.end()
            resetTask?.cancel()
        }
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
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                stat("\(product.useCount)", "次")
                stat(remainingValue, remainingUnit)
                stat("\(abs(product.daysUntilExpiry))", "天",
                     color: product.expiryState == .fresh ? .primary : product.expiryState.color)
            }
            GridRow {
                Text("已用")
                Text(usesLeftText.map { "还剩 · \($0)" } ?? "还剩")
                Text(product.daysUntilExpiry >= 0 ? "后到期" : "已过期")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
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
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(color)
            Text(unit).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 约还能用几次（按每次用量）
    private var usesLeftText: String? {
        guard product.measureMode == .volume, product.amountPerUse > 0 else { return nil }
        let n = Int((product.remainingAmount / product.amountPerUse).rounded(.down))
        return "约 \(n) 次"
    }

    // MARK: 到期一行（替代原来的日期卡片）

    private var expiryLine: some View {
        var basis: String {
            switch product.expiryBasis {
            case .packaging: return "（包装日期）"
            case .afterOpening(let m): return "（开封后 \(m) 个月）"
            }
        }
        let extra = [product.price.map { p in product.costPerUse.map { "每次 \(Fmt.money($0))" } ?? Fmt.money(p) },
                     product.backupStock > 0 ? "备用 \(product.backupStock) 件" : nil].compactMap { $0 }
        return VStack(spacing: 4) {
            Text("\(Fmt.day(product.effectiveExpiry).replacingOccurrences(of: " ", with: "")) 到期\(basis)")
                .foregroundStyle(product.expiryState == .fresh ? Color.secondary : product.expiryState.color)
            if !extra.isEmpty {
                Text(extra.joined(separator: " · ")).foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: 日常流程

    private var slotToggles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(RoutineSlot.allCases) { slot in routineToggle(slot) }
            }
            VStack(spacing: 8) {
                ForEach(RoutineSlot.allCases) { slot in routineToggle(slot) }
            }
        }
        .padding(.top, 4)
    }

    private func routineToggle(_ slot: RoutineSlot) -> some View {
        let on = self.slot == slot
        return Button {
            withAnimation(Theme.snappy) { self.slot = slot }
        } label: {
            Label(slot.title, systemImage: slot.symbol)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .foregroundStyle(on ? inkReverse : Color.primary.opacity(0.85))
                .background(Capsule().fill(on ? ink : soft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("这一次记给\(slot.title)")
        .accessibilityValue(on ? "已选中" : "未选中")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 配色：白天瓷白、夜间近黑，跟随系统

    private var dark: Bool { scheme == .dark }
    private var stage: Color { dark ? Color(hex: "0E0F12") : Color(hex: "F6F6F7") }
    /// 主色：夜间白、白天黑
    private var ink: Color { dark ? Color.white.opacity(0.95) : Color(hex: "1C1C1E") }
    private var inkReverse: Color { dark ? .black : .white }
    private var soft: Color { Color.primary.opacity(dark ? 0.1 : 0.07) }

    // MARK: 背景：产品色的柔光

    private var backdrop: some View {
        ZStack {
            stage
            RadialGradient(colors: [product.tint.opacity(dark ? 0.22 : 0.16), .clear], center: UnitPoint(x: 0.15, y: 0.28), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [product.tint.opacity(dark ? 0.14 : 0.1), .clear], center: UnitPoint(x: 0.85, y: 0.48), startRadius: 0, endRadius: 240)
            RadialGradient(colors: [Color.white.opacity(dark ? 0.06 : 0.7), .clear], center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
    }

    // MARK: 最近 14 天

    private var usageDots: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days: [Date] = (0..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let usedCount = days.filter { product.used(on: $0) }.count
        return VStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(days, id: \.self) { day in
                    Circle()
                        .fill(product.used(on: day) ? ink : Color.primary.opacity(0.12))
                        .frame(width: 10, height: 10)
                }
            }
            Text("最近 14 天").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 14 天里用了 \(usedCount) 天")
    }

    // MARK: 操作

    private var actions: some View {
        VStack(spacing: 10) {
            if recorded {
                HStack(spacing: 10) {
                    Label("已记一次 · \(slot.title)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button { undoLast() } label: {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
            Button { logUse(fromGesture: false) } label: {
                HStack(spacing: 8) {
                    if recorded { Image(systemName: "checkmark") }
                    Text(recorded ? "已记下" : "用了一次")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(inkReverse)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(ink))
            }
            .buttonStyle(ShelfPressStyle())
            .disabled(product.isFinished)
            HStack(spacing: 12) {
                darkPill("用完了") {
                    let p = product
                    close()
                    coordinator.finish(p)
                }
                darkPill(product.needsRestock ? "已在补货" : "加入补货") {
                    withAnimation(Theme.snappy) { product.needsRestock.toggle() }
                }
            }
            .disabled(product.isFinished)
        }
    }

    private func darkPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(soft))
        }
        .buttonStyle(ShelfPressStyle())
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(soft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")

                Spacer()

                Menu {
                    Button(product.isPinned ? "取消常用" : "标为常用", systemImage: product.isPinned ? "star.slash" : "star") {
                        product.togglePin()
                        coordinator.dataChanged()
                    }
                    Menu("日常流程") {
                        ForEach(RoutineSlot.allCases) { s in
                            Button {
                                withAnimation(Theme.snappy) { product.setRoutine(s, !product.inRoutine(s)) }
                                coordinator.dataChanged()
                            } label: {
                                Label(product.inRoutine(s) ? "移出\(s.title)" : "加入\(s.title)",
                                      systemImage: product.inRoutine(s) ? "checkmark" : s.symbol)
                            }
                        }
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: product.isPinned ? "star.fill" : "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(product.isPinned ? Theme.honey : .primary)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(soft))
                }
                .accessibilityLabel("更多操作")

                Button { coordinator.editor = .edit(product) } label: {
                    Text("编辑")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .frame(height: 50)
                        .background(Capsule().fill(soft))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func logUse(fromGesture: Bool) {
        guard !product.isFinished else { return }
        // 记一次，并标明属于哪个时段（胶囊默认当前时段）
        withAnimation(Theme.spring) { coordinator.logRoutine(product, slot) }
        uses += 1
        if !fromGesture { buttonUses += 1 }
        markRecorded()
        // 用到见底：关闭详情，交给"倒空"动画
        if coordinator.finishing === product {
            close()
        }
    }

    /// 按钮短暂变成"已记下"，并给出撤销；不自动关闭，让用户看到数字和圆点的变化
    private func markRecorded() {
        withAnimation(Theme.snappy) { recorded = true }
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.snappy) { recorded = false }
        }
    }

    private func undoLast() {
        resetTask?.cancel()
        withAnimation(Theme.spring) {
            coordinator.undoRoutine(product, slot)
            recorded = false
        }
    }
}

/// iOS 17 浮层模式：和架子上那件共用 matchedGeometryEffect；iOS 18 缩放转场时关闭
struct HeroMatch: ViewModifier {
    let id: UUID
    var ns: Namespace.ID?
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let ns {
            content.matchedGeometryEffect(id: "container-\(id)", in: ns)
        } else {
            content
        }
    }
}
