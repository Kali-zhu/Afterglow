import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]
    @State private var picking = false
    /// 挑选页选完之后真正要打开的那几件：等弹层收起来再进详情，两个呈现不会撞在一起
    @State private var pendingOpen: [Product]? = nil

    private struct Session: Identifiable {
        let id: String
        let date: Date
        let originalCount: Int
        var items: [Product]
    }

    private var available: [Product] {
        products.filter { !$0.isFinished && $0.remainingAmount > 0 }
    }

    private var sessions: [Session] {
        var history: [String: Session] = [:]
        for p in products {
            let marks = Dictionary(grouping: p.groupedUses ?? [], by: \.date)
            for index in p.useLog.indices.suffix(8) {
                let date = p.useLog[index]
                let mark = marks[date]?.first
                let id = mark?.id.uuidString ?? "\(p.uid)-\(index)"
                history[id, default: Session(id: id, date: date, originalCount: mark?.count ?? 1, items: [])].items.append(p)
            }
        }
        return history.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    var body: some View {
        let history = sessions
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    journalCard
                    if !usedDays.isEmpty { streakStrip }
                    historyList(Array(history.prefix(8)))
                    if products.contains(where: { !$0.isFinished && $0.remainingAmount <= 0 }) {
                        Button("去藏品处理用完的产品") { coordinator.tab = .shelf }.frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .background {
                ScreenBackground(colors: Array(available.prefix(3).map(\.tint)))
            }
            .navigationTitle("使用手记")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { coordinator.editor = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加产品")
                }
            }
            // 挑完不直接记：收好弹层，进详情页一件件记（用完了会自动滑到下一件）
            .sheet(isPresented: $picking, onDismiss: openPending) {
                UsagePicker(products: available) { items in
                    pendingOpen = items
                    picking = false
                }
            }
        }
    }

    private func openPending() {
        guard let items = pendingOpen else { return }
        pendingOpen = nil
        // 等弹层彻底收好再呈现详情页：两个呈现不会撞在一起
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            openDetail(items)
        }
    }

    // MARK: 坚持（乐意一直用，是因为看得见自己在坚持）

    /// 有记录的日子
    private var usedDays: Set<Date> {
        let cal = Calendar.current
        var days = Set<Date>()
        for p in products {
            for date in p.useLog { days.insert(cal.startOfDay(for: date)) }
        }
        return days
    }

    /// 连续记录天数：今天还没记就往前数到昨天
    private var streak: Int {
        let cal = Calendar.current
        let days = usedDays
        guard !days.isEmpty else { return 0 }
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// 最近 7 天（含今天），从早到晚
    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private var weekCount: Int {
        let days = usedDays
        return weekDays.filter { days.contains($0) }.count
    }

    private var streakStrip: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(streak)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("天连续记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(weekCount > 0 ? "这周记了 \(weekCount) 天" : "这周还没记，今天记一笔？")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(weekDays, id: \.self) { day in
                    Circle()
                        .fill(usedDays.contains(day) ? Theme.sage : Color.primary.opacity(0.12))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("连续记录 \(streak) 天，这周记了 \(weekCount) 天")
    }

    /// 一件：直接打开它；多件：还是同一个详情页，几件产品像卡片一样左右滑动，一件件记
    private func openDetail(_ items: [Product]) {
        guard let first = items.first else { return }
        coordinator.openDetail(first, also: Array(items.dropFirst()))
    }

    /// 首页第一张卡：不预选任何一件。这次用了什么，由你自己挑。
    /// 右边那三个瓶子只是"你的东西"的缩影，谁都没被选中。
    private var journalCard: some View {
        let shelf = Array(available.prefix(3))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(available.isEmpty ? "还没有可记录的产品" : "这次用了哪些产品？")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(available.isEmpty
                         ? "添加第一件，之后每天点一下就好。"
                         : "从在用的 \(available.count) 件里挑，然后一件件记。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !shelf.isEmpty {
                    VStack(spacing: 0) {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(shelf) { item in
                                ProductFigure(product: item, maxPixel: 200)
                                    .frame(maxWidth: .infinity, alignment: .bottom)
                            }
                        }
                        .frame(height: typeSize.isAccessibilitySize ? 84 : 124, alignment: .bottom)
                        ShelfPlank()
                    }
                    .frame(width: 92)
                    .accessibilityHidden(true)
                }
            }

            Button {
                if available.isEmpty { coordinator.editor = .new } else { showPicker() }
            } label: {
                Label(available.isEmpty ? "添加第一件" : "挑产品，逐件记",
                      systemImage: available.isEmpty ? "plus" : "checklist")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .tint(.primary).foregroundStyle(Color(uiColor: .systemBackground))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 22)
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    @ViewBuilder private func historyList(_ entries: [Session]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("近期记录").font(.title3.weight(.semibold))
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index == 0 || !Calendar.current.isDate(entry.date, inSameDayAs: entries[index - 1].date) {
                        Text(dayLabel(entry.date)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 14)
                    }
                    HStack(spacing: 14) {
                        Text(entry.date, style: .time).monospacedDigit().foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            if entry.items.count > 1 {
                                Text("一起用了 \(entry.items.count) 件").fontWeight(.semibold)
                                Text(entry.items.map(\.name).joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                            } else { Text(entry.items.first?.name ?? "").fontWeight(.semibold) }
                        }
                        Spacer(minLength: 4)
                        if let p = entry.items.first { ProductFigure(product: p, maxPixel: 120).frame(width: 30, height: 34) }
                    }.font(.subheadline).frame(minHeight: 48).accessibilityElement(children: .combine)
                    .contentShape(Rectangle())
                    // 点一条记录 = 打开那件产品的详情，可以接着再记一次（多件记录逐件滑）
                    .onTapGesture { openDetail(entry.items) }
                    .accessibilityAddTraits(.isButton)
                    Divider()
                }
            }
        }
    }

    private func showPicker() {
        picking = true
    }
}

private struct UsagePicker: View {
    let products: [Product]
    /// 选完之后做什么：交回给首页，收好弹层再打开详情页逐件记
    let open: ([Product]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var selected: Set<UUID> = []
    @State private var scope = Scope.suggested

    private enum Scope: Hashable {
        case suggested, all, category(ProductCategory)
    }

    private let suggestionLimit = 6

    /// 勾中的产品，按列表顺序交给详情页
    private var selectedProducts: [Product] {
        products.filter { selected.contains($0.uid) }
    }

    private var enterTitle: String {
        selected.count == 1 ? "进详情，记这一件" : "进详情，逐件记这 \(selected.count) 件"
    }

    // 入参已按入库时间从新到旧排列。
    private var suggestions: (title: String, items: [Product]) {
        let pins = products.filter(\.isPinned).sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
        let recent = products.filter { !$0.useLog.isEmpty }
            .sorted { ($0.useLog.last ?? .distantPast) > ($1.useLog.last ?? .distantPast) }
        if pins.isEmpty && recent.isEmpty {
            return ("最近入库", Array(products.prefix(suggestionLimit)))
        }
        var seen = Set<UUID>()
        var items: [Product] = []
        for product in Array(pins.prefix(3)) + recent + pins where seen.insert(product.uid).inserted {
            items.append(product)
            if items.count == suggestionLimit { break }
        }
        return ("常用和最近使用", items)
    }

    private var results: (title: String, items: [Product]) {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if !words.isEmpty {
            let matches = products.filter { p in
                let label = [p.name, p.brand, p.category.rawValue].joined(separator: " ")
                return words.allSatisfy { label.localizedStandardContains($0) }
            }
            return ("搜索结果 · \(matches.count) 件", matches)
        }
        if products.count > suggestionLimit {
            if case .suggested = scope { return suggestions }
            if case let .category(category) = scope {
                return (category.rawValue, products.filter { $0.category == category })
            }
        }
        return ("全部产品", products)
    }

    var body: some View {
        let result = results
        let large = products.count > suggestionLimit
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if large || searching {
                        HStack(spacing: 8) {
                            Text(result.title).font(.subheadline.weight(.semibold))
                            if !selected.isEmpty && !searching {
                                Text("已选 \(selected.count) 件")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            Spacer(minLength: 8)
                            if large && !searching { categoryMenu }
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 40)
                    }
                    if result.items.isEmpty {
                        if searching {
                            ContentUnavailableView.search(text: query).padding(.top, 40)
                        } else {
                            Text("这里还没有产品")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(result.items) { p in tile(p) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onChange(of: products.map(\.uid)) { _, ids in
                selected.formIntersection(ids)
                if case let .category(cat) = scope, !products.contains(where: { $0.category == cat }) { scope = .suggested }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索所有产品、品牌或品类")
            .navigationTitle("这次用了哪些产品？").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .sensoryFeedback(.selection, trigger: selected.count)
        }
        .presentationDetents(products.count > 3 ? [.large] : [.medium, .large])
    }

    /// 一格 = 一件产品：实物站在一小段玻璃架上，选中的带一道描边和产品色
    private func tile(_ p: Product) -> some View {
        let on = selected.contains(p.uid)
        return Button {
            withAnimation(Theme.snappy) {
                if !selected.insert(p.uid).inserted { selected.remove(p.uid) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        ProductFigure(product: p, maxPixel: 220)
                            .frame(height: 76)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                        ShelfPlank()
                            .padding(.horizontal, 14)
                    }
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(on ? Color.primary : Color.secondary.opacity(0.5))
                        .padding(9)
                        .accessibilityHidden(true)
                }
                Text(p.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.top, 9)
                Text([p.brand, p.remainingText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.top, 2)
                    .padding(.bottom, 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 18, tint: on ? p.tint : nil, strong: on)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(on ? Color.primary.opacity(0.5) : .clear, lineWidth: 1.5)
            }
            .scaleEffect(on ? 0.98 : 1)
            .animation(Theme.snappy, value: on)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.name)，\([p.brand, p.remainingText].filter { !$0.isEmpty }.joined(separator: "，"))")
        .accessibilityValue(on ? "已选中" : "未选中")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 大字号时一排放两格，字才有地方（ROADMAP B9）
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.adaptive(minimum: 104, maximum: 168), spacing: 12)]
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button {
                let items = selectedProducts
                guard !items.isEmpty else { return }
                // 不在这里直接记：交回首页，收起弹层后进详情页，一件一件地记
                open(items)
                dismiss()
            } label: {
                Text(selected.isEmpty ? "挑一件，或者几件一起" : enterTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .tint(.primary).foregroundStyle(Color(uiColor: .systemBackground))
            .disabled(selected.isEmpty)

            if selected.isEmpty {
                Text("勾选后进入详情页，一件件记；记完可以撤销。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var categoryMenu: some View {
        Menu {
            Picker("浏览范围", selection: $scope) {
                Text(products.contains { $0.isPinned || !$0.useLog.isEmpty } ? "常用和最近使用" : "最近入库").tag(Scope.suggested)
                Text("全部产品（\(products.count)）").tag(Scope.all)
                ForEach(ProductCategory.allCases) { category in
                    let count = products.filter { $0.category == category }.count
                    if count > 0 { Text("\(category.rawValue)（\(count)）").tag(Scope.category(category)) }
                }
            }
        } label: { Label("按品类找", systemImage: "square.grid.2x2").font(.subheadline).frame(minHeight: 44) }
    }
}
