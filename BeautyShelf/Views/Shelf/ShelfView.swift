import SwiftUI
import SwiftData

/// 妆台：一层层架子，每层三件。
/// 快到期 / 已过期的永远在最上面一层"该先用掉"，其他按分类排列。
struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppCoordinator.self) private var coordinator
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
        shown.filter { $0.expiryState != .fresh }.sorted { $0.effectiveExpiry < $1.effectiveExpiry }
    }

    private var rest: [Product] {
        shown.filter { $0.expiryState == .fresh }
            .sorted { ($0.category.order, $0.createdAt) < ($1.category.order, $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !active.isEmpty { categoryPicker }
                    if !needsAttention.isEmpty {
                        shelfSection("该先用掉", subtitle: "快到期或已过期，先用它们", items: needsAttention)
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
            .navigationTitle("妆台")
            .searchable(text: $search, prompt: "搜索名称或品牌")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { coordinator.editor = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加产品")
                }
            }
        }
        .overlay {
            if let p = selected, !p.isDeleted {
                ProductDetailView(product: p, ns: ns) {
                    withAnimation(Theme.spring) { selected = nil }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                shelfRow(Array(items[start..<min(start + 3, items.count)]))
            }
        }
    }

    private func shelfRow(_ row: [Product]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(row) { p in
                    Button { withAnimation(Theme.spring) { selected = p } } label: {
                        ProductCard(product: p, ns: ns, isSource: selected?.id != p.id)
                    }
                    .pressable()
                    .opacity(selected?.id == p.id ? 0 : 1)
                    .transition(.asymmetric(insertion: .offset(y: -220).combined(with: .opacity),
                                            removal: .scale(scale: 0.6).combined(with: .opacity)))
                    .contextMenu { menu(for: p) }
                    .accessibilityAction(named: "用了一次") { quickUse(p) }
                }
                ForEach(0..<(3 - row.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.bottom, 10)
            ShelfPlank()
        }
    }

    @ViewBuilder
    private func menu(for p: Product) -> some View {
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
            ContainerView(kind: .bottle, level: 0.15, tint: Color(hex: Theme.liquids[0]))
                .frame(width: 64, height: 104)
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
