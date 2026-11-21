import SwiftUI
import SwiftData
import PhotosUI
import UIKit

enum OpenedChoice: Hashable { case notYet, today, custom }
enum ExpChoice: Hashable { case years(Int), custom }

enum PerUseLevel: CaseIterable, Hashable {
    case small, medium, large
    var title: String {
        switch self {
        case .small: "少量"
        case .medium: "适中"
        case .large: "多"
        }
    }
    private var factor: Double {
        switch self {
        case .small: 0.01
        case .medium: 0.02
        case .large: 0.04
        }
    }
    /// 按容量自动换算，保留一位小数
    func amount(total: Double) -> Double {
        max(0.1, (total * factor * 10).rounded() / 10)
    }
}

/// 表单里正在编辑的值
struct ProductDraft {
    var name = ""
    var brand = ""
    var category: ProductCategory = .skincare
    var kind: VesselKind = .bottle
    var total: Double = 50
    var remaining: Double = 50
    var remainingTouched = false
    var unit = "ml"
    var perUse: Double = 1
    var perUseLevel: PerUseLevel? = .medium
    var opened: OpenedChoice = .notYet
    var openedDate = Date.now
    var pao: Int? = 6
    var paoTouched = false
    var exp: ExpChoice = .years(2)
    var expDate = Date.now
    var priceText = ""
    var backup = 0
    var tint = "E7B873"
    var tintTouched = false
    var morning = false
    var evening = false
    var photo: Data? = nil

    init() {}

    init(product p: Product) {
        name = p.name
        brand = p.brand
        category = p.category
        kind = p.kind
        total = p.totalAmount
        remaining = p.remainingAmount
        remainingTouched = true
        unit = p.unit
        perUse = p.amountPerUse
        perUseLevel = PerUseLevel.allCases.first { abs($0.amount(total: p.totalAmount) - p.amountPerUse) < 0.001 }
        if let o = p.openedDate {
            opened = Calendar.current.isDateInToday(o) ? .today : .custom
            openedDate = o
        } else {
            opened = .notYet
        }
        pao = p.paoMonths
        paoTouched = true
        exp = .custom
        expDate = p.expiryDate
        if let price = p.price { priceText = Fmt.amount(price) }
        backup = p.backupStock
        tint = p.tintHex
        tintTouched = true
        morning = p.inMorning
        evening = p.inEvening
        photo = p.photo
    }
}

/// 添加 / 编辑：一张底部弹出的表单，目标 15 秒加一件。
struct ProductEditorView: View {
    let target: EditorTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var d: ProductDraft
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showingCamera = false
    @State private var showMore: Bool
    @FocusState private var nameFocused: Bool

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new:
            _d = State(initialValue: ProductDraft())
            _showMore = State(initialValue: false)
        case .edit(let p):
            let draft = ProductDraft(product: p)
            _d = State(initialValue: draft)
            _showMore = State(initialValue: draft.morning || draft.evening || draft.backup > 0 || !draft.priceText.isEmpty)
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var mode: MeasureMode { d.kind.measureMode }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                basicsSection
                shapeSection
                capacitySection
                if mode == .volume { perUseSection }
                datesSection
                moreSection
            }
            .navigationTitle(isEditing ? "编辑" : "添加一件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: d.kind) { old, new in kindChanged(from: old, to: new) }
            .onChange(of: d.total) { _, new in totalChanged(new) }
            .onChange(of: d.category) { _, new in
                if !d.paoTouched { d.pao = d.kind.suggestedPAO(for: new) }
            }
            .onChange(of: pickerItem) { _, item in loadPhoto(item) }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(onImage: { image in d.photo = ImageTools.squareJPEG(image) },
                             onDismiss: { showingCamera = false })
                    .ignoresSafeArea()
            }
            .onAppear { if !isEditing { nameFocused = true } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedName: String { d.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: 1. 照片

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                photoPreview
                VStack(alignment: .leading, spacing: 4) {
                    if CameraPicker.isAvailable {
                        Button { showingCamera = true } label: {
                            Label("拍照", systemImage: "camera").frame(minHeight: 44)
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("从相册选", systemImage: "photo.on.rectangle").frame(minHeight: 44)
                    }
                    if d.photo != nil {
                        Button(role: .destructive) {
                            d.photo = nil
                            pickerItem = nil
                        } label: {
                            Label("移除照片", systemImage: "trash").frame(minHeight: 44)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            Text("没有照片就用形状插画。照片会贴在容器上当标签。")
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let data = d.photo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("产品照片")
        } else {
            ContainerView(kind: d.kind, level: mode == .estimate ? d.remaining / 100 : 0.7,
                          tint: Color(hex: d.tint), animated: false)
                .frame(width: 42, height: 68)
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
                .accessibilityHidden(true)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self),
               let square = ImageTools.squareJPEG(from: data) {
                d.photo = square
            }
        }
    }

    // MARK: 2. 名称、品牌

    private var basicsSection: some View {
        Section {
            TextField("名称（必填），例如 小棕瓶精华", text: $d.name)
                .focused($nameFocused)
                .submitLabel(.next)
            TextField("品牌", text: $d.brand)
            Picker("分类", selection: $d.category) {
                ForEach(ProductCategory.allCases) { c in
                    Label(c.rawValue, systemImage: c.symbol).tag(c)
                }
            }
        }
    }

    // MARK: 3. 形状

    private var shapeSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VesselKind.allCases) { k in
                        shapeTile(k)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("形状")
        } footer: {
            Text(d.kind.examples)
        }
    }

    private func shapeTile(_ k: VesselKind) -> some View {
        let on = d.kind == k
        return Button {
            withAnimation(Theme.snappy) { d.kind = k }
        } label: {
            VStack(spacing: 6) {
                ContainerView(kind: k, level: 0.65, tint: Color(hex: on ? d.tint : k.defaultTint), animated: false)
                    .frame(width: 26, height: 42)
                Text(k.title)
                    .font(.caption.weight(on ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(minWidth: 58, minHeight: 80)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Color.primary.opacity(0.08) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? Color.primary : Color.primary.opacity(0.12), lineWidth: on ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(k.title)，\(k.examples)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 4. 容量 / 剩余

    private var remainingBinding: Binding<Double> {
        Binding(get: { d.remaining }, set: { d.remaining = $0; d.remainingTouched = true })
    }

    @ViewBuilder
    private var capacitySection: some View {
        switch mode {
        case .volume:
            Section("容量") {
                FlowLayout(spacing: 8) {
                    ForEach(d.kind.quickTotals, id: \.self) { v in
                        ChoiceChip(title: "\(Fmt.amount(v)) \(d.unit)", isOn: d.total == v) { d.total = v }
                    }
                }
                .padding(.vertical, 4)
                Stepper(value: $d.total, in: 1...1000, step: d.total < 30 ? 1 : 5) {
                    Text("总量 \(Fmt.amount(d.total)) \(d.unit)").monospacedDigit()
                }
                Picker("单位", selection: $d.unit) {
                    Text("ml").tag("ml")
                    Text("g").tag("g")
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Text("现在剩 \(Fmt.amount(d.remaining)) \(d.unit)").monospacedDigit()
                    Slider(value: remainingBinding, in: 0...max(d.total, 1))
                        .accessibilityLabel("现在剩余")
                        .accessibilityValue("\(Fmt.amount(d.remaining)) \(d.unit)")
                }
            }
        case .count:
            Section {
                FlowLayout(spacing: 8) {
                    ForEach(d.kind.quickTotals, id: \.self) { v in
                        ChoiceChip(title: "\(Int(v)) 片", isOn: d.total == v) { d.total = v }
                    }
                }
                .padding(.vertical, 4)
                Stepper(value: $d.total, in: 1...200, step: 1) {
                    Text("共 \(Int(d.total)) 片").monospacedDigit()
                }
                Stepper(value: remainingBinding, in: 0...max(d.total, 1), step: 1) {
                    Text("现在剩 \(Int(d.remaining)) 片").monospacedDigit()
                }
            } header: {
                Text("数量")
            } footer: {
                Text("每用一次记 1 片。")
            }
        case .estimate:
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("估算还剩 \(Int(d.remaining))%").monospacedDigit()
                    Slider(value: remainingBinding, in: 0...100, step: 5)
                        .accessibilityLabel("估算剩余")
                        .accessibilityValue("\(Int(d.remaining))%")
                }
            } header: {
                Text("剩余")
            } footer: {
                Text("口红、眼影盘这类不好称量，凭感觉估一下就好。以后在详情里直接拖动液面调整。")
            }
        }
    }

    // MARK: 5. 每次用量

    private var perUseSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(PerUseLevel.allCases, id: \.self) { level in
                    ChoiceChip(title: "\(level.title) \(Fmt.amount(level.amount(total: d.total))) \(d.unit)",
                               isOn: d.perUseLevel == level) {
                        d.perUseLevel = level
                        d.perUse = level.amount(total: d.total)
                    }
                }
            }
            .padding(.vertical, 4)
            Stepper(value: Binding(get: { d.perUse }, set: { d.perUse = $0; d.perUseLevel = nil }),
                    in: 0.1...100, step: 0.1) {
                Text("每次约 \(Fmt.amount(d.perUse)) \(d.unit)").monospacedDigit()
            }
        } header: {
            Text("每次用量")
        } footer: {
            Text("按这个用量，大约还能用 \(Int(d.remaining / max(d.perUse, 0.1))) 次。")
        }
    }

    // MARK: 6. 日期

    private var openedValue: Date? {
        switch d.opened {
        case .notYet: return nil
        case .today, .custom: return d.openedDate
        }
    }

    private var expValue: Date {
        switch d.exp {
        case .years(let n):
            let cal = Calendar.current
            return cal.date(byAdding: .year, value: n, to: cal.startOfDay(for: .now)) ?? .now
        case .custom:
            return d.expDate
        }
    }

    private var datesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("开封了吗？").font(.subheadline).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ChoiceChip(title: "还没开", isOn: d.opened == .notYet) { d.opened = .notYet }
                    ChoiceChip(title: "今天开的", isOn: d.opened == .today) {
                        d.opened = .today
                        d.openedDate = .now
                    }
                    ChoiceChip(title: "选日期", systemImage: "calendar", isOn: d.opened == .custom) {
                        d.opened = .custom
                    }
                }
            }
            .padding(.vertical, 4)
            if d.opened == .custom {
                DatePicker("开封日期", selection: $d.openedDate, in: ...Date.now, displayedComponents: .date)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("开封后保质（罐子图标上的 M）").font(.subheadline).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach([6, 12, 24, 36], id: \.self) { m in
                        ChoiceChip(title: "\(m)M", isOn: d.pao == m) {
                            d.paoTouched = true
                            d.pao = d.pao == m ? nil : m
                        }
                        .accessibilityLabel("开封后 \(m) 个月")
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("包装到期日（EXP）").font(.subheadline).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach([1, 2, 3], id: \.self) { n in
                        ChoiceChip(title: "\(n) 年后", isOn: d.exp == .years(n)) { d.exp = .years(n) }
                    }
                    ChoiceChip(title: "选日期", systemImage: "calendar", isOn: d.exp == .custom) {
                        if d.exp != .custom { d.expDate = expValue }
                        d.exp = .custom
                    }
                }
            }
            .padding(.vertical, 4)
            if d.exp == .custom {
                DatePicker("到期日", selection: $d.expDate, displayedComponents: .date)
            }

            expiryPreview
        } header: {
            Text("日期")
        }
    }

    private var expiryPreview: some View {
        let r = Product.computeExpiry(exp: expValue, opened: openedValue, pao: d.pao)
        let days = Product.days(until: r.date)
        let state = Product.state(forDays: days)
        var text = days < 0
            ? "已在 \(Fmt.day(r.date)) 过期（\(r.basis.text)）"
            : "会在 \(Fmt.day(r.date)) 过期（\(r.basis.text)）"
        if openedValue == nil, let m = d.pao {
            text += "。开封后要在 \(m) 个月内用完，第一次记录使用时自动算开封。"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(state == .fresh ? Color.primary : state.color)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 6)
        .animation(Theme.spring, value: text)
        .accessibilityElement(children: .combine)
    }

    // MARK: 7. 更多

    private var moreSection: some View {
        Section {
            DisclosureGroup("更多", isExpanded: $showMore) {
                HStack {
                    Text("价格")
                    Spacer()
                    Text("¥").foregroundStyle(.secondary)
                    TextField("选填", text: $d.priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                .frame(minHeight: 44)

                Stepper(value: $d.backup, in: 0...20) {
                    Text("备用库存 \(d.backup) 件").monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("液体颜色").font(.subheadline).foregroundStyle(.secondary)
                    FlowLayout(spacing: 2) {
                        ForEach(Theme.liquids.indices, id: \.self) { i in
                            colorSwatch(i)
                        }
                    }
                }
                .padding(.vertical, 4)

                Toggle(isOn: $d.morning) { Label("加入早间流程", systemImage: RoutineSlot.morning.symbol) }
                Toggle(isOn: $d.evening) { Label("加入晚间流程", systemImage: RoutineSlot.evening.symbol) }
            }
        }
    }

    private func colorSwatch(_ i: Int) -> some View {
        let hex = Theme.liquids[i]
        let on = d.tint == hex
        return Button {
            withAnimation(Theme.snappy) {
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
        .accessibilityLabel(Theme.liquidNames[i])
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 联动

    private func kindChanged(from old: VesselKind, to new: VesselKind) {
        let fraction = d.total > 0 ? min(1, d.remaining / d.total) : 1
        if !isEditing || old.measureMode != new.measureMode {
            d.unit = new.defaultUnit
            d.total = new.defaultTotal
            if d.remainingTouched {
                let r = new.defaultTotal * fraction
                d.remaining = new.measureMode == .volume ? r : r.rounded()
            } else {
                d.remaining = new.defaultTotal
            }
        }
        if let level = d.perUseLevel { d.perUse = level.amount(total: d.total) }
        if !d.paoTouched { d.pao = new.suggestedPAO(for: d.category) }
        if !d.tintTouched { d.tint = new.defaultTint }
    }

    private func totalChanged(_ total: Double) {
        if d.remainingTouched {
            d.remaining = min(d.remaining, total)
        } else {
            d.remaining = total
        }
        if let level = d.perUseLevel { d.perUse = level.amount(total: total) }
    }

    // MARK: 保存

    private var parsedPrice: Double? {
        let s = d.priceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let v = Double(s), v > 0 else { return nil }
        return v
    }

    private func save() {
        let name = trimmedName
        guard !name.isEmpty else { return }

        let product: Product
        var isNew = false
        switch target {
        case .new:
            product = Product(name: name, kind: d.kind, expiryDate: expValue)
            isNew = true
        case .edit(let p):
            product = p
        }

        product.name = name
        product.brand = d.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        product.category = d.category
        product.kind = d.kind
        switch mode {
        case .volume:
            product.totalAmount = d.total
            product.unit = d.unit
            product.amountPerUse = d.perUse
        case .count:
            product.totalAmount = d.total.rounded()
            product.unit = "片"
            product.amountPerUse = 1
        case .estimate:
            product.totalAmount = 100
            product.unit = "%"
            product.amountPerUse = 0
        }
        product.remainingAmount = min(max(0, d.remaining), product.totalAmount)
        product.openedDate = openedValue
        product.paoMonths = d.pao
        product.expiryDate = expValue
        product.price = parsedPrice
        product.backupStock = d.backup
        product.tintHex = d.tint
        product.inMorning = d.morning
        product.inEvening = d.evening
        product.photo = d.photo
        if product.level >= 0.15 { product.lowStockAlertAt = nil }

        if isNew {
            withAnimation(Theme.spring) { context.insert(product) }
        }
        dismiss()
    }
}
