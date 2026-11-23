import SwiftUI
import SwiftData

/// 藏品：一面放满玻璃瓶的架子。
///
/// 顶部是收藏总览（总值 / 件数 / 品牌 / 备用），下面按品类分层：每层横向滑动，
/// 下一件总是露出半个身子，一眼就看得出"我拥有的东西很多、而且很贵"。
/// 快到期 / 已过期 / 快用完的永远在最上面一层"该先用掉"。
/// 物件按真实比例高低错落、底边贴住架板；点一下把它"拿起来"看详情。
struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var widthClass
    @Query(sort: \Product.createdAt, order: .forward, animation: .spring(response: 0.42, dampingFraction: 0.82))
    private var all: [Product]
    @Namespace private var ns
    @State private var filter: ProductCategory? = nil
    @State private var search = ""
    @State private var pendingDelete: Product? = nil
    @State private var quickUses = 0

    private var active: [Product] { all.filter { !$0.isFinished } }

    private var shown: [Product] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return active.filter {
            (filter == nil || $0.category == filter) &&
            (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.brand.localizedCaseInsensitiveContains(q))
        }
    }

    private var needsAttention: [Product] {
        shown.filter { $0.expiryState != .fresh || $0.isLow }.sorted { $0.effectiveExpiry < $1.effectiveExpiry }
    }

    private var rest: [Product] {
        shown.filter { $0.expiryState == .fresh && !$0.isLow }
            .sorted { ($0.category.order, $0.createdAt) < ($1.category.order, $1.createdAt) }
    }

    // MARK: 收藏总览（"我东西很多"这件事，先用数字说出来）

    private var totalValue: Double { active.reduce(0.0) { $0 + ($1.price ?? 0) } }
    private var pricedCount: Int { active.filter { ($0.price ?? 0) > 0 }.count }
    private var brandCount: Int {
        Set(active.map { $0.brand.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }).count
    }
    private var backupCount: Int { active.reduce(0) { $0 + $1.backupStock } }
    private var attentionCount: Int {
        active.filter { $0.expiryState != .fresh || $0.isLow }.count
    }

    /// "14 件在用 · 13 个品牌 · 4 件该先处理 · 3 件备用"
    private var summary: String {
        var parts = ["\(active.count) 件在用"]
        if brandCount > 0 { parts.append("\(brandCount) 个品牌") }
        if attentionCount > 0 { parts.append("\(attentionCount) 件该先处理") }
        if backupCount > 0 { parts.append("\(backupCount) 件备用") }
        return parts.joined(separator: " · ")
    }

    private var glowColors: [Color] {
        let tints = active.compactMap { p -> Color? in p.cutout == nil ? p.tint : nil }
        return Array(tints.prefix(3))
    }

    // MARK: 分组

    private struct ShelfGroup: Identifiable {
        let category: ProductCategory
        let items: [Product]
        let value: Double
        var id: String { category.rawValue }
    }

    private var groups: [ShelfGroup] {
        ProductCategory.allCases.compactMap { category in
            let items = rest.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            let value = items.reduce(0.0) { $0 + ($1.price ?? 0) }
            return ShelfGroup(category: category, items: items, value: value)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if !active.isEmpty {
                        overview
                        categoryPicker
                    }
                    if !needsAttention.isEmpty {
                        shelfSection("该先用掉", subtitle: "到期提醒和快用完的产品",
                                     items: needsAttention, value: nil)
                    }
                    ForEach(groups) { group in
                        shelfSection(group.category.rawValue, subtitle: nil,
                                     items: group.items, value: group.value)
                    }
                    if active.isEmpty {
                        emptyState
                    } else if shown.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background {
                ZStack {
                    Theme.porcelain
                    AmbientGlow(colors: glowColors)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("藏品")
            .searchable(text: $search, prompt: "搜索名称或品牌")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { coordinator.editor = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加产品")
                }
            }
        }
        .onAppear { MotionService.shared.begin() }
        .onDisappear { MotionService.shared.end() }
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.impact(weight: .light), trigger: quickUses)
        .confirmationDialog("删除这件产品？", isPresented: deleteBinding, titleVisibility: .visible,
                            presenting: pendingDelete) { p in
            Button("删除「\(p.name)」", role: .destructive) {
                withAnimation(Theme.spring) { context.delete(p) }
            }
        } message: { _ in
            Text("删除后无法恢复。用完的产品请选「用完了」，会留在空瓶墙上。")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: 总览

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if totalValue > 0 {
                    Text(Fmt.bigMoney(totalValue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("藏品总值")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(active.count)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("件藏品")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if backupCount > 0 {
                    Label("\(backupCount) 件备用", systemImage: "shippingbox")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if totalValue > 0 && pricedCount < active.count {
                Text("总值按填了价格的 \(pricedCount) 件算")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24, tint: active.first?.tint)
        .accessibilityElement(children: .combine)
    }

    // MARK: 分类筛选

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip(nil, "全部", "square.grid.2x2", count: active.count)
                ForEach(ProductCategory.allCases) { category in
                    let count = active.filter { $0.category == category }.count
                    if count > 0 {
                        chip(category, category.rawValue, category.symbol, count: count)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ c: ProductCategory?, _ title: String, _ symbol: String, count: Int) -> some View {
        let on = filter == c
        return Button { withAnimation(Theme.spring) { filter = c } } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                Text("\(count)").monospacedDigit().opacity(0.6)
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(on ? Color(uiColor: .systemBackground) : Color.primary)
            .background {
                if on { Capsule().fill(Color.primary).matchedGeometryEffect(id: "chip", in: ns) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 件")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 架子

    /// 一个区块 = 标题（带件数与价值）+ 一层可以横向滑动的玻璃架
    private func shelfSection(_ title: String, subtitle: String?, items: [Product], value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.title3.weight(.semibold))
                Text("\(items.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let value, value > 0 {
                    Text(Fmt.money(value))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            shelfRow(items)
        }
    }

    /// 大字号时每件更宽，名字有地方放
    private var itemWidth: CGFloat {
        if typeSize.isAccessibilitySize { return 104 }
        return widthClass == .regular ? 98 : 78
    }
    private var stageHeight: CGFloat { typeSize.isAccessibilitySize ? 150 : ProductCard.defaultStageHeight }

    /// 一列最多放几件：放得下就不滚动，架板铺满整行
    private var fitsPerRow: Int {
        if typeSize.isAccessibilitySize { return 2 }
        return widthClass == .regular ? 6 : 3
    }

    /// 一层：物件站在同一块玻璃架板上；件数超过一行才横向滑动
    @ViewBuilder
    private func shelfRow(_ items: [Product]) -> some View {
        if items.count <= fitsPerRow {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items) { p in
                    card(p).frame(width: itemWidth)
                }
                ForEach(0..<(fitsPerRow - items.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.top, 6)
            .background(alignment: .top) {
                ShelfPlank()
                    .padding(.horizontal, -10)
                    .padding(.top, stageHeight)
            }
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items) { p in
                        card(p).frame(width: itemWidth)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .background(alignment: .top) {
                    ShelfPlank()
                        .padding(.horizontal, 10)
                        .padding(.top, stageHeight)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    private func card(_ p: Product) -> some View {
        Button { coordinator.openDetail(p) } label: {
            ProductCard(product: p, live: coordinator.detail == nil, stageHeight: stageHeight)
        }
        .buttonStyle(ShelfPressStyle())
        .overlay(alignment: .topTrailing) {
            if p.backupStock > 0 {
                // 有备用库存：一眼看出"我有两瓶"
                Text("×\(p.backupStock + 1)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.thinMaterial))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
        }
        .contextMenu { menu(for: p) }
        .accessibilityAction(named: "用了一次") { quickUse(p) }
    }

    @ViewBuilder
    private func menu(for p: Product) -> some View {
        Button(p.isPinned ? "取消常用" : "标为常用", systemImage: p.isPinned ? "star.slash" : "star") {
            withAnimation(Theme.spring) { p.togglePin() }
            coordinator.dataChanged()
        }
        Button("用了一次", systemImage: "drop") { quickUse(p) }
        Button("编辑", systemImage: "pencil") { coordinator.editor = .edit(p) }
        Button("用完了", systemImage: "checkmark.circle") { coordinator.finish(p) }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = p }
    }

    private func quickUse(_ p: Product) {
        withAnimation(Theme.spring) { coordinator.logUse(p) }
        quickUses += 1
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContainerView(kind: .bottle, level: 0.15, tint: Color(hex: Theme.liquids[0]), cap: .dropper, finish: .clear)
                .frame(width: 70, height: 114)
                .accessibilityHidden(true)
            Text("架子还是空的").font(.headline)
            Text("添加你正在用的第一件，记录用量和保质期。")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { coordinator.editor = .new } label: {
                Text("添加产品").font(.headline).frame(minHeight: 44).padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            Button("先看看示例") {
                withAnimation(Theme.spring) { SampleData.insert(into: context) }
            }
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 架子上的按压：轻轻下沉一点（像手指按在玻璃上），松开弹回
struct ShelfPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1, anchor: .bottom)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}
