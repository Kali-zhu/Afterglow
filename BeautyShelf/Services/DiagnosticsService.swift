import Foundation
import MetricKit

/// 崩溃与卡顿收集（ROADMAP A6）：只用系统自带的 MetricKit，不引入任何 SDK。
///
/// 报告写在这台手机的 Application Support/Diagnostics 里，不上传、不联网。
/// 用户可在「设置 → 关于」看到份数，并把最新的一份分享给开发者。
/// 系统大约每天汇总一次，App 需要被启动过才会收到。
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsService()

    /// 最多留几份，避免一直占存储
    private let limit = 20

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }()

    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: 读取

    /// 已保存的报告（新的在前）
    var reports: [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var reportCount: Int { reports.count }
    var latestReport: URL? { reports.first }

    // MARK: 接收

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            write(payload.jsonRepresentation(), kind: "metrics", at: payload.timeStampBegin)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            write(payload.jsonRepresentation(), kind: "diagnostics", at: payload.timeStampBegin)
        }
    }

    // MARK: 落盘

    private func write(_ data: Data, kind: String, at date: Date) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmm"
        let url = directory.appendingPathComponent("\(fmt.string(from: date))-\(kind).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            trim()
        } catch {
            // 写不进去就算了：诊断数据不该影响 App 本身
        }
    }

    private func trim() {
        for url in reports.dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
