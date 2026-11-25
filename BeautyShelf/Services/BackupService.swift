import Foundation
import SwiftData

/// 数据备份（ROADMAP A2）：把全部产品——包括使用记录、照片和抠图——导出成一个 JSON 文件，
/// 再从这个文件恢复。恢复只补上这台手机上还没有的产品（按 uid 去重），不覆盖现有数据。
enum BackupService {
    /// 文件格式版本：字段增减时加一。旧版本 App 读到更新的文件会拒绝恢复。
    static let formatVersion = 1

    struct Backup: Codable {
        var version: Int
        var exportedAt: Date
        var products: [ProductRecord]
    }

    /// 一件产品落盘的全部字段（与 Product 的存储属性一一对应）
    struct ProductRecord: Codable {
        var uid: UUID
        var name: String
        var brand: String
        var categoryRaw: String
        var kindRaw: String
        var measureRaw: String
        var totalAmount: Double
        var remainingAmount: Double
        var unit: String
        var amountPerUse: Double
        var useCount: Int
        var useLog: [Date]
        var groupedUses: [UsageGroupMark]?
        var openedDate: Date?
        var paoMonths: Int?
        var expiryDate: Date
        var price: Double?
        var backupStock: Int
        var tintHex: String
        var photo: Data?
        var cutout: Data?
        var capRaw: String
        var finishRaw: String
        var inMorning: Bool
        var inEvening: Bool
        var inMakeup: Bool?
        var morningDoneOn: Date?
        var eveningDoneOn: Date?
        var makeupDoneOn: Date?
        var finishedDate: Date?
        var needsRestock: Bool
        var isSample: Bool
        var pinnedAt: Date?
        var lowStockAlertAt: Date?
        var createdAt: Date

        init(_ p: Product) {
            uid = p.uid
            name = p.name
            brand = p.brand
            categoryRaw = p.categoryRaw
            kindRaw = p.kindRaw
            measureRaw = p.measureRaw
            totalAmount = p.totalAmount
            remainingAmount = p.remainingAmount
            unit = p.unit
            amountPerUse = p.amountPerUse
            useCount = p.useCount
            useLog = p.useLog
            groupedUses = p.groupedUses
            openedDate = p.openedDate
            paoMonths = p.paoMonths
            expiryDate = p.expiryDate
            price = p.price
            backupStock = p.backupStock
            tintHex = p.tintHex
            photo = p.photo
            cutout = p.cutout
            capRaw = p.capRaw
            finishRaw = p.finishRaw
            inMorning = p.inMorning
            inEvening = p.inEvening
            inMakeup = p.inMakeup
            morningDoneOn = p.morningDoneOn
            eveningDoneOn = p.eveningDoneOn
            makeupDoneOn = p.makeupDoneOn
            finishedDate = p.finishedDate
            needsRestock = p.needsRestock
            isSample = p.isSample
            pinnedAt = p.pinnedAt
            lowStockAlertAt = p.lowStockAlertAt
            createdAt = p.createdAt
        }

        func makeProduct() -> Product {
            let p = Product(name: name, brand: brand,
                            category: ProductCategory(rawValue: categoryRaw) ?? .skincare,
                            kind: VesselKind(rawValue: kindRaw) ?? .bottle,
                            total: totalAmount, remaining: remainingAmount, unit: unit,
                            amountPerUse: amountPerUse, expiryDate: expiryDate,
                            openedDate: openedDate, paoMonths: paoMonths, tintHex: tintHex)
            p.uid = uid
            p.categoryRaw = categoryRaw
            p.kindRaw = kindRaw
            p.measureRaw = measureRaw
            p.totalAmount = totalAmount
            p.remainingAmount = remainingAmount
            p.amountPerUse = amountPerUse
            p.useCount = useCount
            p.useLog = useLog
            p.groupedUses = groupedUses
            p.price = price
            p.backupStock = backupStock
            p.photo = photo
            p.cutout = cutout
            p.capRaw = capRaw
            p.finishRaw = finishRaw
            p.inMorning = inMorning
            p.inEvening = inEvening
            p.inMakeup = inMakeup
            p.morningDoneOn = morningDoneOn
            p.eveningDoneOn = eveningDoneOn
            p.makeupDoneOn = makeupDoneOn
            p.finishedDate = finishedDate
            p.needsRestock = needsRestock
            p.isSample = isSample
            p.pinnedAt = pinnedAt
            p.lowStockAlertAt = lowStockAlertAt
            p.createdAt = createdAt
            return p
        }
    }

    enum BackupError: LocalizedError {
        case notABackup
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .notABackup: "这不是余香的备份文件。"
            case .newerVersion: "这个备份来自更新的版本，请先更新「余香」再恢复。"
            }
        }
    }

    /// 把全部产品写成一个临时 JSON 文件，交给 ShareLink 保存到「文件」或发出去
    static func exportFile(for products: [Product]) throws -> URL {
        let backup = Backup(version: formatVersion, exportedAt: .now,
                            products: products.map(ProductRecord.init))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(backup)

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("余香备份-\(stamp.string(from: .now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 从备份文件恢复：只补上还没有的产品。返回新增几件、跳过几件。
    static func restore(from url: URL, into context: ModelContext) throws -> (added: Int, skipped: Int) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let backup = try? decoder.decode(Backup.self, from: data) else {
            throw BackupError.notABackup
        }
        guard backup.version <= formatVersion else { throw BackupError.newerVersion }

        let existing = Set(((try? context.fetch(FetchDescriptor<Product>())) ?? []).map(\.uid))
        var added = 0
        var skipped = 0
        for record in backup.products {
            if existing.contains(record.uid) {
                skipped += 1
                continue
            }
            context.insert(record.makeProduct())
            added += 1
        }
        try context.save()
        return (added, skipped)
    }
}
