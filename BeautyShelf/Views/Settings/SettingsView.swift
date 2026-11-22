import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// 设置：三个提醒开关 + 清除示例数据
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Product]
    @AppStorage(SettingsKey.notifyExpiry) private var notifyExpiry = true
    @AppStorage(SettingsKey.notifyLowStock) private var notifyLowStock = true
    @AppStorage(SettingsKey.notifyEvening) private var notifyEvening = false
    @State private var denied = false
    @State private var confirmClear = false

    private var sampleCount: Int { all.filter { $0.isSample }.count }

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("长按主屏幕空白处 → 左上角「＋」→ 搜索「妆台」。在小组件里勾掉的，回到 App 会同步。")
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
        }
        .task { await refreshDenied() }
        .onChange(of: notifyExpiry) { changed(enabled: notifyExpiry) }
        .onChange(of: notifyLowStock) { changed(enabled: notifyLowStock) }
        .onChange(of: notifyEvening) { changed(enabled: notifyEvening) }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
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
