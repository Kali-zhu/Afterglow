import SwiftUI
import SwiftData

/// 今日：早间 / 晚间两段清单，点圆圈 = 记一次使用；全部完成时进度环合拢。
struct TodayView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \Product.createdAt) private var all: [Product]
    @State private var picking: RoutineSlot? = nil

    private func items(_ slot: RoutineSlot) -> [Product] {
        all.filter { !$0.isFinished && $0.inRoutine(slot) }
    }

    private var totalSteps: Int { items(.morning).count + items(.evening).count }
    private var doneSteps: Int {
        items(.morning).filter { $0.isDone(.morning) }.count + items(.evening).filter { $0.isDone(.evening) }.count
    }
    private var progress: Double { totalSteps == 0 ? 0 : Double(doneSteps) / Double(totalSteps) }
    private var allDone: Bool { totalSteps > 0 && doneSteps == totalSteps }

    /// 晚上把晚间流程放在前面
    private var slots: [RoutineSlot] {
        Calendar.current.component(.hour, from: .now) >= 17 ? [.evening, .morning] : [.morning, .evening]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))

                ForEach(slots) { slot in
                    routineSection(slot)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.porcelain.ignoresSafeArea())
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            }
            .sheet(item: $picking) { slot in
                RoutinePickerView(slot: slot)
            }
        }
        .sensoryFeedback(.success, trigger: allDone) { old, new in !old && new }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: progress)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if totalSteps == 0 { return "还没有护肤流程" }
        if allDone { return "今天的流程都完成了" }
        return "今天完成 \(doneSteps) / \(totalSteps)"
    }

    private var subline: String {
        if totalSteps == 0 { return "把每天用的产品加进早间、晚间，之后点一下就记好了。" }
        if allDone { return "明天见。" }
        return "点圆圈记一次使用，再点一次可以撤销。"
    }

    private func routineSection(_ slot: RoutineSlot) -> some View {
        let list = items(slot)
        let done = list.filter { $0.isDone(slot) }.count
        return Section {
            if list.isEmpty {
                Button { picking = slot } label: {
                    Label("从妆台挑选\(slot.title)用的产品", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                }
            } else {
                ForEach(list) { p in
                    RoutineRow(product: p, slot: slot) {
                        withAnimation(Theme.spring) {
                            if p.isDone(slot) {
                                p.undoRoutine(slot)
                            } else {
                                coordinator.logRoutine(p, slot)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("移出", systemImage: "minus.circle") {
                            withAnimation { p.setRoutine(slot, false) }
                        }
                        .tint(.gray)
                    }
                }
            }
        } header: {
            HStack {
                Label(slot.title, systemImage: slot.symbol)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !list.isEmpty {
                    Text("\(done)/\(list.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("调整") { picking = slot }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityLabel("调整\(slot.title)流程")
            }
            .textCase(nil)
        }
    }
}

/// 流程里的一行：圆圈（≥44pt）+ 小容器 + 名称
struct RoutineRow: View {
    let product: Product
    let slot: RoutineSlot
    let toggle: () -> Void
    @State var drops = 0

    private var done: Bool { product.isDone(slot) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if !done { drops += 1 }
                toggle()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 2)
                    if done {
                        Circle().fill(product.tint)
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(product.name)
            .accessibilityValue(done ? "今天已记录" : "未记录")
            .accessibilityHint(done ? "轻点撤销这次记录" : "轻点记一次使用")
            .sensoryFeedback(.impact(weight: .medium), trigger: drops)

            ZStack(alignment: .top) {
                ContainerView(product: product, slosh: drops, animated: false)
                    .frame(width: 28, height: 46)
                FallingDrop(tint: product.tint, trigger: drops, distance: 26, size: 7)
                    .offset(y: -14)
            }
            .frame(width: 34, height: 50)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Text(product.brand.isEmpty ? product.remainingText : "\(product.brand) · \(product.remainingText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if product.expiryState != .fresh {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(product.expiryState.color)
                    .accessibilityLabel(product.expiryText)
            }
        }
    }
}

/// 从妆台挑选早间 / 晚间流程里的产品
struct RoutinePickerView: View {
    let slot: RoutineSlot
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.createdAt) private var all: [Product]

    init(slot: RoutineSlot) {
        self.slot = slot
    }

    private var active: [Product] {
        all.filter { !$0.isFinished }.sorted { ($0.category.order, $0.createdAt) < ($1.category.order, $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                if active.isEmpty {
                    Text("妆台上还没有产品。").foregroundStyle(.secondary)
                }
                ForEach(active) { p in
                    Toggle(isOn: Binding(get: { p.inRoutine(slot) }, set: { p.setRoutine(slot, $0) })) {
                        HStack(spacing: 12) {
                            ContainerView(product: p, animated: false)
                                .frame(width: 24, height: 40)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                if !p.brand.isEmpty {
                                    Text(p.brand).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("\(slot.title)流程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
