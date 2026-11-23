import SwiftUI
import SwiftData

/// 妆台：玻璃架按可用空间和字号决定每层件数。
/// 快到期 / 已过期的永远在最上面一层"该先用掉"，其他按分类排列。
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
    @State private var selected: Product? = nil
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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if !active.isEmpty { categoryPicker }
                    if !needsAttention.isEmpty {
                        shelfSection("该先处理", subtitle: "到期提醒和快用完的产品", items: needsAttention)
                    }
                    if !rest.isEmpty {
                        shelfSection(needsAttention.isEmpty ? "全部" : "其他", subtitle: nil, items: rest)
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
            .background(Theme.porcelain.ignoresSafeArea())
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
        .modifier(DetailPresenter(selected: $selected, ns: ns, coordinator: coordinator, context: context))
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

    // MARK: 分类筛选

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip(nil, "全部", "square.grid.2x2")
                ForEach(ProductCategory.allCases) { chip($0, $0.rawValue, $0.symbol) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ c: ProductCategory?, _ title: String, _ symbol: String) -> some View {
        let on = filter == c
        return Button { withAnimation(Theme.spring) { filter = c } } label: {
            Label(title, systemImage: symbol)
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
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 架子

    /// 一个区块 = 标题 + 若干层架子
    private func shelfSection(_ title: String, subtitle: String?, items: [Product]) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                shelfRow(Array(items[start..<min(start + columns, items.count)]))
            }
        }
    }

    /// 大字号时每层两件，名字有地方放
    private var columns: Int {
        if typeSize.isAccessibilitySize { return 2 }
        return widthClass == .regular ? 5 : 3
    }
    private var stageHeight: CGFloat { typeSize.isAccessibilitySize ? 150 : ProductCard.defaultStageHeight }

    /// 一层：物件站在玻璃架板上，名字在架板下方
    private func shelfRow(_ row: [Product]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(row) { p in
                let isSelected = selected?.id == p.id
                Button { withAnimation(Theme.lift) { selected = p } } label: {
                    ProductCard(product: p, ns: ns,
                                isSource: !isSelected,
                                live: selected == nil,
                                stageHeight: stageHeight)
                }
                .buttonStyle(ShelfPressStyle())
                // 浮层模式下，拿起来的那件从架子上"消失"（matchedGeometryEffect 把它带到详情）
                .opacity(isSelected && !LiftPresentation.usesZoom ? 0 : 1)
                .transition(.asymmetric(insertion: .offset(y: -220).combined(with: .opacity),
                                        removal: .scale(scale: 0.6).combined(with: .opacity)))
                .contextMenu { menu(for: p) }
                .accessibilityAction(named: "用了一次") { quickUse(p) }
            }
            ForEach(0..<(columns - row.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
        .background(alignment: .top) {
            ShelfPlank()
                .padding(.horizontal, -10)
                .padding(.top, stageHeight)
        }
        .padding(.top, 6)
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

/// 详情的呈现：iOS 18 全屏 + 系统缩放转场（.navigationTransition(.zoom)）；
/// iOS 17 浮层 + matchedGeometryEffect。两种都由详情页自己做"拿起来"的 3D 倾斜与投影。
struct DetailPresenter: ViewModifier {
    @Binding var selected: Product?
    let ns: Namespace.ID
    let coordinator: AppCoordinator
    let context: ModelContext

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            content.fullScreenCover(item: $selected) { p in
                ProductDetailView(product: p, ns: ns, zoomed: true) { selected = nil }
                    .environment(coordinator)
                    .modelContext(context)
                    .navigationTransition(.zoom(sourceID: p.uid, in: ns))
                    .presentationBackground(.clear)
            }
        } else {
            overlayed(content)
        }
        #else
        overlayed(content)
        #endif
    }

    private func overlayed(_ content: Content) -> some View {
        content.overlay {
            if let p = selected, !p.isDeleted {
                ProductDetailView(product: p, ns: ns) {
                    withAnimation(Theme.lift) { selected = nil }
                }
            }
        }
    }
}
