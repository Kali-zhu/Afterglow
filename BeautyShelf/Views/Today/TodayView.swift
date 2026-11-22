import SwiftUI
import SwiftData

/// 今日：一个小仪式。
/// 当前时段（15:00 前早间，之后晚间）的产品按顺序排成一排"托盘"大卡片，
/// 点「拿起来用」或上滑 = 记一次使用，卡片滑进下方"已用"一摞；全部用完时进度环合拢。
/// 右上角可切换成紧凑清单（大字号时默认清单）。
struct TodayView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Product.createdAt) private var all: [Product]

    @State private var slot: RoutineSlot = SharedStore.currentSlot()
    @State private var picking: RoutineSlot? = nil
    /// 顺序存在 UserDefaults，不会触发刷新；改完顺序后 +1
    @State private var orderVersion = 0
    @State private var logTick = 0
    /// "" = 自动（大字号用清单）；"tray" / "list" = 用户手动选的
    @AppStorage("todayLayout") private var layoutRaw = ""
    @Namespace private var trayNS

    private var useList: Bool {
        switch layoutRaw {
        case "list": true
        case "tray": false
        default: dynamicTypeSize.isAccessibilitySize
        }
    }

    private func items(_ slot: RoutineSlot) -> [Product] {
        _ = orderVersion
        return SharedStore.sorted(all.filter { !$0.isFinished && $0.inRoutine(slot) }, for: slot)
    }

    private var list: [Product] { items(slot) }
    private var pending: [Product] { list.filter { !$0.isDone(slot) } }
    private var done: [Product] { list.filter { $0.isDone(slot) } }
    private var progress: Double { list.isEmpty ? 0 : Double(done.count) / Double(list.count) }
    private var allDone: Bool { !list.isEmpty && pending.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if useList { compactList } else { ritual }
            }
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(Theme.spring) { layoutRaw = useList ? "tray" : "list" }
                    } label: {
                        Image(systemName: useList ? "rectangle.stack" : "list.bullet")
                    }
                    .accessibilityLabel(useList ? "切换为托盘卡片" : "切换为紧凑清单")
                    Button("调整") { picking = slot }
                        .accessibilityLabel("调整\(slot.title)流程")
                }
            }
            .sheet(item: $picking, onDismiss: { orderVersion += 1 }) { s in
                RoutinePickerView(slot: s)
                    .environment(coordinator)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: logTick)
        .sensoryFeedback(.success, trigger: allDone) { old, new in !old && new }
    }

    // MARK: - 仪式（托盘）

    private var ritual: some View {
        ScrollView {
            VStack(spacing: 24) {
                slotPicker
                    .padding(.horizontal, 20)
                header
                    .padding(.horizontal, 20)

                if list.isEmpty {
                    emptyState.padding(.horizontal, 20)
                } else if allDone {
                    completion.padding(.horizontal, 20)
                        .transition(completionTransition)
                } else {
                    tray
                }

                if !done.isEmpty {
                    doneStack.padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private var slotPicker: some View {
        Picker("时段", selection: $slot.animation(Theme.spring)) {
            ForEach(RoutineSlot.allCases) { s in
                let n = items(s)
                let d = n.filter { $0.isDone(s) }.count
                Text(n.isEmpty ? s.title : "\(s.title) \(d)/\(n.count)").tag(s)
            }
        }
        .pickerStyle(.segmented)
    }

    private var header: some View {
        HStack(spacing: 20) {
            RitualRing(progress: progress, done: done.count, total: list.count)
                .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Label(slot.title + "流程", systemImage: slot.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if let next = pending.first, !allDone {
                    Text("下一步：\(next.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if list.isEmpty { return "还没有\(slot.title)流程" }
        if allDone { return completionLine }
        if done.isEmpty { return "\(list.count) 步，慢慢来" }
        return "还剩 \(pending.count) 步"
    }

    private var completionLine: String {
        slot == .evening ? "晚间护肤完成，晚安" : "早间护肤完成，出门吧"
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, p in
                        RitualCard(product: p,
                                   step: (list.firstIndex(where: { $0.id == p.id }) ?? index) + 1,
                                   total: list.count,
                                   isNext: index == 0) {
                            use(p)
                        }
                        .containerRelativeFrame(.horizontal) { w, _ in min(320, w * 0.72) }
                        .matchedGeometryEffect(id: geometryID(p, inTray: true), in: trayNS)
                        .transition(cardTransition)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)

            Text("点「拿起来用」或把卡片往上推，就记好了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)
        }
    }

    private var completionTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.96))
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity
            : AnyTransition.asymmetric(insertion: AnyTransition.opacity,
                                       removal: AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top)))
    }

    /// 减弱动态效果时不做卡片→已用一摞的位移
    private func geometryID(_ p: Product, inTray: Bool) -> String {
        reduceMotion ? "\(p.uid.uuidString)-\(inTray ? "tray" : "done")" : p.uid.uuidString
    }

    private var doneStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已用").font(.headline)
                Text("\(done.count)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(done) { p in
                        Menu {
                            Button("撤销这次记录", systemImage: "arrow.uturn.backward") {
                                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.spring) {
                                    coordinator.undoRoutine(p, slot)
                                }
                            }
                        } label: {
                            DoneChip(product: p)
                        }
                        .matchedGeometryEffect(id: geometryID(p, inTray: false), in: trayNS)
                        .accessibilityLabel("\(p.name)，今天已用")
                        .accessibilityHint("轻点可撤销")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var completion: some View {
        VStack(spacing: 14) {
            Image(systemName: slot == .evening ? "moon.stars.fill" : "sun.max.fill")
                .font(.system(size: 40))
                .foregroundStyle(slot == .evening ? Color(hex: "D5C6E8") : Theme.honey)
                .symbolEffect(.bounce, value: reduceMotion ? false : allDone)
                .accessibilityHidden(true)
            Text(completionLine)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(slot == .evening ? "\(list.count) 步都做完了。早点休息。" : "\(list.count) 步都做完了。今天也好好的。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContainerView(kind: .bottle, level: 0.5, tint: Color(hex: Theme.liquids[slot == .evening ? 3 : 0]), animated: false)
                .frame(width: 52, height: 86)
                .accessibilityHidden(true)
            Text("把每天\(slot.title)用的产品排进来，之后点一下就记好了。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                picking = slot
            } label: {
                Label("从妆台挑选", systemImage: "plus")
                    .font(.headline)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
    }

    private func use(_ p: Product) {
        logTick += 1
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) {
            coordinator.logRoutine(p, slot)
        }
    }

    // MARK: - 紧凑清单（无障碍 / 大字号）

    private var compactList: some View {
        List {
            Section {
                slotPicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                HStack(spacing: 16) {
                    RitualRing(progress: progress, done: done.count, total: list.count)
                        .frame(width: 64, height: 64)
                    Text(headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            Section {
                if list.isEmpty {
                    Button { picking = slot } label: {
                        Label("从妆台挑选\(slot.title)用的产品", systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                } else {
                    ForEach(list) { p in
                        RoutineRow(product: p, slot: slot) {
                            withAnimation(Theme.spring) {
                                if p.isDone(slot) {
                                    coordinator.undoRoutine(p, slot)
                                } else {
                                    logTick += 1
                                    coordinator.logRoutine(p, slot)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("移出", systemImage: "minus.circle") {
                                withAnimation { p.setRoutine(slot, false) }
                            }
                            .tint(.gray)
                        }
                    }
                }
            } header: {
                Label(slot.title, systemImage: slot.symbol)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - 托盘里的一张大卡片

struct RitualCard: View {
    let product: Product
    let step: Int
    let total: Int
    let isNext: Bool
    let onUse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragY: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("第 \(step) 步")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if product.expiryState != .fresh {
                    Label(product.expiryText, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(product.expiryState.color)
                        .lineLimit(1)
                }
            }

            ProductFigure(product: product, maxPixel: 700)
                .frame(maxWidth: .infinity)
                .frame(height: 190 * product.shelfScale)
                .frame(height: 190, alignment: .bottom)
                .background(alignment: .bottom) {
                    Ellipse()
                        .fill(product.tint.opacity(0.22))
                        .frame(width: 120, height: 14)
                        .blur(radius: 6)
                        .offset(y: 6)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.brand.isEmpty ? product.remainingText : "\(product.brand) · \(product.remainingText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("第 \(step) 步，共 \(total) 步，\(product.name)，\(product.remainingText)\(product.expiryState == .fresh ? "" : "，" + product.expiryText)")

            Button(action: onUse) {
                Text("拿起来用")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(isNext ? Color.primary : Color.secondary.opacity(0.35))
            .foregroundStyle(isNext ? Color(uiColor: .systemBackground) : Color.primary)
            .accessibilityLabel("拿起来用：\(product.name)")
            .accessibilityHint("记一次使用")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(isNext ? product.tint.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .offset(y: dragY)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragY) / -40), anchor: .bottom)
        .simultaneousGesture(swipeUp)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "拿起来用") { onUse() }
    }

    /// 往上推卡片：超过阈值就记一次；横向拖动交给托盘滚动
    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { v in
                guard abs(v.translation.height) > abs(v.translation.width) else { return }
                dragY = min(0, v.translation.height) * (reduceMotion ? 0.3 : 1)
            }
            .onEnded { v in
                let vertical = abs(v.translation.height) > abs(v.translation.width)
                if vertical && (v.translation.height < -90 || v.predictedEndTranslation.height < -220) {
                    onUse()
                }
                withAnimation(Theme.snappy) { dragY = 0 }
            }
    }
}

/// 已用一摞里的小件
struct DoneChip: View {
    let product: Product

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ProductFigure(product: product, maxPixel: 200)
                .frame(width: 40, height: 56)
                .frame(width: 60, height: 68)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                .opacity(0.85)
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.sage)
                .offset(x: 4, y: 4)
        }
        .frame(minWidth: 44, minHeight: 44)
    }
}

/// 今日进度环：中间是 已用 / 总数；全部完成时合拢并出现对勾
struct RitualRing: View {
    let progress: Double
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = max(6, side * 0.09)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: line)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(Theme.sage, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if total > 0 && progress >= 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.3, weight: .bold))
                        .foregroundStyle(Theme.sage)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(done)/\(total)")
                        .font(.system(size: side * 0.24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Theme.spring, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total > 0 && progress >= 1 ? "流程全部完成" : "已完成 \(done) 步，共 \(total) 步")
    }
}

// MARK: - 紧凑清单的一行

/// 流程里的一行：圆圈（≥44pt）+ 小容器 + 名称
struct RoutineRow: View {
    let product: Product
    let slot: RoutineSlot
    let toggle: () -> Void
    @State var drops = 0

    private var done: Bool { product.isDone(slot) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if !done { drops += 1 }
                toggle()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 2)
                    if done {
                        Circle().fill(product.tint)
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(product.name)
            .accessibilityValue(done ? "今天已记录" : "未记录")
            .accessibilityHint(done ? "轻点撤销这次记录" : "轻点记一次使用")

            ZStack(alignment: .top) {
                ProductFigure(product: product, maxPixel: 160, slosh: drops)
                    .frame(width: 28, height: 46)
                FallingDrop(tint: product.tint, trigger: drops, distance: 26, size: 7)
                    .offset(y: -14)
            }
            .frame(width: 34, height: 50)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .lineLimit(3)
                Text(product.brand.isEmpty ? product.remainingText : "\(product.brand) · \(product.remainingText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if product.expiryState != .fresh {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(product.expiryState.color)
                    .accessibilityLabel(product.expiryText)
            }
        }
    }
}

// MARK: - 挑选 + 排序

/// 从妆台挑选早间 / 晚间流程里的产品，并调整顺序
struct RoutinePickerView: View {
    let slot: RoutineSlot
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \Product.createdAt) private var all: [Product]

    init(slot: RoutineSlot) {
        self.slot = slot
    }

    private var active: [Product] {
        all.filter { !$0.isFinished }.sorted { ($0.category.order, $0.createdAt) < ($1.category.order, $1.createdAt) }
    }

    private var selectedCount: Int { active.filter { $0.inRoutine(slot) }.count }

    var body: some View {
        NavigationStack {
            List {
                if selectedCount > 1 {
                    Section {
                        NavigationLink {
                            RoutineReorderView(slot: slot)
                        } label: {
                            Label("调整顺序（\(selectedCount) 步）", systemImage: "arrow.up.arrow.down")
                                .frame(minHeight: 44)
                        }
                    } footer: {
                        Text("今日托盘和小组件都按这个顺序排。")
                    }
                }
                Section {
                    if active.isEmpty {
                        Text("妆台上还没有产品。").foregroundStyle(.secondary)
                    }
                    ForEach(active) { p in
                        Toggle(isOn: Binding(get: { p.inRoutine(slot) }, set: { on in
                            p.setRoutine(slot, on)
                            coordinator.dataChanged()
                        })) {
                            HStack(spacing: 12) {
                                ProductFigure(product: p, maxPixel: 160)
                                    .frame(width: 24, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    if !p.brand.isEmpty {
                                        Text(p.brand).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text("妆台上的产品")
                }
            }
            .navigationTitle("\(slot.title)流程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 拖动排序（顺序按 uid 存在 App Group 里）
struct RoutineReorderView: View {
    let slot: RoutineSlot
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \Product.createdAt) private var all: [Product]
    @State private var ordered: [Product] = []

    var body: some View {
        List {
            ForEach(ordered) { p in
                HStack(spacing: 12) {
                    Text("\((ordered.firstIndex(where: { $0.id == p.id }) ?? 0) + 1)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22)
                    ProductFigure(product: p, maxPixel: 160)
                        .frame(width: 24, height: 40)
                    Text(p.name).lineLimit(2)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
            .onMove { from, to in
                ordered.move(fromOffsets: from, toOffset: to)
                coordinator.setOrder(ordered, for: slot)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("调整顺序")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ordered = SharedStore.sorted(all.filter { !$0.isFinished && $0.inRoutine(slot) }, for: slot)
        }
    }
}
