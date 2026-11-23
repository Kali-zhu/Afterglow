import SwiftUI
import SwiftData

/// 今日（首页）·「一束光」：黑白经典，一束光从上方打在台面上。
/// 左上大号衬线问候 + 一句建议；台面上站着用户挑的常用产品。
/// 轻点瓶子 = 记一次（弹一下、+1、底部可撤销）；长按台面 = 整理（晃动、× 收进抽屉、从藏品添加）；
/// 底部一个主按钮：早间 / 晚间照常用一遍。
struct TodayView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.createdAt) private var all: [Product]
    @Namespace private var ns
    @State private var selected: Product? = nil
    @State private var picking = false
    @State private var editing = false
    @State private var popID: UUID? = nil
    @State private var plusID: UUID? = nil
    @State private var toast: Toast? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    struct Toast: Equatable { let id = UUID(); let text: String; let products: [Product]
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id } }

    private var active: [Product] { all.filter { !$0.isFinished } }
    private var pinned: [Product] {
        active.filter(\.isPinned).sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }
    private var usedCount: Int { pinned.filter(\.usedToday).count }
    private var slot: RoutineSlot { Calendar.current.component(.hour, from: .now) < 15 ? .morning : .evening }
    /// 照常用一遍的范围：标了当前时段流程的常用品；一个都没标就是全部常用
    private var routine: [Product] {
        let r = pinned.filter { $0.inRoutine(slot) }
        return r.isEmpty ? pinned : r
    }
    private var routineDone: Int { routine.filter(\.usedToday).count }
    private var allDone: Bool { !routine.isEmpty && routineDone == routine.count }

    /// 建议：昨天用过、今天还没用的；否则最久没用的那件
    private var suggestion: (Product, String)? {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        let todo = pinned.filter { !$0.usedToday }
        if let p = todo.first(where: { $0.used(on: yesterday) }) { return (p, "昨天用过") }
        let byLast = todo.sorted { ($0.useLog.last ?? .distantPast) < ($1.useLog.last ?? .distantPast) }
        if let p = byLast.first { return (p, p.useLog.isEmpty ? "还没用过" : "好久没用") }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Self.bg.ignoresSafeArea()
                Beam().ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    if pinned.isEmpty && !editing {
                        greetingBlock.padding(.top, 36)
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        greetingBlock.padding(.top, 36)
                        Spacer(minLength: 16)
                        table
                        bottom.padding(.top, 18)
                    }
                }
                .padding(.bottom, 14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $picking) { PinPickerView().environment(coordinator) }
        }
        .modifier(DetailPresenter(selected: $selected, ns: ns, coordinator: coordinator, context: context))
        .task { migratePins() }
    }

    static let bg = Color(light: "F6F5F3", dark: "0B0B0C")
    static let ink = Color(light: "141414", dark: "F2F1EE")
    static let serif = "Songti SC"

    // MARK: 顶部：日期 + 设置

    private var topBar: some View {
        HStack {
            Text(dateLine)
                .font(.custom("Times New Roman", size: 13))
                .tracking(2.6)
                .foregroundStyle(.secondary)
            Spacer()
            Button { coordinator.showSettings = true } label: {
                Image(systemName: "person")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Self.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE · MM.dd"
        return f.string(from: .now).uppercased()
    }

    // MARK: 问候

    private var phrase: (en: String, hi: String, big: String) {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<9: return ("GOOD MORNING", "早上好", "阳光明媚")
        case 9..<12: return ("GOOD MORNING", "上午好", "元气满满")
        case 12..<14: return ("GOOD NOON", "中午好", "歇一会儿")
        case 14..<18: return ("GOOD AFTERNOON", "下午好", "补个妆吧")
        case 18..<22: return ("GOOD EVENING", "晚上好", "卸下一天")
        default: return ("GOOD NIGHT", "夜深了", "好好睡觉")
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(phrase.en)
                .font(.custom("Times New Roman", size: 12))
                .tracking(3.2)
                .foregroundStyle(.secondary)
            Text(phrase.hi)
                .font(.custom(Self.serif, size: 19))
                .foregroundStyle(Self.ink.opacity(0.8))
                .padding(.top, 20)
            Text(phrase.big)
                .font(.custom(Self.serif, size: 46).weight(.bold))
                .foregroundStyle(Self.ink)
                .padding(.top, 4)
            suggestionLine.padding(.top, 14)
            Rectangle().fill(Self.ink).frame(width: 22, height: 1.5).padding(.top, 22)
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder private var suggestionLine: some View {
        if allDone {
            Text("\(slot.title)都用好了，今天也很棒～").font(.system(size: 15)).foregroundStyle(.secondary)
        } else if let s = suggestion {
            (Text(slot == .morning ? "要不要用一下" : "今晚试试")
             + Text(s.0.name).fontWeight(.semibold).underline()
             + Text("～"))
                .font(.system(size: 15))
                .foregroundStyle(Self.ink.opacity(0.75))
                .lineLimit(1)
        } else {
            Text("把每天会用的几件摆上台面吧").font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }

    // MARK: 台面

    private var table: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(pinned) { p in item(p) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 34)
                .frame(minWidth: UIScreen.main.bounds.width, alignment: .center)
            }
            .scrollDisabled(pinned.count <= 6)
            // 台面
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(light: "FFFFFF", dark: "2A2A2C"), Color(light: "ECEAE6", dark: "1A1A1C")],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 14)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 4)
                // 抽屉
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(light: "F1EFEC", dark: "151517"))
                    .frame(height: 62)
                    .overlay(HStack(spacing: 90) {
                        Capsule().fill(Self.ink).frame(width: 22, height: 2.5)
                        Capsule().fill(Self.ink).frame(width: 22, height: 2.5)
                    })
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) { enterEdit() }
        }
    }

    private func item(_ p: Product) -> some View {
        let used = p.usedToday
        let tag: String? = (!editing && suggestion?.0.id == p.id) ? suggestion?.1 : nil
        return VStack(spacing: 8) {
            ZStack(alignment: .top) {
                ProductFigure(product: p, maxPixel: 400)
                    .frame(height: 112 * max(0.55, p.shelfScale))
                    .frame(width: 50, height: 120, alignment: .bottom)
                    .modifier(LiftSource(id: p.uid, ns: ns, isSource: selected?.id != p.id))
                    .scaleEffect(popID == p.uid ? 1.12 : 1, anchor: .bottom)
                    .rotationEffect(.degrees(editing ? (p.uid.hashValue % 2 == 0 ? 2.2 : -2.2) : 0), anchor: .bottom)
                    .animation(editing ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default, value: editing)
                if let tag {
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Self.bg)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Self.ink))
                        .fixedSize()
                        .offset(y: -30)
                        .transition(.opacity)
                }
                if plusID == p.uid {
                    Text("+1").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Self.ink)
                        .offset(y: -30)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { withAnimation(Theme.spring) { p.togglePin() }; coordinator.dataChanged() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(hex: "141414")))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .offset(x: -12, y: -4)
                    .accessibilityLabel("把\(p.name)收进抽屉")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            Circle().fill(Self.ink).frame(width: 5, height: 5).opacity(used ? 1 : 0)
        }
        .frame(width: 52)
        .contentShape(Rectangle())
        .onTapGesture { if editing { selected = p } else { tap(p) } }
        .onLongPressGesture(minimumDuration: 0.45) { enterEdit() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.name)
        .accessibilityValue("\(p.remainingText)\(used ? "，今天用过" : "")")
        .accessibilityHint(editing ? "轻点查看详情" : "轻点记一次，长按整理台面")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 底部

    @ViewBuilder private var bottom: some View {
        VStack(spacing: 14) {
            ZStack {
                if let toast {
                    HStack(spacing: 14) {
                        Text(toast.text).font(.system(size: 14))
                        Button("撤销") { undo(toast) }.font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 38)
                    .background(Capsule().fill(Color(hex: "141414")))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text(editing ? "点 × 收进抽屉 · 点瓶子看详情" : "轻点瓶子记一次  ·  今天用了 \(usedCount) 件")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .frame(height: 38)

            if editing {
                HStack(spacing: 12) {
                    Button { picking = true } label: {
                        Label("从藏品添加", systemImage: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Self.ink)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 1.2))
                    }
                    Button { withAnimation(Theme.spring) { editing = false } } label: {
                        Text("完成").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Self.bg)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Capsule().fill(Self.ink))
                    }
                }
            } else {
                Button { useAll() } label: {
                    HStack(spacing: 10) {
                        if allDone {
                            Image(systemName: "checkmark")
                            Text("\(slot.title)都用好了")
                        } else {
                            Text("\(slot.title)照常用一遍")
                            Text("\(routineDone) / \(routine.count)").opacity(0.5).contentTransition(.numericText())
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(allDone ? Color.white : Self.bg)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(allDone ? Color.gray.opacity(0.55) : Self.ink))
                }
                .disabled(allDone)
            }
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("台面还空着").font(.custom(Self.serif, size: 20).weight(.semibold)).foregroundStyle(Self.ink)
            Text("把每天会用的几件摆上来，以后点一下瓶子就记一次。")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { picking = true } label: {
                Label("从藏品挑几件", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.bg)
                    .padding(.horizontal, 26).frame(minHeight: 50)
                    .background(Capsule().fill(Self.ink))
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
    }

    // MARK: 动作

    private func enterEdit() {
        guard !editing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(Theme.spring) { editing = true; toast = nil }
    }

    private func tap(_ p: Product) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        coordinator.logUse(p)
        withAnimation(Theme.snappy) { popID = p.uid; plusID = p.uid }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(Theme.springBack) { popID = nil }
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.25)) { if plusID == p.uid { plusID = nil } }
        }
        show(Toast(text: "记好了 · \(p.name) 第 \(p.useCount) 次", products: [p]))
    }

    private func useAll() {
        let todo = routine.filter { !$0.usedToday }
        guard !todo.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(Theme.spring) {
            for p in todo { coordinator.logRoutine(p, slot) }
        }
        show(Toast(text: "记好了 · \(todo.count) 件各用一次", products: todo))
    }

    private func undo(_ t: Toast) {
        withAnimation(Theme.spring) {
            for p in t.products where !p.isFinished {
                if p.isDone(slot) { p.undoRoutine(slot) } else { p.undoLastUse() }
            }
            toast = nil
        }
        coordinator.dataChanged()
    }

    private func show(_ t: Toast) {
        toastTask?.cancel()
        withAnimation(Theme.spring) { toast = t }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.spring) { if toast == t { toast = nil } }
        }
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
}

/// 一束光：从屏幕上方斜照到台面的柔和光柱
private struct Beam: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.30, y: 0))
                path.addLine(to: CGPoint(x: w * 0.70, y: 0))
                path.addLine(to: CGPoint(x: w * 1.05, y: h * 0.72))
                path.addLine(to: CGPoint(x: -w * 0.05, y: h * 0.72))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.75),
                                          Color.white.opacity(scheme == .dark ? 0.03 : 0.25),
                                          Color.white.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .blur(radius: 18)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
