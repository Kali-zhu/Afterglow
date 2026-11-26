import SwiftUI
import SwiftData

/// 空瓶：把"用完了"变成值得看的东西。
///
/// 顶部一张玻璃统计卡（今年用空几件、用完的价值、平均每次、平均用多久），
/// 然后是待补货，最后一整面"空瓶墙"：空瓶倒空后褪成磨砂的白，站在玻璃架板上，
/// 每一瓶下面写着它陪了你多久、用了几次、每次多少钱。
struct FinishedView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Product.createdAt, order: .forward, animation: .spring(response: 0.42, dampingFraction: 0.82))
    private var all: [Product]
    @State private var restockTick = 0
    @State private var showShareCard = false

    private var finished: [Product] {
        all.filter { $0.isFinished }
            .sorted { ($0.finishedDate ?? .distantPast) > ($1.finishedDate ?? .distantPast) }
    }

    private var restock: [Product] { all.filter { $0.needsRestock } }

    /// 统计只算真的用空的：示例数据不该变成"你的战绩"。
    /// 一件真的都还没有时退回顾示示例，免得统计卡全是破折号。
    private var counted: [Product] {
        let own = finished.filter { !$0.isSample }
        return own.isEmpty ? finished : own
    }

    private var thisYear: [Product] {
        counted.filter {
            guard let d = $0.finishedDate else { return false }
            return Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
        }
    }

    // MARK: 统计

    private var finishedValue: Double { counted.reduce(0.0) { $0 + ($1.price ?? 0) } }

    private var averagePerUse: Double? {
        let priced = counted.filter { ($0.price ?? 0) > 0 && $0.useCount > 0 }
        guard !priced.isEmpty else { return nil }
        let cost = priced.reduce(0.0) { $0 + ($1.price ?? 0) }
        let uses = priced.reduce(0) { $0 + $1.useCount }
        guard uses > 0 else { return nil }
        return cost / Double(uses)
    }

    private var averageDays: Int? {
        guard !counted.isEmpty else { return nil }
        return counted.reduce(0) { $0 + $1.usageDays } / counted.count
    }

    private var durationValue: String {
        guard let days = averageDays else { return "—" }
        if days >= 45 { return "\(max(1, Int((Double(days) / 30).rounded()))) 个月" }
        return "\(days) 天"
    }

    // MARK: 空瓶墙的分行

    /// 一层放几件：大字号时每件更宽，一层只放两件（ROADMAP B9）
    private var columns: Int {
        if typeSize.isAccessibilitySize { return 2 }
        return widthClass == .regular ? 6 : 4
    }

    private var rows: [[Product]] {
        stride(from: 0, to: finished.count, by: columns).map { start in
            Array(finished[start..<min(start + columns, finished.count)])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // 一件空瓶都还没有、也没有待补货：整页只讲一件事，不摆满零和破折号的统计卡
                if finished.isEmpty && restock.isEmpty {
                    emptyPage
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if finished.isEmpty {
                                if !restock.isEmpty { restockList }
                                emptyCard
                            } else {
                                statsCard
                                shareButton
                                if !restock.isEmpty { restockList }
                                wall
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background {
                ScreenBackground(colors: Array(finished.prefix(3).map(\.tint)))
            }
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

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(thisYear.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(Self.year) 年用空")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("累计 \(counted.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                StatReadout(value: finishedValue > 0 ? Fmt.bigMoney(finishedValue) : "—",
                            caption: "用完的价值")
                Spacer(minLength: 6)
                StatReadout(value: averagePerUse.map { Fmt.money($0) } ?? "—",
                            caption: "平均每次")
                Spacer(minLength: 6)
                StatReadout(value: durationValue,
                            caption: "平均用多久")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24, tint: finished.first?.tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今年用空 \(thisYear.count) 件，累计 \(counted.count) 件")
    }

    private static var year: Int {
        Calendar.current.component(.year, from: .now)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("待补货").font(.title3.weight(.semibold))
                Text("\(restock.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(restock.enumerated()), id: \.element.id) { index, p in
                    if index > 0 { Divider().padding(.leading, 60) }
                    restockRow(p)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glassPanel(cornerRadius: 20)
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

    /// 买到了：用完的 → 藏品里多一件全新的同款；还在用的 → 备用库存 +1
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

    // MARK: 空瓶墙

    private var wall: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("空瓶墙").font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Text("累计 \(finished.count) 件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                emptyRow(row)
            }
        }
    }

    private func emptyRow(_ row: [Product]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(row) { p in
                Button { coordinator.openDetail(p) } label: {
                    EmptyBottleCell(product: p)
                }
                .buttonStyle(ShelfPressStyle())
                .contextMenu { menu(for: p) }
            }
            ForEach(0..<(columns - row.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
        .padding(.top, 6)
        .background(alignment: .top) {
            ShelfPlank()
                .padding(.horizontal, -10)
                .padding(.top, EmptyBottleCell.stageHeight)
        }
    }

    // MARK: 还没有空瓶

    /// 一面还空着的墙：三件磨砂的空瓶影子站在一段玻璃架板上
    private var ghostShelf: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 22) {
                ghost(.bottle, size: CGSize(width: 34, height: 76))
                ghost(.jar, size: CGSize(width: 44, height: 58))
                ghost(.tube, size: CGSize(width: 30, height: 68))
            }
            .padding(.bottom, 3)
            ShelfPlank()
                .frame(width: 186)
        }
        .accessibilityHidden(true)
    }

    private func ghost(_ kind: VesselKind, size: CGSize) -> some View {
        ContainerView(kind: kind, level: 0, tint: Theme.shelf, animated: false)
            .frame(width: size.width, height: size.height)
            .grayscale(1)
            .opacity(0.42)
    }

    /// 崭新的空瓶页：一面空墙、一句话、一个去处，上下留白把它居中
    private var emptyPage: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    ghostShelf
                    VStack(spacing: 8) {
                        Text("空瓶墙还空着").font(.title3.weight(.semibold))
                        Text("用完一件，它就会褪成磨砂的白，站到这一面墙上——记着它陪了你多久、用了几次、每次多少钱。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 26)
                    Button { coordinator.tab = .shelf } label: {
                        Label("去藏品里挑一件", systemImage: "square.grid.2x2")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.primary)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .padding(.top, 26)
                    .accessibilityHint("打开藏品，长按一件产品选「用完了」")
                    Text("在藏品里长按任意一件，选「用完了」")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 28)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// 有待补货、但墙上还空着：一张小卡，别让页面被切成两截
    private var emptyCard: some View {
        VStack(spacing: 16) {
            ghostShelf
            VStack(spacing: 6) {
                Text("空瓶墙还空着").font(.headline)
                Text("用完一件，它会站到这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .glassPanel(cornerRadius: 24)
    }
}

/// 空瓶墙上的一件：空的磨砂瓶站在架板上，下面两行字写着它陪了你多久
private struct EmptyBottleCell: View {
    let product: Product

    static let stageHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // 空瓶不是纯白：底部留一道它自己颜色的残影，架板上还有一小片焦散。
                // 明度差靠这两样和影子一起拉开，墙才不是一片糊掉的白（ROADMAP B4）
                CausticGlow(tint: product.tint, width: 34, strength: 0.55)
                    .offset(y: -1)
                ContactShadow(width: 38)
                    .offset(y: 1)
                ContainerView(product: product, level: 0.06, animated: false)
                    .frame(width: 44, height: 78)
            }
            .frame(height: Self.stageHeight, alignment: .bottom)
            Color.clear.frame(height: ShelfPlank.height - ShelfPlank.surface + 2)
            VStack(spacing: 2) {
                Text(product.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var detail: String {
        var parts = ["\(product.useCount) 次", durationText]
        if let cost = product.costPerUse { parts.append("\(Fmt.money(cost))/次") }
        return parts.joined(separator: " · ")
    }

    private var durationText: String {
        let days = product.usageDays
        if days >= 60 { return "\(max(1, Int((Double(days) / 30).rounded()))) 个月" }
        return "\(days) 天"
    }

    private var accessibilityText: String {
        var s = "\(product.name)，用了 \(product.useCount) 次，用了 \(product.usageDays) 天"
        if let cost = product.costPerUse { s += "，每次 \(Fmt.money(cost))" }
        return s
    }
}
