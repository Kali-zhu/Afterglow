import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import UniformTypeIdentifiers

/// 设置：提醒开关、数据备份与恢复、清除示例数据
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Query private var all: [Product]
    @AppStorage(SettingsKey.notifyExpiry) private var notifyExpiry = true
    @AppStorage(SettingsKey.notifyLowStock) private var notifyLowStock = true
    @AppStorage(SettingsKey.notifyEvening) private var notifyEvening = false
    @State private var denied = false
    @State private var confirmClear = false
    @State private var backupFile: BackupFile? = nil
    @State private var showImporter = false
    @State private var notice: String? = nil

    private var sampleCount: Int { all.filter { $0.isSample }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        RoutineTodayView()
                    } label: {
                        Label("日常流程", systemImage: "list.bullet")
                    }
                }
                Section {
                    Toggle("到期提醒", isOn: $notifyExpiry)
                    Toggle("快用完提醒", isOn: $notifyLowStock)
                    Toggle("晚间流程提醒", isOn: $notifyEvening)
                } header: {
                    Text("提醒")
                } footer: {
                    Text("到期前 30 天、7 天各提醒一次；剩余不到 15% 时提醒补货；晚间流程每晚 21:30 提醒。")
                }

                if denied {
                    Section {
                        Text("通知权限已关闭，提醒不会出现。")
                        Button("打开系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }

                Section {
                    Label("今晚该用：当前流程，在桌面上直接勾选", systemImage: "checklist")
                    Label("快过期：最快过期的几件，也可放在锁屏", systemImage: "hourglass")
                } header: {
                    Text("小组件")
                } footer: {
                    Text("长按主屏幕空白处 → 左上角「＋」→ 搜索「余香」。在小组件里勾掉的，回到 App 会同步。")
                }

                Section {
                    Button { exportBackup() } label: {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                            .frame(minHeight: 44)
                    }
                    .disabled(all.isEmpty)

                    Button { showImporter = true } label: {
                        Label("从备份恢复", systemImage: "tray.and.arrow.down")
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("导出一个文件，里面有全部产品、使用记录和照片。换手机、重装 App 之前先导一份——删掉 App 就等于丢掉这些记录。恢复只补上这台手机上还没有的，不会覆盖现在的数据。")
                }

                Section {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Text(sampleCount > 0 ? "清除示例数据（\(sampleCount) 件）" : "没有示例数据")
                            .frame(minHeight: 44)
                    }
                    .disabled(sampleCount == 0)
                } footer: {
                    Text("只删除示例产品，你自己添加的不受影响。")
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("在用", value: "\(all.filter { !$0.isFinished }.count) 件")
                    LabeledContent("空瓶", value: "\(all.filter { $0.isFinished }.count) 件")
                    if let report = DiagnosticsService.shared.latestReport {
                        ShareLink(item: report) {
                            LabeledContent("诊断报告", value: "\(DiagnosticsService.shared.reportCount) 份 · 分享最新")
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("清除全部示例数据？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除 \(sampleCount) 件示例", role: .destructive) {
                    let kept = all.filter { !$0.isSample }
                    withAnimation(Theme.spring) { SampleData.clear(from: context, products: all) }
                    NotificationService.reschedule(products: kept)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                restoreBackup(from: result)
            }
            .sheet(item: $backupFile) { file in
                BackupShareSheet(file: file)
            }
            .alert("数据备份", isPresented: Binding(get: { notice != nil },
                                                set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) { notice = nil }
            } message: {
                Text(notice ?? "")
            }
        }
        .task { await refreshDenied() }
        .onChange(of: notifyExpiry) { changed(enabled: notifyExpiry) }
        .onChange(of: notifyLowStock) { changed(enabled: notifyLowStock) }
        .onChange(of: notifyEvening) { changed(enabled: notifyEvening) }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: 备份

    private func exportBackup() {
        do {
            let url = try BackupService.exportFile(for: all)
            backupFile = BackupFile(url: url, count: all.count)
        } catch {
            notice = "没能导出：\(error.localizedDescription)"
        }
    }

    private func restoreBackup(from result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let counts = try BackupService.restore(from: url, into: context)
                let refreshed = (try? context.fetch(FetchDescriptor<Product>())) ?? all
                NotificationService.reschedule(products: refreshed)
                coordinator.dataChanged()
                if counts.added == 0 {
                    notice = "这份备份里的 \(counts.skipped) 件产品这台手机上已经有了，没有重复添加。"
                } else if counts.skipped > 0 {
                    notice = "恢复 \(counts.added) 件，另外 \(counts.skipped) 件已存在，跳过。"
                } else {
                    notice = "恢复了 \(counts.added) 件产品。"
                }
            } catch {
                notice = "没能恢复：\(error.localizedDescription)"
            }
        case .failure(let error):
            notice = "没能打开文件：\(error.localizedDescription)"
        }
    }

    private func changed(enabled: Bool) {
        NotificationService.reschedule(products: all)
        guard enabled else { return }
        Task {
            await NotificationService.requestAuthorization()
            await refreshDenied()
        }
    }

    private func refreshDenied() async {
        denied = await NotificationService.authorizationStatus() == .denied
    }
}

// MARK: - 导出的备份文件

private struct BackupFile: Identifiable {
    let url: URL
    let count: Int
    var id: URL { url }
}

/// 备份已经写到临时目录：先说清里面有什么，再交给系统分享（存到「文件」、iCloud Drive 或发给自己）
private struct BackupShareSheet: View {
    let file: BackupFile

    @Environment(\.dismiss) private var dismiss

    private var sizeText: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.sage)
                    .padding(.top, 20)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("备份已生成").font(.title3.weight(.semibold))
                    Text("\(file.count) 件产品 · \(sizeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ShareLink(item: file.url) {
                    Label("保存 / 分享文件", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))

                Text("存到「文件」或者发给自己。换手机后，用「从备份恢复」把它读回来。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background { ScreenBackground() }
            .navigationTitle("导出备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
