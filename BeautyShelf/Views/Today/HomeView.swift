import SwiftUI
import SwiftData

/// 今日（首页）：用户自己从藏品里挑的几件"常用"。
/// 点哪一件 → 直接拿起来进使用页（ProductDetailView），按形状操作或点按钮记一次。
/// 底部一条小提醒：快过期 / 快见底的，最多 3 件。
struct TodayView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.createdAt) private var all: [Product]
    @Namespace private var ns
    @State private var selected: Product? = nil
    @State private var picking = false

    private var active: [Product] { all.filter { !$0.isFinished } }
    private var pinned: [Product] {
        active.filter(\.isPinned).sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }
    private var usedCount: Int { pinned.filter(\.usedToday).count }
    private var attention: [Product] {
        Array(active.filter { $0.expiryState != .fresh || $0.isLow }
            .sorted { $0.effectiveExpiry < $1.effectiveExpiry }
            .prefix(3))
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if pinned.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(pinned) { p in
                                let isSel = selected?.id == p.id
                                Button { withAnimation(Theme.lift) { selected = p } } label: {
                                    PinTile(product: p, ns: ns, isSource: !isSel)
                                }
                                .buttonStyle(ShelfPressStyle())
                                .opacity(isSel && !LiftPresentation.usesZoom ? 0 : 1)
                                .contextMenu {
                                    Button("从首页拿下", systemImage: "star.slash") {
                                        withAnimation(Theme.spring) { p.togglePin() }
                                        coordinator.dataChanged()
                                    }
                                }
                            }
                            addTile
                        }
                    }
                    if !attention.isEmpty { attentionStrip }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button("挑选") { picking = true }
                        .accessibilityLabel("从藏品挑选首页产品")
                }
            }
            .sheet(isPresented: $picking) { PinPickerView().environment(coordinator) }
        }
        .modifier(DetailPresenter(selected: $selected, ns: ns, coordinator: coordinator, context: context))
        .task { migratePins() }
    }

    /// 老数据第一次进新首页：把早晚流程里的产品先放上来，免得一片空
    private func migratePins() {
        let key = "pinsMigrated.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard pinned.isEmpty else { return }
        for (i, p) in active.filter({ $0.inMorning || $0.inEvening }).enumerated() {
            p.pinnedAt = Date.now.addingTimeInterval(Double(-i))
        }
        coordinator.dataChanged()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.title3.weight(.semibold))
            if !pinned.isEmpty {
                Text(usedCount == 0 ? "点一下瓶子，就记一次" : "今天用了 \(usedCount) 件，共 \(pinned.count) 件常用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var addTile: some View {
        Button { picking = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                Text("从藏品挑选").font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: PinTile.height)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
            )
        }
        .buttonStyle(ShelfPressStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: -8) {
                ContainerView(kind: .bottle, level: 0.6, tint: Color(hex: Theme.liquids[0]), animated: false)
                    .frame(width: 46, height: 76)
                ContainerView(kind: .tube, level: 0.4, tint: Color(hex: Theme.liquids[2]), animated: false)
                    .frame(width: 40, height: 66)
                ContainerView(kind: .jar, level: 0.7, tint: Color(hex: Theme.liquids[3]), animated: false)
                    .frame(width: 50, height: 52)
            }
            .accessibilityHidden(true)
            Text("把每天会用的几件放到首页").font(.headline)
            Text("以后打开就能看到，点一下瓶子就记一次。\n在藏品里长按也能「放到首页」。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { picking = true } label: {
                Label("去藏品里挑", systemImage: "star")
                    .font(.headline)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
    }

    private var attentionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("留意一下").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(attention) { p in
                    Button { withAnimation(Theme.lift) { selected = p } } label: {
                        HStack(spacing: 12) {
                            ProductFigure(product: p, maxPixel: 160)
                                .frame(width: 24, height: 38)
                            Text(p.name).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(note(for: p))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(p.expiryState != .fresh ? p.expiryState.color : Theme.honey)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if p.id != attention.last?.id { Divider().padding(.leading, 50) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        }
    }

    private func note(for p: Product) -> String {
        p.expiryState != .fresh ? p.expiryText : "快见底 · \(p.remainingText)"
    }
}

/// 首页的一件：瓷白卡片上站着实物，下面名字 + 剩余；今天用过右上角一个小对勾
struct PinTile: View {
    let product: Product
    var ns: Namespace.ID
    var isSource: Bool = true

    static let height: CGFloat = 228

    var body: some View {
        VStack(spacing: 10) {
            ProductFigure(product: product, maxPixel: 500)
                .frame(height: 130 * max(0.6, product.shelfScale))
                .frame(height: 136, alignment: .bottom)
                .modifier(LiftSource(id: product.uid, ns: ns, isSource: isSource))
                .background(alignment: .bottom) {
                    Ellipse()
                        .fill(product.tint.opacity(0.25))
                        .frame(width: 80, height: 10)
                        .blur(radius: 5)
                        .offset(y: 5)
                }
            VStack(spacing: 2) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(product.remainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        )
        .overlay(alignment: .topTrailing) {
            if product.usedToday {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.sage)
                    .font(.title3)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(product.name)
        .accessibilityValue("\(product.remainingText)\(product.usedToday ? "，今天用过" : "")")
        .accessibilityHint("轻点拿起来记一次")
        .accessibilityAddTraits(.isButton)
    }
}

/// 从藏品里挑首页的产品
struct PinPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \Product.createdAt) private var all: [Product]

    private var active: [Product] {
        all.filter { !$0.isFinished }.sorted { ($0.category.order, $0.createdAt) < ($1.category.order, $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if active.isEmpty { Text("藏品里还没有产品。").foregroundStyle(.secondary) }
                    ForEach(active) { p in
                        Button {
                            p.togglePin()
                            coordinator.dataChanged()
                        } label: {
                            HStack(spacing: 12) {
                                ProductFigure(product: p, maxPixel: 160)
                                    .frame(width: 26, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).foregroundStyle(.primary)
                                    if !p.brand.isEmpty {
                                        Text(p.brand).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: p.isPinned ? "star.fill" : "star")
                                    .foregroundStyle(p.isPinned ? Theme.honey : Color.secondary)
                                    .font(.body.weight(.medium))
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(p.isPinned ? "在首页" : "")
                    }
                } footer: {
                    Text("点亮星星的会出现在首页。")
                }
            }
            .navigationTitle("放到首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
