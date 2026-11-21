import Foundation
import SwiftData
import SwiftUI

// MARK: - 分类

enum ProductCategory: String, Codable, CaseIterable, Identifiable {
    case skincare = "护肤", makeup = "彩妆", fragrance = "香氛", body = "身体", hair = "头发"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .skincare: "drop.fill"
        case .makeup: "paintbrush.pointed.fill"
        case .fragrance: "sparkles"
        case .body: "hands.sparkles.fill"
        case .hair: "wind"
        }
    }
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - 容器形状（决定插画与计量方式）

enum VesselKind: String, Codable, CaseIterable, Identifiable {
    case bottle, jar, tube, sheet, stick, compact
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottle: "瓶"
        case .jar: "罐"
        case .tube: "管"
        case .sheet: "片"
        case .stick: "口红"
        case .compact: "盘"
        }
    }

    var examples: String {
        switch self {
        case .bottle: "精华、水、乳液、粉底液、香水"
        case .jar: "面霜、眼霜、身体霜"
        case .tube: "洁面、防晒、护手霜"
        case .sheet: "面膜、眼膜、安瓶"
        case .stick: "口红、唇膏"
        case .compact: "眼影盘、粉饼、腮红"
        }
    }

    var measureMode: MeasureMode {
        switch self {
        case .bottle, .jar, .tube: .volume
        case .sheet: .count
        case .stick, .compact: .estimate
        }
    }

    var defaultUnit: String {
        switch self {
        case .jar: "g"
        case .sheet: "片"
        case .stick, .compact: "%"
        case .bottle, .tube: "ml"
        }
    }

    var defaultTotal: Double {
        switch self {
        case .bottle: 50
        case .jar: 50
        case .tube: 100
        case .sheet: 10
        case .stick, .compact: 100
        }
    }

    /// 添加表单里的容量快捷胶囊
    var quickTotals: [Double] {
        switch self {
        case .bottle: [30, 50, 100, 200]
        case .jar: [15, 30, 50, 100]
        case .tube: [30, 50, 100, 150]
        case .sheet: [5, 10, 20, 30]
        case .stick, .compact: []
        }
    }

    var defaultTint: String {
        switch self {
        case .stick: "C9505C"
        case .compact: "F2C4C9"
        case .sheet: "BFD7EA"
        case .jar: "F1E6D8"
        case .bottle, .tube: "E7B873"
        }
    }

    /// 开封后保质期的预选值：精华 6M、面霜 12M、香水 36M……
    func suggestedPAO(for category: ProductCategory) -> Int? {
        if category == .fragrance { return 36 }
        switch self {
        case .bottle: return category == .makeup ? 12 : 6
        case .jar, .tube: return 12
        case .sheet: return nil
        case .stick, .compact: return 24
        }
    }
}

enum MeasureMode: String, Codable {
    /// 容量（ml / g），每次扣减用量
    case volume
    /// 按片计数
    case count
    /// 估算剩余 %
    case estimate
}

enum RoutineSlot: String, CaseIterable, Identifiable {
    case morning, evening
    var id: String { rawValue }
    var title: String { self == .morning ? "早间" : "晚间" }
    var symbol: String { self == .morning ? "sun.max" : "moon.stars" }
}

enum ExpiryBasis: Equatable {
    case packaging
    case afterOpening(months: Int)
    var text: String {
        switch self {
        case .packaging: "按包装到期日算"
        case .afterOpening(let m): "按开封后 \(m) 个月算"
        }
    }
}

enum ExpiryState {
    case fresh, soon, expired
    var color: Color {
        switch self {
        case .fresh: Theme.sage
        case .soon: Theme.honey
        case .expired: Theme.rouge
        }
    }
}

// MARK: - 产品

@Model
final class Product {
    var uid: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var categoryRaw: String = "护肤"
    var kindRaw: String = "bottle"
    var measureRaw: String = "volume"
    /// 总量（ml / g / 片；估算型固定为 100）
    var totalAmount: Double = 50
    /// 剩余量（同单位；估算型为百分比）
    var remainingAmount: Double = 50
    var unit: String = "ml"
    var amountPerUse: Double = 1
    var useCount: Int = 0
    var useLog: [Date] = []
    var openedDate: Date? = nil
    /// 开封后保质期（月），PAO
    var paoMonths: Int? = nil
    /// 包装上的到期日 EXP
    var expiryDate: Date = Date(timeIntervalSinceNow: 2 * 365 * 24 * 3600)
    var price: Double? = nil
    var backupStock: Int = 0
    var tintHex: String = "E7B873"
    @Attribute(.externalStorage) var photo: Data? = nil
    var inMorning: Bool = false
    var inEvening: Bool = false
    var morningDoneOn: Date? = nil
    var eveningDoneOn: Date? = nil
    var finishedDate: Date? = nil
    var needsRestock: Bool = false
    var isSample: Bool = false
    var lowStockAlertAt: Date? = nil
    var createdAt: Date = Date.now

    init(name: String,
         brand: String = "",
         category: ProductCategory = .skincare,
         kind: VesselKind = .bottle,
         total: Double? = nil,
         remaining: Double? = nil,
         unit: String? = nil,
         amountPerUse: Double = 1,
         expiryDate: Date,
         openedDate: Date? = nil,
         paoMonths: Int? = nil,
         tintHex: String? = nil) {
        let t = total ?? kind.defaultTotal
        self.uid = UUID()
        self.name = name
        self.brand = brand
        self.categoryRaw = category.rawValue
        self.kindRaw = kind.rawValue
        self.measureRaw = kind.measureMode.rawValue
        self.totalAmount = t
        self.remainingAmount = min(remaining ?? t, t)
        self.unit = unit ?? kind.defaultUnit
        self.amountPerUse = kind.measureMode == .count ? 1 : amountPerUse
        self.useCount = 0
        self.useLog = []
        self.expiryDate = expiryDate
        self.openedDate = openedDate
        self.paoMonths = paoMonths
        self.tintHex = tintHex ?? kind.defaultTint
        self.createdAt = .now
    }

    // MARK: 派生属性

    var category: ProductCategory {
        get { ProductCategory(rawValue: categoryRaw) ?? .skincare }
        set { categoryRaw = newValue.rawValue }
    }

    var kind: VesselKind {
        get { VesselKind(rawValue: kindRaw) ?? .bottle }
        set {
            kindRaw = newValue.rawValue
            measureRaw = newValue.measureMode.rawValue
        }
    }

    var measureMode: MeasureMode { MeasureMode(rawValue: measureRaw) ?? kind.measureMode }

    var level: Double { totalAmount > 0 ? max(0, min(1, remainingAmount / totalAmount)) : 0 }
    var tint: Color { Color(hex: tintHex) }
    var isFinished: Bool { finishedDate != nil }
    /// 剩余不足 15%
    var isLow: Bool { !isFinished && level < 0.15 }

    var remainingText: String {
        switch measureMode {
        case .volume: "剩 \(Fmt.amount(remainingAmount)) \(unit)"
        case .count: "剩 \(Int(remainingAmount.rounded())) / 共 \(Int(totalAmount.rounded())) 片"
        case .estimate: "约剩 \(Int(remainingAmount.rounded()))%"
        }
    }

    /// 面膜袋上显示的剩余片数
    var badgeText: String? { measureMode == .count ? "\(Int(remainingAmount.rounded()))" : nil }

    // MARK: 保质期：EXP 与 开封日 + PAO 取更早的那个

    static func computeExpiry(exp: Date, opened: Date?, pao: Int?) -> (date: Date, basis: ExpiryBasis) {
        if let opened, let pao,
           let afterOpening = Calendar.current.date(byAdding: .month, value: pao, to: opened),
           afterOpening < exp {
            return (afterOpening, .afterOpening(months: pao))
        }
        return (exp, .packaging)
    }

    static func days(until date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func state(forDays days: Int) -> ExpiryState {
        switch days {
        case ..<0: .expired
        case 0...30: .soon
        default: .fresh
        }
    }

    var effectiveExpiry: Date { Self.computeExpiry(exp: expiryDate, opened: openedDate, pao: paoMonths).date }
    var expiryBasis: ExpiryBasis { Self.computeExpiry(exp: expiryDate, opened: openedDate, pao: paoMonths).basis }
    var daysUntilExpiry: Int { Self.days(until: effectiveExpiry) }
    var expiryState: ExpiryState { Self.state(forDays: daysUntilExpiry) }

    var expiryText: String {
        let d = daysUntilExpiry
        if d < 0 { return "已过期 \(-d) 天" }
        if d == 0 { return "今天过期" }
        return "\(d) 天后过期"
    }

    // MARK: 统计

    /// 从开封（或添加）到用完（或今天）一共多少天
    var usageDays: Int {
        let start = openedDate ?? createdAt
        let end = finishedDate ?? .now
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
        return max(1, d)
    }

    var costPerUse: Double? {
        guard let price, price > 0, useCount > 0 else { return nil }
        return price / Double(useCount)
    }

    func used(on day: Date) -> Bool {
        useLog.contains { Calendar.current.isDate($0, inSameDayAs: day) }
    }

    // MARK: 操作

    /// 记一次使用。第一次使用时自动记为今天开封。
    func logUse(at date: Date = .now) {
        if openedDate == nil { openedDate = date }
        useCount += 1
        var log = useLog
        log.append(date)
        if log.count > 500 { log.removeFirst(log.count - 500) }
        useLog = log
        if measureMode != .estimate {
            remainingAmount = max(0, remainingAmount - amountPerUse)
        }
    }

    func undoLastUse() {
        guard useCount > 0 else { return }
        useCount -= 1
        if !useLog.isEmpty {
            var log = useLog
            log.removeLast()
            useLog = log
        }
        if measureMode != .estimate {
            remainingAmount = min(totalAmount, remainingAmount + amountPerUse)
        }
    }

    /// 估算型：拖动液面设置剩余
    func setEstimatedLevel(_ level: Double) {
        remainingAmount = (max(0, min(1, level)) * totalAmount).rounded()
        if self.level >= 0.15 { lowStockAlertAt = nil }
    }

    func inRoutine(_ slot: RoutineSlot) -> Bool { slot == .morning ? inMorning : inEvening }

    func setRoutine(_ slot: RoutineSlot, _ on: Bool) {
        if slot == .morning { inMorning = on } else { inEvening = on }
    }

    func isDone(_ slot: RoutineSlot) -> Bool {
        let d = slot == .morning ? morningDoneOn : eveningDoneOn
        guard let d else { return false }
        return Calendar.current.isDateInToday(d)
    }

    func logRoutine(_ slot: RoutineSlot) {
        logUse()
        if slot == .morning { morningDoneOn = .now } else { eveningDoneOn = .now }
    }

    func undoRoutine(_ slot: RoutineSlot) {
        guard isDone(slot) else { return }
        undoLastUse()
        if slot == .morning { morningDoneOn = nil } else { eveningDoneOn = nil }
    }

    func markFinished() {
        finishedDate = .now
        remainingAmount = 0
        lowStockAlertAt = nil
        if openedDate == nil { openedDate = createdAt }
    }

    /// 补货 / 开备用：一件全新的同款
    func makeFreshCopy(openNow: Bool) -> Product {
        let exp = Calendar.current.date(byAdding: .year, value: 2, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let p = Product(name: name, brand: brand, category: category, kind: kind,
                        total: totalAmount, remaining: totalAmount, unit: unit,
                        amountPerUse: amountPerUse, expiryDate: exp,
                        openedDate: openNow ? .now : nil, paoMonths: paoMonths, tintHex: tintHex)
        p.price = price
        p.photo = photo
        p.inMorning = inMorning
        p.inEvening = inEvening
        p.isSample = isSample
        return p
    }
}
