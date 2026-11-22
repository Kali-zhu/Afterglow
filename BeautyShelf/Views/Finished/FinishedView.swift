import SwiftUI
import SwiftData

/// 空瓶：顶部"待补货"清单 + 今年空瓶数 + 用完的产品墙（用了几次、多久、每次多少钱）。
struct FinishedView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.createdAt, order: .forward, animation: .spring(response: 0.42, dampingFraction: 0.82))
    private var all: [Product]
    @State private var restockTick = 0
    @State private var showShareCard = false

    private var finished: [Product] {
        all.filter { $0.isFinished }
            .sorted { ($0.finishedDate ?? .distantPast) > ($1.finishedDate ?? .distantPast) }
    }

    private var restock: [Product] { all.filter { $0.needsRestock } }

    private var thisYear: [Product] {
        finished.filter {
            guard let d = $0.finishedDate else { return false }
            return Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !restock.isEmpty { restockList }
                    yearBanner
                    if !finished.isEmpty { shareButton }
                    if finished.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(finished) { p in
                                FinishedCard(product: p)
                                    .contextMenu { menu(for: p) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("空瓶")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            }
            .sheet(isPresented: $showShareCard) {
                EmptiesShareSheet(finished: finished)
            }
        }
        .sensoryFeedback(.success, trigger: restockTick)
    }

    // MARK: 今年空瓶

    private var yearBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("今年空瓶")
                .font(.headline)
            Text("\(thisYear.count)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("件")
                .font(.headline)
            Spacer()
            if !thisYear.isEmpty {
                Text("共用了 \(thisYear.reduce(0) { $0 + $1.useCount }) 次")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: 空瓶记分享图

    private var shareButton: some View {
        Button {
            showShareCard = true
        } label: {
            Label("生成空瓶记", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .foregroundStyle(Color(uiColor: .systemBackground))
        .accessibilityHint("把这个月或今年的空瓶做成一张可以分享的图")
    }

    // MARK: 待补货

    private var restockList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("待补货").font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(restock.enumerated()), id: \.element.id) { index, p in
                    if index > 0 { Divider().padding(.leading, 60) }
                    restockRow(p)
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        }
    }

    private func restockRow(_ p: Product) -> some View {
        HStack(spacing: 12) {
            ContainerView(product: p, animated: false)
                .frame(width: 26, height: 42)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.body.weight(.medium)).lineLimit(2)
                Text(p.isFinished ? (p.brand.isEmpty ? "已用完" : "\(p.brand) · 已用完")
                                  : (p.brand.isEmpty ? p.remainingText : "\(p.brand) · \(p.remainingText)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("买到了") { bought(p) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .accessibilityLabel("买到了\(p.name)")
            Button {
                withAnimation(Theme.spring) { p.needsRestock = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从补货清单移除\(p.name)")
        }
        .padding(.vertical, 6)
    }

    /// 买到了：用完的 → 妆台上多一件全新的同款；还在用的 → 备用库存 +1
    private func bought(_ p: Product) {
        withAnimation(Theme.spring) {
            p.needsRestock = false
            if p.isFinished {
                context.insert(p.makeFreshCopy(openNow: false))
            } else {
                p.backupStock += 1
            }
        }
        restockTick += 1
    }

    @ViewBuilder
    private func menu(for p: Product) -> some View {
        Button("再来一件", systemImage: "arrow.uturn.backward") {
            withAnimation(Theme.spring) { context.insert(p.makeFreshCopy(openNow: false)) }
        }
        Button(p.needsRestock ? "移出补货清单" : "加入补货清单", systemImage: "cart") {
            withAnimation(Theme.spring) { p.needsRestock.toggle() }
        }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) {
            withAnimation(Theme.spring) { context.delete(p) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ContainerView(kind: .bottle, level: 0, tint: Color(hex: Theme.liquids[2]), animated: false)
                .frame(width: 56, height: 92)
                .accessibilityHidden(true)
            Text("还没有空瓶").font(.headline)
            Text("用完一件，在妆台长按它选「用完了」，它会来到这里。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// 空瓶墙上的一件
struct FinishedCard: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                ContainerView(product: product, level: 0, animated: false)
                    .frame(width: 44, height: 72)
                Spacer()
                if let d = product.finishedDate {
                    Text(Fmt.shortDay(d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !product.brand.isEmpty {
                    Text(product.brand).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                fact("用了", "\(product.useCount)", "次")
                fact("用了", "\(product.usageDays)", "天")
                if let c = product.costPerUse {
                    fact("每次", Fmt.money(c), "")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var s = "\(product.name)，用了 \(product.useCount) 次，用了 \(product.usageDays) 天"
        if let c = product.costPerUse { s += "，每次 \(Fmt.money(c))" }
        return s
    }

    private func fact(_ lead: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(lead).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if !unit.isEmpty {
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
