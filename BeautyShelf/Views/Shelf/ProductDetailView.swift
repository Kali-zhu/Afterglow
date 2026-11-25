import SwiftUI
import SwiftData

/// 点开 = 把它从架子上"拿起来"：放大、带一点 3D 倾斜、投影变大变柔。
/// 这是全 App 唯一的"使用页"：首页、藏品、空瓶、近期记录点任何一件产品都打开它。
/// iOS 18 由 ProductDetailPresenter 的系统缩放转场带过来，iOS 17 直接全屏。
/// 实物本身可以按形状操作来记一次使用（见 UseGestureHero），下方保留大按钮"用了一次"。
/// 估算型产品（口红、粉盒）用滑块调整剩余量。
///
/// 一起记多件时也进这一页：几件产品像卡片一样左右滑动，一张一张地记。
/// 底色和首页、藏品、空瓶一样是那层淡淡的瓷白（Theme.porcelain），产品色只是背景里的一团柔光。
struct ProductDetailView: View {
    /// 可以左右滑动的几件产品，第一张是点开的那件
    let items: [Product]
    var close: () -> Void

    @Environment(AppCoordinator.self) var coordinator
    @Environment(\.modelContext) var context
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var scheme

    /// 当前在第几张卡
    @State var index = 0
    /// 每件产品各记了几次：液面晃一下
    @State var sloshes: [UUID: Int] = [:]
    /// 只有"用了一次"按钮触发时 +1：实物自动演示一遍动作
    @State var demos: [UUID: Int] = [:]
    /// 触感反馈的触发计数
    @State var tick = 0
    @State var revealed = false
    @State var lifted = false
    @State var tilt: Double = 0
    @State var confirmDelete = false
    /// 这一次记给哪个时段：默认当前时段（15:00 前早间，之后晚间）
    @State var slot: RoutineSlot = SharedStore.currentSlot()
    /// 刚记下的那一件：按钮短暂变成"已记下"，并给出撤销
    @State var recordedID: UUID? = nil
    @State var resetTask: Task<Void, Never>? = nil
    /// 刚在一组里用完的那件：提示"收进空瓶墙了"，可以顺手加进补货
    @State var finishedID: UUID? = nil
    @State var finishedTask: Task<Void, Never>? = nil

    init(items: [Product], close: @escaping () -> Void) {
        self.items = items
        self.close = close
    }

    /// 当前这张卡上的产品
    private var current: Product { items[min(max(index, 0), items.count - 1)] }
    /// 一起记多件：可以左右滑动
    private var grouped: Bool { items.count > 1 }

    private func heroSize(_ p: Product) -> CGSize {
        p.cutout != nil ? CGSize(width: 210, height: 246) : CGSize(width: 144, height: 222)
    }

    var body: some View {
        ZStack {
            backdrop
                .opacity(revealed ? 1 : 0.0001)
                .accessibilityHidden(true)

            // 卡片在上面，按钮在自己的一块里：两者各占各的高度，永远不会叠在一起
            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.uid) { pair in
                        card(pair.element).tag(pair.offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                actions
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
            finishedTask?.cancel()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .sensoryFeedback(.selection, trigger: estimateStep)
        .confirmationDialog("删除「\(current.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteCurrent() }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    // MARK: 一张卡（每件产品一张）

    private func card(_ p: Product) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                hero(p)
                    .padding(.top, 46)

                VStack(spacing: 4) {
                    Text(p.name)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    if !p.brand.isEmpty {
                        Text(p.brand).font(.title3).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                stats(p)
                expiryLine(p)
                if p.measureMode == .estimate {
                    estimateSlider(p)
                }
                usageDots(p)
                // 空瓶只看记录：不再选时段
                if !p.isFinished { slotToggles }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .opacity(revealed ? 1 : 0)
        }
        .scrollIndicators(.hidden)
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

    private func hero(_ p: Product) -> some View {
        VStack(spacing: 10) {
            UseGestureHero(product: p,
                           size: heroSize(p),
                           slosh: sloshes[p.uid] ?? 0,
                           demoTrigger: demos[p.uid] ?? 0) {
                logUse(p, fromGesture: true)
            }
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: -0.4, z: 0), anchor: .bottom, perspective: 0.55)
            .background(alignment: .bottom) {
                // 投影：拿起来后变大、变柔、离得更远
                Ellipse()
                    .fill(Color.black.opacity(lifted ? 0.16 : 0.3))
                    .frame(width: heroSize(p).width * (lifted ? 0.85 : 0.65), height: lifted ? 26 : 8)
                    .blur(radius: lifted ? 16 : 3)
                    .offset(y: lifted ? 30 : 4)
                    .accessibilityHidden(true)
            }
            .scaleEffect(lifted ? 1 : 0.96, anchor: .bottom)

            if !p.isFinished {
                Text(UseGestureHero.hint(for: p))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: 估算剩余

    private func estimateBinding(_ p: Product) -> Binding<Double> {
        Binding(get: { p.level },
                set: { p.setEstimatedLevel($0) })
    }

    /// 每跨过 5% 轻触一下
    private var estimateStep: Int {
        current.measureMode == .estimate ? Int((current.level * 20).rounded()) : -1
    }

    private func estimateSlider(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("估算剩余").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((p.level * 100).rounded()))%")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Slider(value: estimateBinding(p), in: 0...1, step: 0.05) {
                Text("估算剩余")
            } minimumValueLabel: {
                Image(systemName: "circle.dotted").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "circle.fill").accessibilityHidden(true)
            }
            .tint(p.tint.mixed(with: .black, 0.15))
            .accessibilityValue("约剩 \(Int((p.level * 100).rounded()))%")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    // MARK: 数据

    private func stats(_ p: Product) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                stat("\(p.useCount)", "次")
                stat(remainingValue(p), remainingUnit(p))
                stat("\(abs(p.daysUntilExpiry))", "天",
                     color: p.expiryState == .fresh ? .primary : p.expiryState.color)
            }
            GridRow {
                Text("已用")
                Text(usesLeftText(p).map { "还剩 · \($0)" } ?? "还剩")
                Text(p.daysUntilExpiry >= 0 ? "后到期" : "已过期")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已使用 \(p.useCount) 次，\(p.remainingText)，\(p.expiryText)")
    }

    private func remainingValue(_ p: Product) -> String {
        switch p.measureMode {
        case .volume: return Fmt.amount(p.remainingAmount)
        case .count: return "\(Int(p.remainingAmount.rounded()))"
        case .estimate: return "\(Int(p.remainingAmount.rounded()))"
        }
    }

    private func remainingUnit(_ p: Product) -> String {
        switch p.measureMode {
        case .volume: return p.unit
        case .count: return "/\(Int(p.totalAmount.rounded())) 片"
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
    private func usesLeftText(_ p: Product) -> String? {
        guard p.measureMode == .volume, p.amountPerUse > 0 else { return nil }
        let n = Int((p.remainingAmount / p.amountPerUse).rounded(.down))
        return "约 \(n) 次"
    }

    // MARK: 到期一行（替代原来的日期卡片）

    private func expiryLine(_ p: Product) -> some View {
        var basis: String {
            switch p.expiryBasis {
            case .packaging: return "（包装日期）"
            case .afterOpening(let m): return "（开封后 \(m) 个月）"
            }
        }
        let extra = [p.price.map { price in p.costPerUse.map { "每次 \(Fmt.money($0))" } ?? Fmt.money(price) },
                     p.backupStock > 0 ? "备用 \(p.backupStock) 件" : nil].compactMap { $0 }
        return VStack(spacing: 4) {
            Text("\(Fmt.day(p.effectiveExpiry).replacingOccurrences(of: " ", with: "")) 到期\(basis)")
                .foregroundStyle(p.expiryState == .fresh ? Color.secondary : p.expiryState.color)
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
        .padding(.top, 2)
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

    // MARK: 配色：白天瓷白、夜间近黑，跟随系统（和首页、藏品、空瓶同一层底色）

    private var dark: Bool { scheme == .dark }
    private var stage: Color { Theme.porcelain }
    /// 主色：夜间白、白天黑
    private var ink: Color { dark ? Color.white.opacity(0.95) : Color(hex: "1C1C1E") }
    private var inkReverse: Color { dark ? .black : .white }
    private var soft: Color { Color.primary.opacity(dark ? 0.1 : 0.07) }

    // MARK: 背景：一层淡淡的瓷白 + 产品色的一团柔光（不用粉调的大片渐变）

    private var backdrop: some View {
        ScreenBackground(colors: [current.tint.mixed(with: Theme.porcelain, 0.62)])
            .animation(.easeInOut(duration: 0.35), value: index)
    }

    // MARK: 最近 14 天

    private func usageDots(_ p: Product) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days: [Date] = (0..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let usedCount = days.filter { p.used(on: $0) }.count
        return VStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(days, id: \.self) { day in
                    Circle()
                        .fill(p.used(on: day) ? ink : Color.primary.opacity(0.12))
                        .frame(width: 10, height: 10)
                }
            }
            Text("最近 14 天").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 14 天里用了 \(usedCount) 天")
    }

    // MARK: 操作

    private var actions: some View {
        VStack(spacing: 10) {
            statusRow

            Button { logUse(current, fromGesture: false) } label: {
                HStack(spacing: 8) {
                    if recordedID == current.uid { Image(systemName: "checkmark") }
                    Text(useTitle(current))
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(inkReverse)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(ink))
            }
            .buttonStyle(ShelfPressStyle())
            .disabled(current.isFinished)

            HStack(spacing: 10) {
                // 空瓶不再「用完了」，只留补货
                if !current.isFinished {
                    softPill("用完了") { finishCurrent() }
                }
                softPill(current.needsRestock ? "已在补货" : "加入补货") {
                    withAnimation(Theme.snappy) { current.needsRestock.toggle() }
                }
                // 退出放在拇指够得到的地方，不用再伸手去左上角
                softPill("完成") { close() }
                    .accessibilityLabel("关闭详情")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            // 一层不透明的底：滚动的内容不会从按钮后面透出来
            VStack(spacing: 0) {
                LinearGradient(colors: [stage.opacity(0), stage.opacity(0.92), stage],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                stage
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 按钮上方那一条：刚用完的提示，其次是刚记下的撤销，再其次是"第几张 / 共几张"
    @ViewBuilder private var statusRow: some View {
        if let finishedID, let done = items.first(where: { $0.uid == finishedID }) {
            HStack(spacing: 10) {
                Label("「\(done.name)」收进空瓶墙", systemImage: "archivebox")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if !done.needsRestock {
                    Button {
                        withAnimation(Theme.snappy) { done.needsRestock = true }
                        coordinator.dataChanged()
                    } label: {
                        Label("加入补货", systemImage: "cart")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .transition(.opacity)
        } else if recordedID == current.uid {
            HStack(spacing: 10) {
                Label("已记一次 · \(slot.title)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button { undoLast() } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
            }
            .transition(.opacity)
        } else if grouped {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? ink : Color.primary.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
                Text("\(index + 1) / \(items.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .frame(height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(index + 1) 件，共 \(items.count) 件，左右滑动切换")
            .transition(.opacity)
        }
    }

    /// 主按钮文字：刚记下 / 空瓶显示用完的日期 / 平时"用了一次"
    private func useTitle(_ p: Product) -> String {
        if recordedID == p.uid { return "已记下" }
        if let d = p.finishedDate { return "\(d.formatted(.dateTime.year().month().day()))用完" }
        return "用了一次"
    }

    private func softPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
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
                    Button(current.isPinned ? "取消常用" : "标为常用", systemImage: current.isPinned ? "star.slash" : "star") {
                        current.togglePin()
                        coordinator.dataChanged()
                    }
                    Menu("日常流程") {
                        ForEach(RoutineSlot.allCases) { s in
                            Button {
                                withAnimation(Theme.snappy) { current.setRoutine(s, !current.inRoutine(s)) }
                                coordinator.dataChanged()
                            } label: {
                                Label(current.inRoutine(s) ? "移出\(s.title)" : "加入\(s.title)",
                                      systemImage: current.inRoutine(s) ? "checkmark" : s.symbol)
                            }
                        }
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: current.isPinned ? "star.fill" : "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(current.isPinned ? Theme.honey : .primary)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(soft))
                }
                .accessibilityLabel("更多操作")

                Button { coordinator.editor = .edit(current) } label: {
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

    // MARK: 记一次

    private func logUse(_ p: Product, fromGesture: Bool) {
        guard !p.isFinished else { return }
        // 记一次，并标明属于哪个时段（胶囊默认当前时段）
        withAnimation(Theme.spring) { coordinator.logRoutine(p, slot) }
        sloshes[p.uid, default: 0] += 1
        if !fromGesture { demos[p.uid, default: 0] += 1 }
        tick += 1
        markRecorded(p)
        // 用到见底
        if coordinator.finishing === p {
            if grouped {
                // 一起记多件：不倒空、不退出，就地把这件收进空瓶墙，滑到下一件
                coordinator.finishing = nil
                markDrained(p)
            } else {
                close()
            }
        }
    }

    /// 点「用完了」。一组里记多件时留在这一页：这件收进空瓶墙，自动滑到下一件还没用完的；
    /// 单件时保持原来的样子——关掉详情，播"倒空"动画。
    private func finishCurrent() {
        let p = current
        guard !p.isFinished else { return }
        if grouped {
            markDrained(p)
        } else {
            close()
            coordinator.finish(p)
        }
    }

    /// 在一组里就地用完：标记为已用完、保存、给一次触感，然后滑到下一件。
    /// 这一组都用完了就停在这张卡上（用「完成」退出），不把用户甩出去。
    private func markDrained(_ p: Product) {
        tick += 1
        withAnimation(Theme.spring) { p.markFinished() }
        coordinator.dataChanged()
        resetTask?.cancel()
        recordedID = nil
        withAnimation(Theme.snappy) { finishedID = p.uid }
        // 这条提示是过路的：4 秒后自己收起来，别一直挂在页脚上
        finishedTask?.cancel()
        finishedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(4000))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.snappy) { finishedID = nil }
        }
        advance(after: p)
    }

    /// 从当前这张往后找下一件还没用完的（绕回开头）；全都用完了就留在原地
    private func advance(after p: Product) {
        let count = items.count
        guard count > 1 else { return }
        let next = (1..<count)
            .map { (index + $0) % count }
            .first { !items[$0].isFinished }
        guard let next else { return }
        withAnimation(Theme.spring) { index = next }
    }

    /// 按钮短暂变成"已记下"，并给出撤销；不自动关闭，让用户看到数字和圆点的变化
    private func markRecorded(_ p: Product) {
        withAnimation(Theme.snappy) {
            recordedID = p.uid
            finishedID = nil
        }
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.snappy) {
                if recordedID == p.uid { recordedID = nil }
            }
        }
    }

    private func undoLast() {
        resetTask?.cancel()
        let p = current
        withAnimation(Theme.spring) {
            coordinator.undoRoutine(p, slot)
            recordedID = nil
        }
    }

    private func deleteCurrent() {
        let p = current
        close()
        withAnimation(Theme.spring) { context.delete(p) }
    }
}
