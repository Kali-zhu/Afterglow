import SwiftUI
import UIKit

/// 第 3 步：一张紧凑的确认卡。新增时只露出最关键的几项，其余收在「更多」；编辑时全部展开。
struct ProductConfirmCard: View {
    @Binding var d: ProductDraft
    let isEditing: Bool
    let photoImage: UIImage?
    let cutoutImage: UIImage?
    let namespace: Namespace.ID
    let matchEnabled: Bool
    let recutStatus: String?
    let isRecutting: Bool
    let onRetake: () -> Void
    let onRecut: () -> Void
    let onUseOriginal: () -> Void
    let onSave: () -> Void

    enum ChipField: Hashable { case expiry, pao, capacity }

    @State private var editing: ChipField? = nil
    @State private var showMore: Bool
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var previewHeight: CGFloat = 200

    init(d: Binding<ProductDraft>, isEditing: Bool, photoImage: UIImage?, cutoutImage: UIImage?,
         namespace: Namespace.ID, matchEnabled: Bool, recutStatus: String?, isRecutting: Bool,
         onRetake: @escaping () -> Void, onRecut: @escaping () -> Void,
         onUseOriginal: @escaping () -> Void, onSave: @escaping () -> Void) {
        _d = d
        self.isEditing = isEditing
        self.photoImage = photoImage
        self.cutoutImage = cutoutImage
        self.namespace = namespace
        self.matchEnabled = matchEnabled
        self.recutStatus = recutStatus
        self.isRecutting = isRecutting
        self.onRetake = onRetake
        self.onRecut = onRecut
        self.onUseOriginal = onUseOriginal
        self.onSave = onSave
        _showMore = State(initialValue: isEditing)
    }

    private var motion: Animation { reduceMotion ? EditorMotion.fade : EditorMotion.spring }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                preview
                mediaActions
                nameCard
                detectedCard
                kindCard
                if isEditing { remainingCard }
                moreCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task {
            guard !isEditing else { return }
            // 等卡片落定再弹键盘，免得打断"飞过来"的动画
            try? await Task.sleep(for: .milliseconds(450))
            nameFocused = true
        }
    }

    // MARK: 预览

    private var previewLevel: Double {
        switch d.mode {
        case .estimate: return d.remaining / 100
        case .volume, .count: return d.total > 0 ? min(1, d.remaining / d.total) : 0.7
        }
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            // 和架上同一套东西：接触阴影 + 玻璃架板，看上去已经站在妆台上了
            ShelfPlank()
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            ContactShadow(width: 110)
                .offset(y: -(ShelfPlank.height) + 2)
                .accessibilityHidden(true)

            Group {
                if let cut = cutoutImage {
                    Image(uiImage: cut)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: previewHeight)
                        .subjectMatch(namespace, enabled: matchEnabled && !reduceMotion)
                        .shadow(color: .black.opacity(0.22), radius: 14, y: 10)
                } else if let photo = photoImage {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: previewHeight * 0.85, height: previewHeight * 0.85)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                } else {
                    // 没有照片：形状插画兜底
                    ContainerView(kind: d.kind, level: previewLevel, tint: Color(hex: d.tint), animated: false)
                        .frame(width: previewHeight * 0.48, height: previewHeight * 0.8)
                }
            }
            .padding(.bottom, 8 + ShelfPlank.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: previewHeight + 16 + ShelfPlank.height)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cutoutImage != nil ? "抠好的产品照片" : (photoImage != nil ? "产品照片" : "\(d.kind.title)的形状插画"))
    }

    @ViewBuilder
    private var mediaActions: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if photoImage != nil {
                    smallButton("重新拍照", "camera", action: onRetake)
                    smallButton("重新抠图", "wand.and.stars", action: onRecut)
                        .disabled(isRecutting)
                        .accessibilityHint("换一种抠法：全部主体或其中一个")
                    if cutoutImage != nil {
                        smallButton("用原图", "photo", action: onUseOriginal)
                    }
                } else {
                    smallButton("拍一张", "camera", action: onRetake)
                }
            }
            if isRecutting {
                ProgressView().controlSize(.small)
            } else if let recutStatus {
                Text(recutStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    private func smallButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 名称 / 品牌

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("名称，例如 小棕瓶精华", text: $d.name)
                .font(.title3.weight(.semibold))
                .focused($nameFocused)
                .submitLabel(.done)
                .frame(minHeight: 48)
                .accessibilityLabel("名称（必填）")
            Divider()
            TextField("品牌", text: $d.brand)
                .frame(minHeight: 44)
                .accessibilityLabel("品牌")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .editorCard()
    }

    // MARK: 识别到的胶囊

    private var detectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorFlowLayout(spacing: 8) {
                DetectedChip(title: expiryChipTitle, systemImage: "calendar",
                             style: d.detectedExpiry != nil ? .detected : (d.expTouched ? .set : .placeholder),
                             isActive: editing == .expiry) { toggle(.expiry) }
                    .accessibilityLabel("到期日，\(expiryChipTitle)")
                    .accessibilityHint("轻点修改")
                DetectedChip(title: paoChipTitle, systemImage: "hourglass",
                             style: d.detectedPAO ? .detected : (d.paoTouched ? .set : .placeholder),
                             isActive: editing == .pao) { toggle(.pao) }
                    .accessibilityLabel(paoAccessibility)
                    .accessibilityHint("轻点修改")
                if d.mode != .estimate {
                    DetectedChip(title: capacityChipTitle, systemImage: d.mode == .count ? "square.stack" : "drop",
                                 style: d.detectedCapacity ? .detected : (d.capacityTouched ? .set : .placeholder),
                                 isActive: editing == .capacity) { toggle(.capacity) }
                        .accessibilityLabel("容量，\(capacityChipTitle)")
                        .accessibilityHint("轻点修改")
                }
            }

            if let editing {
                Group {
                    switch editing {
                    case .expiry: expiryEditor
                    case .pao: paoEditor
                    case .capacity: capacityEditor
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            expirySummary
        }
        .padding(16)
        .editorCard()
    }

    private func toggle(_ f: ChipField) {
        withAnimation(motion) { editing = editing == f ? nil : f }
    }

    private var expiryChipTitle: String {
        if let det = d.detectedExpiry { return "EXP \(det.text)" }
        if d.expTouched {
            switch d.exp {
            case .years(let n): return "EXP \(n) 年后"
            case .custom: return "EXP \(EditorFmt.month(d.expDate))"
            }
        }
        return "到期日 · 约 2 年"
    }

    private var paoAccessibility: String {
        if let m = d.pao { return "开封后保质期，\(m) 个月" }
        return "开封后保质期，未填"
    }

    private var paoChipTitle: String {
        guard let m = d.pao else { return "开封后保质 · 不清楚" }
        return "开封后 \(m)M"
    }

    private var capacityChipTitle: String {
        switch d.mode {
        case .count: return "\(Int(d.total.rounded())) 片"
        case .volume, .estimate: return "\(EditorFmt.amount(d.total)) \(d.unit)"
        }
    }

    // 到期日编辑
    private var expiryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("包装上的到期日（EXP）").font(.subheadline).foregroundStyle(.secondary)
            EditorFlowLayout(spacing: 8) {
                ForEach([1, 2, 3], id: \.self) { n in
                    EditorChip(title: "\(n) 年后", isOn: d.exp == .years(n) && d.expTouched) {
                        d.exp = .years(n)
                        d.expTouched = true
                        d.detectedExpiry = nil
                    }
                }
            }
            DatePicker("到期日", selection: Binding(
                get: { d.expValue },
                set: { new in
                    if let det = d.detectedExpiry, let detDate = det.date,
                       !Calendar.current.isDate(detDate, inSameDayAs: new) {
                        d.detectedExpiry = nil
                    }
                    d.exp = .custom
                    d.expDate = new
                    d.expTouched = true
                }), displayedComponents: .date)
                .frame(minHeight: 44)
        }
    }

    // 开封后保质期编辑
    private var paoEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开罐图标上的数字（6M = 开封后 6 个月）").font(.subheadline).foregroundStyle(.secondary)
            EditorFlowLayout(spacing: 8) {
                ForEach([3, 6, 12, 18, 24, 36], id: \.self) { m in
                    EditorChip(title: "\(m)M", isOn: d.pao == m) {
                        d.pao = m
                        d.paoTouched = true
                        d.detectedPAO = false
                    }
                    .accessibilityLabel("开封后 \(m) 个月")
                }
                EditorChip(title: "不清楚", isOn: d.pao == nil) {
                    d.pao = nil
                    d.paoTouched = true
                    d.detectedPAO = false
                }
            }
        }
    }

    private var totalBinding: Binding<Double> {
        Binding(get: { d.total }, set: { v in
            d.changeTotal(v)
            d.capacityTouched = true
            d.detectedCapacity = false
        })
    }

    // 容量编辑
    @ViewBuilder
    private var capacityEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if d.mode == .count {
                EditorFlowLayout(spacing: 8) {
                    ForEach(d.kind.quickTotals, id: \.self) { v in
                        EditorChip(title: "\(Int(v)) 片", isOn: d.total == v) { totalBinding.wrappedValue = v }
                    }
                }
                Stepper(value: totalBinding, in: 1...200, step: 1) {
                    Text("共 \(Int(d.total)) 片").monospacedDigit()
                }
                .frame(minHeight: 44)
            } else {
                EditorFlowLayout(spacing: 8) {
                    ForEach(d.kind.quickTotals, id: \.self) { v in
                        EditorChip(title: "\(EditorFmt.amount(v)) \(d.unit)", isOn: d.total == v) { totalBinding.wrappedValue = v }
                    }
                }
                Stepper(value: totalBinding, in: 1...1000, step: d.total < 30 ? 1 : 5) {
                    Text("总量 \(EditorFmt.amount(d.total)) \(d.unit)").monospacedDigit()
                }
                .frame(minHeight: 44)
                Picker("单位", selection: Binding(get: { d.unit }, set: { d.unit = $0; d.capacityTouched = true })) {
                    Text("ml").tag("ml")
                    Text("g").tag("g")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var expirySummary: some View {
        let r = Product.computeExpiry(exp: d.expValue, opened: d.openedValue, pao: d.pao)
        let days = Product.days(until: r.date)
        let state = Product.state(forDays: days)
        var text = days < 0
            ? "已在 \(EditorFmt.day(r.date)) 过期（\(r.basis.text)）"
            : "会在 \(EditorFmt.day(r.date)) 过期（\(r.basis.text)）"
        if d.openedValue == nil, let m = d.pao {
            text += "。开封后 \(m) 个月内用完，第一次记录使用时自动算开封"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            Text(text)
                .font(.footnote)
                .foregroundStyle(state == .fresh ? Color.secondary : state.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 形状 / 分类

    private var categoryBinding: Binding<ProductCategory> {
        Binding(get: { d.category }, set: { c in withAnimation(motion) { d.changeCategory(to: c) } })
    }

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("形状").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("分类", selection: categoryBinding) {
                        ForEach(ProductCategory.allCases) { c in
                            Label(c.rawValue, systemImage: c.symbol).tag(c)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: d.category.symbol)
                        Text(d.category.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("分类，\(d.category.rawValue)")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(VesselKind.allCases) { k in
                        EditorChip(title: k.title, isOn: d.kind == k) {
                            withAnimation(motion) { d.changeKind(to: k, isEditing: isEditing) }
                        }
                        .accessibilityLabel("\(k.title)，\(k.examples)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .editorCard()
    }

    // MARK: 剩余量

    private var remainingBinding: Binding<Double> {
        Binding(get: { d.remaining }, set: { d.remaining = $0; d.remainingTouched = true })
    }

    @ViewBuilder
    private var remainingControl: some View {
        switch d.mode {
        case .volume:
            VStack(alignment: .leading, spacing: 4) {
                Text("现在剩 \(EditorFmt.amount(d.remaining)) \(d.unit)").monospacedDigit()
                Slider(value: remainingBinding, in: 0...max(d.total, 1))
                    .accessibilityLabel("现在剩余")
                    .accessibilityValue("\(EditorFmt.amount(d.remaining)) \(d.unit)")
            }
        case .count:
            Stepper(value: remainingBinding, in: 0...max(d.total, 1), step: 1) {
                Text("现在剩 \(Int(d.remaining)) 片").monospacedDigit()
            }
            .frame(minHeight: 44)
        case .estimate:
            VStack(alignment: .leading, spacing: 4) {
                Text("估算还剩 \(Int(d.remaining))%").monospacedDigit()
                Slider(value: remainingBinding, in: 0...100, step: 5)
                    .accessibilityLabel("估算剩余")
                    .accessibilityValue("\(Int(d.remaining))%")
            }
        }
    }

    private var remainingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("剩余").font(.subheadline).foregroundStyle(.secondary)
            remainingControl
        }
        .padding(16)
        .editorCard()
    }

    // MARK: 更多

    private var moreCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(motion) { showMore.toggle() }
            } label: {
                HStack {
                    Text("更多").font(.body.weight(.medium))
                    Spacer()
                    Text(showMore ? "" : "价格、备用、流程、开封日期、外观")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多")
            .accessibilityValue(showMore ? "已展开" : "已收起")

            if showMore {
                VStack(alignment: .leading, spacing: 16) {
                    if !isEditing {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("剩余").font(.subheadline).foregroundStyle(.secondary)
                            remainingControl
                        }
                    }
                    openedSection
                    if d.mode == .volume { perUseSection }
                    priceAndBackup
                    routineToggles
                    appearanceSection
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .editorCard()
    }

    private var openedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开封了吗？").font(.subheadline).foregroundStyle(.secondary)
            EditorFlowLayout(spacing: 8) {
                EditorChip(title: "还没开", isOn: d.opened == .notYet) { d.opened = .notYet }
                EditorChip(title: "今天开的", isOn: d.opened == .today) {
                    d.opened = .today
                    d.openedDate = .now
                }
                EditorChip(title: "选日期", systemImage: "calendar", isOn: d.opened == .custom) { d.opened = .custom }
            }
            if d.opened == .custom {
                DatePicker("开封日期", selection: $d.openedDate, in: ...Date.now, displayedComponents: .date)
                    .frame(minHeight: 44)
            }
        }
    }

    private var perUseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每次用量").font(.subheadline).foregroundStyle(.secondary)
            EditorFlowLayout(spacing: 8) {
                ForEach(PerUseLevel.allCases, id: \.self) { level in
                    EditorChip(title: "\(level.title) \(EditorFmt.amount(level.amount(total: d.total))) \(d.unit)",
                               isOn: d.perUseLevel == level) {
                        d.perUseLevel = level
                        d.perUse = level.amount(total: d.total)
                    }
                }
            }
            Stepper(value: Binding(get: { d.perUse }, set: { d.perUse = $0; d.perUseLevel = nil }),
                    in: 0.1...100, step: 0.1) {
                Text("每次约 \(EditorFmt.amount(d.perUse)) \(d.unit)").monospacedDigit()
            }
            .frame(minHeight: 44)
            Text("按这个用量，大约还能用 \(Int(d.remaining / max(d.perUse, 0.1))) 次。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var priceAndBackup: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("价格")
                Spacer()
                Text("¥").foregroundStyle(.secondary)
                TextField("选填", text: $d.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("价格，元")
            }
            .frame(minHeight: 44)
            Stepper(value: $d.backup, in: 0...20) {
                Text("备用库存 \(d.backup) 件").monospacedDigit()
            }
            .frame(minHeight: 44)
        }
    }

    private var routineToggles: some View {
        VStack(spacing: 4) {
            Toggle(isOn: $d.morning) { Label("加入早间流程", systemImage: RoutineSlot.morning.symbol) }
                .frame(minHeight: 44)
            Toggle(isOn: $d.evening) { Label("加入晚间流程", systemImage: RoutineSlot.evening.symbol) }
                .frame(minHeight: 44)
            Toggle(isOn: Binding(get: { d.makeup ?? (d.category == .makeup) }, set: { d.makeup = $0 })) {
                Label("加入化妆流程", systemImage: RoutineSlot.makeup.symbol)
            }
            .frame(minHeight: 44)
        }
    }

    private static let liquids = ["E7B873", "F1E6D8", "BFD7EA", "D5C6E8", "C8E0CC", "F2C4C9", "E9A07A", "C9505C", "D9B38C"]
    private static let liquidNames = ["琥珀", "奶白", "淡蓝", "淡紫", "薄荷", "裸粉", "珊瑚", "正红", "肤色"]

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("外观").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("盖子")
                Spacer()
                Picker("盖子", selection: Binding(get: { d.effectiveCap }, set: { d.cap = $0; d.capTouched = true })) {
                    ForEach(CapStyle.allCases) { c in Text(c.title).tag(c) }
                }
                .pickerStyle(.menu)
            }
            .frame(minHeight: 44)
            HStack {
                Text("材质")
                Spacer()
                Picker("材质", selection: Binding(get: { d.effectiveFinish }, set: { d.finish = $0; d.finishTouched = true })) {
                    ForEach(GlassFinish.allCases) { f in Text(f.title).tag(f) }
                }
                .pickerStyle(.menu)
            }
            .frame(minHeight: 44)

            Text("液体颜色").padding(.top, 4)
            EditorFlowLayout(spacing: 2) {
                if !Self.liquids.contains(d.tint.uppercased()) {
                    swatch(hex: d.tint, name: "照片取色")
                }
                ForEach(Self.liquids.indices, id: \.self) { i in
                    swatch(hex: Self.liquids[i], name: Self.liquidNames[i])
                }
            }
            Text(cutoutImage != nil ? "有实物抠图时，盖子和材质只影响细节光影。" : "没有照片时，妆台上用这些画出容器。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func swatch(hex: String, name: String) -> some View {
        let on = d.tint.uppercased() == hex.uppercased()
        return Button {
            withAnimation(reduceMotion ? nil : EditorMotion.snappy) {
                d.tint = hex
                d.tintTouched = true
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 1 : 0.12), lineWidth: on ? 2 : 1))
                .scaleEffect(on ? 1.12 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 放上妆台

    private var saveBar: some View {
        let disabled = d.trimmedName.isEmpty
        return Button(action: onSave) {
            Text(isEditing ? "保存" : "放上妆台")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(Capsule().fill(Color.primary.opacity(disabled ? 0.3 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(EditorPressStyle(reduceMotion: reduceMotion))
        .disabled(disabled)
        .accessibilityHint(disabled ? "先填写名称" : "")
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

// MARK: - 小组件（编辑器私用，避免依赖正在改版的公共组件）

/// 识别结果胶囊：识别到的（带魔法棒）、已填的、待填的（虚线）
struct DetectedChip: View {
    enum Style { case detected, set, placeholder }
    let title: String
    let systemImage: String
    let style: Style
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: style == .detected ? "wand.and.stars" : (style == .placeholder ? "plus" : systemImage))
                    .imageScale(.small)
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(style == .placeholder ? .regular : .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(style == .placeholder ? Color.secondary : Color.primary)
            .background(
                Capsule().fill(isActive ? Color.primary.opacity(0.14) : (style == .placeholder ? Color.clear : Color.primary.opacity(0.07)))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(style == .placeholder ? 0.3 : (isActive ? 0.6 : 0)),
                                       style: StrokeStyle(lineWidth: 1, dash: style == .placeholder ? [4, 3] : []))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// 单选胶囊，≥ 44pt
struct EditorChip: View {
    let title: String
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Color(uiColor: .systemBackground) : Color.primary)
            .background(Capsule().fill(isOn ? Color.primary : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 会自动换行的排布（动态字体放大后换行）
struct EditorFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: maxW.isFinite ? maxW : nil, height: nil))
            if x > 0 && x + size.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct EditorPressStyle: ButtonStyle {
    var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(EditorMotion.snappy, value: configuration.isPressed)
    }
}

extension View {
    /// 编辑器里的分组：和首页、藏品同一套玻璃
    func editorCard() -> some View {
        glassPanel(cornerRadius: 20, strong: true)
    }
}
