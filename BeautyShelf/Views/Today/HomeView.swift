import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]
    @State private var picking = false
    @State private var receipt: [Change] = []
    @State private var confirming = false
    @State private var saveError = false

    private struct UsageState: Equatable {
        let remaining: Double
        let opened: Date?
        let count: Int
        let log: [Date]
        let groups: [UsageGroupMark]?

        init(_ p: Product) {
            remaining = p.remainingAmount
            opened = p.openedDate
            count = p.useCount
            log = p.useLog
            groups = p.groupedUses
        }

        func apply(to p: Product) {
            p.remainingAmount = remaining
            p.openedDate = opened
            p.useCount = count
            p.useLog = log
            p.groupedUses = groups
        }
    }

    private struct Change {
        let id: UUID
        let before: UsageState
        let after: UsageState
    }

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

    private func featured(in history: [Session]) -> [Product] {
        for session in history {
            let usable = session.items.filter { !$0.isFinished && $0.remainingAmount > 0 }
            if usable.count == session.originalCount { return usable }
            if let first = usable.first { return [first] }
        }
        return available.count == 1 ? available : []
    }

    private var undoTargets: [Product] {
        let targets = receipt.compactMap { change in
            products.first { $0.uid == change.id && !$0.isFinished && UsageState($0) == change.after }
        }
        return targets.count == receipt.count ? targets : []
    }

    var body: some View {
        let history = sessions
        let featuredItems = featured(in: history)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 4) {
                        journalCard(featuredItems)
                        if !featuredItems.isEmpty && available.count > 1 {
                            Button(action: showPicker) { Label("换一件或记多件", systemImage: "checklist") }
                                .font(.subheadline).frame(minHeight: 44)
                        }
                    }
                    historyList(Array(history.prefix(8)))
                    if products.contains(where: { !$0.isFinished && $0.remainingAmount <= 0 }) {
                        Button("去藏品处理用完的产品") { coordinator.tab = .shelf }.frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("使用手记")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { coordinator.editor = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加产品")
                }
            }
            .sheet(isPresented: $picking) {
                UsagePicker(products: available, record: record)
            }
            .alert("记录未能保存，请重试", isPresented: $saveError) { Button("好") {} }
            .task(id: receipt.first?.after.log.last) {
                guard confirming else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                if !Task.isCancelled { confirming = false }
            }
        }
    }

    private func action(for items: [Product]) -> (title: String, symbol: String) {
        if items.count > 1 { return ("再记这 \(items.count) 件", "arrow.clockwise") }
        if let p = items.first { return p.useLog.isEmpty ? ("用了一次", "drop") : ("再记一次", "arrow.clockwise") }
        return available.isEmpty ? ("添加产品", "plus") : ("记下用过的产品", "checklist")
    }

    private func journalCard(_ items: [Product]) -> some View {
        let recorded = undoTargets
        let justRecorded = confirming && recorded.contains { $0.uid == items.first?.uid }
        let button = action(for: items)
        return VStack(alignment: .leading, spacing: 16) {
            if let p = items.first {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(p.useLog.isEmpty ? "在用的产品" : "最近用过").font(.subheadline).foregroundStyle(.secondary)
                        if let date = p.useLog.last {
                            Text("\(dayLabel(date))　\(date.formatted(date: .omitted, time: .shortened))")
                                .font(.headline).monospacedDigit().padding(.bottom, 10)
                        }
                        Text(items.count > 1 ? "一起用了 \(items.count) 件" : p.name).font(.title2.bold())
                        Text(items.count > 1 ? items.map(\.name).joined(separator: "、") :
                                [p.brand, p.remainingText].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 0) {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(items.prefix(3))) { item in
                                ProductFigure(product: item).frame(maxWidth: .infinity, alignment: .bottom)
                            }
                        }.frame(height: items.count > 1 ? 100 : 140, alignment: .bottom)
                        ShelfPlank()
                    }.frame(width: 98).accessibilityHidden(true)
                }
            } else {
                Text(available.isEmpty ? "还没有可记录的产品" : "这次用了哪些产品？").font(.title2.bold())
            }
            Button {
                if !items.isEmpty { record(items) }
                else if available.isEmpty { coordinator.editor = .new }
                else { showPicker() }
            } label: {
                Label(justRecorded ? "已记下" : button.title, systemImage: justRecorded ? "checkmark" : button.symbol)
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .tint(.primary).foregroundStyle(Color(uiColor: .systemBackground)).disabled(justRecorded)
            if let first = recorded.first {
                HStack {
                    Text(recorded.count > 1 ? "已记录 \(recorded.count) 件，各一次" : "\(first.name)已记一次")
                        .font(.subheadline)
                    Spacer()
                    Button { undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }.frame(minHeight: 44)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
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
                    Divider()
                }
            }
        }
    }

    private func showPicker() {
        picking = true
    }

    @discardableResult private func record(_ items: [Product]) -> Bool {
        guard !items.isEmpty, items.allSatisfy({ !$0.isFinished && $0.remainingAmount > 0 }) else { return false }
        let date = Date.now
        let group = items.count > 1 ? UsageGroupMark(id: UUID(), date: date, count: items.count) : nil
        let changes = items.map { p in
            let before = UsageState(p)
            p.logUse(at: date, group: group)
            return Change(id: p.uid, before: before, after: UsageState(p))
        }
        do { try context.save() } catch {
            for (p, change) in zip(items, changes) { change.before.apply(to: p) }
            if !picking { saveError = true }
            return false
        }
        receipt = changes
        confirming = true
        coordinator.dataChanged()
        return true
    }

    private func undo() {
        let targets = undoTargets
        guard !targets.isEmpty else { return }
        for (p, change) in zip(targets, receipt) { change.before.apply(to: p) }
        do { try context.save() } catch {
            for (p, change) in zip(targets, receipt) { change.after.apply(to: p) }
            saveError = true
            return
        }
        receipt.removeAll()
        confirming = false
        coordinator.dataChanged()
    }
}

private struct UsagePicker: View {
    let products: [Product]
    let record: ([Product]) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Set<UUID> = []
    @State private var scope = Scope.suggested
    @State private var saveError = false

    private enum Scope: Hashable {
        case suggested, all, category(ProductCategory)
    }

    private let suggestionLimit = 6

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
            VStack(spacing: 0) {
                if large || searching {
                    HStack {
                        Text(result.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        if large && !searching { categoryMenu }
                    }.padding(.horizontal, 20).frame(minHeight: 44)
                }
                List(result.items) { p in
                    Button {
                        if !selected.insert(p.uid).inserted { selected.remove(p.uid) }
                    } label: {
                        HStack {
                            ProductFigure(product: p, maxPixel: 120).frame(width: 32, height: 38)
                            VStack(alignment: .leading) {
                                Text(p.name).foregroundStyle(.primary)
                                Text([p.brand, p.remainingText].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selected.contains(p.uid) ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large).accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }.accessibilityAddTraits(selected.contains(p.uid) ? .isSelected : [])
                }
                .listStyle(.plain)
                .overlay { if result.items.isEmpty && searching { ContentUnavailableView.search(text: query) } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let items = products.filter { selected.contains($0.uid) }
                    guard !items.isEmpty, items.count == selected.count else { return }
                    if record(items) { dismiss() } else { saveError = true }
                } label: {
                    Text(selected.isEmpty ? "请选择产品" : "记录 \(selected.count) 件，各一次")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(.primary).foregroundStyle(Color(uiColor: .systemBackground)).disabled(selected.isEmpty)
                .padding(.horizontal).padding(.vertical, 6).background(.bar)
            }
            .onChange(of: products.map(\.uid)) { _, ids in
                selected.formIntersection(ids)
                if case let .category(cat) = scope, !products.contains(where: { $0.category == cat }) { scope = .suggested }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索所有产品、品牌或品类")
            .navigationTitle("这次用了哪些产品？").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .presentationDetents(large ? [.large] : [.medium, .large])
        .alert("记录未能保存，请重试", isPresented: $saveError) { Button("好") {} }
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
