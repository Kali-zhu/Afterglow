import Foundation
import SwiftData
import UIKit
import ImageIO

/// App 与小组件共用的存储：
/// - SwiftData 数据库放在 App Group 容器里（两边读写同一份）
/// - 流程顺序、"小组件改过数据"的时间戳放在 App Group 的 UserDefaults
///
/// 这个文件同时编进 App 和 BeautyShelfWidgets 两个 target。
enum SharedStore {
    static let appGroup = "group.com.llmzhu.BeautyShelf"

    /// App Group 的 UserDefaults；没开 App Group（签名里没勾）时退回 standard，至少不崩
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    // MARK: - SwiftData 容器

    /// 共享容器。App 和小组件各自进程里各有一个实例，指向同一个文件。
    static let container: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Product.self])
        if groupURL != nil {
            migrateLegacyStoreIfNeeded()
            let config = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup))
            if let c = try? ModelContainer(for: schema, configurations: [config]) { return c }
        }
        // 兜底：App Group 不可用（例如签名未开启）时用 App 自己的沙盒，小组件将读不到数据
        let fallback = ModelConfiguration(schema: schema, groupContainer: .none)
        do {
            return try ModelContainer(for: schema, configurations: [fallback])
        } catch {
            fatalError("无法创建数据库：\(error)")
        }
    }

    /// v0.2 之前数据库在 App 沙盒的 Application Support/default.store；
    /// 第一次启动共享版时把它搬进 App Group（只在 App 进程、且新位置还没有数据库时做一次）。
    private static func migrateLegacyStoreIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let group = groupURL else { return }
        let fm = FileManager.default
        guard let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let newDir = group.appendingPathComponent("Library/Application Support", isDirectory: true)
        let legacy = legacyDir.appendingPathComponent("default.store")
        let target = newDir.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: target.path) else { return }
        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let from = legacyDir.appendingPathComponent("default.store" + suffix)
                let to = newDir.appendingPathComponent("default.store" + suffix)
                if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: to) }
            }
            // 外部存储（照片 / 抠图）所在的隐藏目录
            let support = legacyDir.appendingPathComponent(".default_SUPPORT", isDirectory: true)
            if fm.fileExists(atPath: support.path) {
                try? fm.copyItem(at: support, to: newDir.appendingPathComponent(".default_SUPPORT", isDirectory: true))
            }
        } catch {
            // 搬迁失败就从空库开始，旧文件原样保留
            for suffix in ["", "-shm", "-wal"] {
                try? fm.removeItem(at: newDir.appendingPathComponent("default.store" + suffix))
            }
        }
    }

    // MARK: - 当前时段：15:00 之前是早间，之后是晚间

    static func currentSlot(at date: Date = .now) -> RoutineSlot {
        Calendar.current.component(.hour, from: date) < 15 ? .morning : .evening
    }

    static func isDone(_ p: Product, _ slot: RoutineSlot, on day: Date = .now) -> Bool {
        let d = p.routineDate(slot)
        guard let d else { return false }
        return Calendar.current.isDate(d, inSameDayAs: day)
    }

    // MARK: - 流程顺序（Product 上没有顺序字段，按 uid 存在 App Group 里）

    private static func orderKey(_ slot: RoutineSlot) -> String { "routineOrder.\(slot.rawValue)" }

    static func order(for slot: RoutineSlot) -> [String] {
        defaults.stringArray(forKey: orderKey(slot)) ?? []
    }

    static func setOrder(_ uids: [String], for slot: RoutineSlot) {
        defaults.set(uids, forKey: orderKey(slot))
    }

    /// 按保存的顺序排；没排过的接在后面（按添加时间）
    static func sorted(_ products: [Product], for slot: RoutineSlot) -> [Product] {
        let order = order(for: slot)
        var index: [String: Int] = [:]
        for (i, id) in order.enumerated() where index[id] == nil { index[id] = i }
        return products.sorted { a, b in
            let ia = index[a.uid.uuidString] ?? Int.max
            let ib = index[b.uid.uuidString] ?? Int.max
            if ia != ib { return ia < ib }
            return a.createdAt < b.createdAt
        }
    }

    /// 某时段里未用完的产品，已排好序
    static func routine(_ slot: RoutineSlot, in context: ModelContext) -> [Product] {
        let all = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        return sorted(all.filter { !$0.isFinished && $0.inRoutine(slot) }, for: slot)
    }

    // MARK: - 小组件改过数据 → App 回到前台时刷新

    private static let externalChangeKey = "externalChangeAt"
    private static let externalSeenKey = "externalChangeSeenAt"

    /// 小组件（另一个进程）写入数据库后调用
    static func noteExternalChange() {
        defaults.set(Date.now.timeIntervalSince1970, forKey: externalChangeKey)
    }

    /// App 回到前台时调用：有没看过的外部修改就返回 true，并标记为已看过
    @discardableResult
    static func consumeExternalChange() -> Bool {
        let changed = defaults.double(forKey: externalChangeKey)
        let seen = defaults.double(forKey: externalSeenKey)
        guard changed > seen else { return false }
        defaults.set(changed, forKey: externalSeenKey)
        return true
    }

    // MARK: - 抠图缩略图（ImageIO 直接按尺寸解码，小组件内存有限）

    private static let thumbCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        return c
    }()

    static func thumbnail(_ data: Data, key: String, maxPixel: Int) -> UIImage? {
        let k = "\(key)-\(data.count)-\(maxPixel)" as NSString
        if let hit = thumbCache.object(forKey: k) { return hit }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        thumbCache.setObject(image, forKey: k)
        return image
    }
}
