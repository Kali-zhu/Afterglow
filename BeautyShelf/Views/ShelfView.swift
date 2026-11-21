import SwiftUI
import SwiftData

/// 主界面：一层层架子，每层三个瓶子。
/// 快到期 / 已过期的单独放在最上面一层，其他按分类排列。
struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.expiryDate) private var products: [Product]
    @Namespace private var ns
    @State private var filter: ProductCategory?
    @State private var selected: Product?
    @State private var showingAdd = false
    @State private var search = ""

    private var shown: [Product] {
        products.filter {
            (filter == nil || $0.category == filter) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.brand.localizedCaseInsensitiveContains(search))
        }
    }
    private var needsAttention: [Product] { shown.filter { $0.expiryState != .fresh } }
    private var rest: [Product] { shown.filter { $0.expiryState == .fresh } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    categoryPicker
                    if !needsAttention.isEmpty {
                        shelfSection("该先用掉", items: needsAttention)
                    }
                    if !rest.isEmpty {
                        shelfSection(needsAttention.isEmpty ? "全部" : "其他", items: rest)
                    }
                    if products.isEmpty { emptyState }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("妆台")
            .searchable(text: $search, prompt: "搜索名称或品牌")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加产品")
                }
            }
        }
        .overlay {
            if let p = selected {
                ProductDetailView(product: p, ns: ns) {
                    withAnimation(Theme.spring) { selected = nil }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddProductView() }
        .sensoryFeedback(.selection, trigger: filter)
    }

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
                .padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(on ? Color(uiColor: .systemBackground) : .primary)
                .background {
                    if on { Capsule().fill(.primary).matchedGeometryEffect(id: "chip", in: ns) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 一个区块 = 标题 + 若干层架子
    private func shelfSection(_ title: String, items: [Product]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
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
                        ProductCard(product: p, ns: ns)
                    }
                    .pressable()
                    .opacity(selected?.id == p.id ? 0 : 1)
                    .contextMenu {
                        Button("用了一次", systemImage: "drop") { withAnimation(Theme.spring) { p.logUse() } }
                        Button("删除", systemImage: "trash", role: .destructive) { context.delete(p) }
                    }
                }
                ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
            }
            .padding(.bottom, 10)
            // 架板：有厚度的一条，而不是发丝线
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.shelf)
                .frame(height: 6)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            LiquidBottle(level: 0.15, tint: Color(hex: Theme.liquids[0]))
                .frame(width: 64, height: 104)
            Text("架子还是空的").font(.headline)
            Text("添加你正在用的第一瓶，记录用量和保质期。")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("添加产品") { showingAdd = true }
                .buttonStyle(.borderedProminent).tint(.primary)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

#Preview {
    ShelfView().modelContainer(for: Product.self, inMemory: true)
}
