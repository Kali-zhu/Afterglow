import SwiftUI
import SwiftData

/// 我的：账号、会员、这个 App 剩下的事。
///
/// 三块，从上到下——身份卡（本机使用中 + 三个数字）、会员卡（会员会解锁什么，位置先留好）、
/// 一张清单（日常流程 / 提醒与数据 / 关于）。
/// 现在没有登录、没有上传：整个梳妆台就在这台手机上。
struct ProfileView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \Product.createdAt, order: .forward) private var all: [Product]

    /// 身份卡上的数字只算你自己的：示例数据不算"累计记下"。一件真的都还没有时照示例显示。
    private var counted: [Product] {
        let own = all.filter { !$0.isSample }
        return own.isEmpty ? all : own
    }
    private var totalUses: Int { counted.reduce(0) { $0 + $1.useCount } }
    private var activeCount: Int { counted.filter { !$0.isFinished }.count }
    private var emptyCount: Int { counted.filter { $0.isFinished }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    identityCard
                    membershipCard
                    settingsList
                    Text("你的梳妆台全部存在这台手机上，没有账号、没有上传。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
            .background {
                // 四个标签页同一个底：冷瓷白，不带任何产品柔光
                ScreenBackground()
            }
            .navigationTitle("我的")
        }
    }

    // MARK: 身份

    private var identityCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.sage.opacity(0.22), Theme.sage.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("余")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.sage)
                }
                .frame(width: 54, height: 54)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text("梳妆台的主人").font(.title3.weight(.semibold))
                    Text("本机使用中 · 还没有登录").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                StatReadout(value: "\(activeCount)", caption: "在用")
                Spacer(minLength: 6)
                StatReadout(value: "\(emptyCount)", caption: "空瓶")
                Spacer(minLength: 6)
                StatReadout(value: "\(totalUses)", caption: "累计记下")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本机使用中，在用 \(activeCount) 件，空瓶 \(emptyCount) 件，累计记下 \(totalUses) 次")
    }

    // MARK: 会员（位置先留好，不假装已经能买）

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("余香会员").font(.title3.weight(.semibold))
                Text("开发中")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.sage.opacity(0.16)))
                    .foregroundStyle(Theme.sage)
                Spacer(minLength: 8)
                Text("现在全部免费").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                benefit("wand.and.stars", "云抠图", "拍一张，云上替你把底抠干净；会员含每月额度")
                benefit("icloud", "多设备同步", "用 Apple 登录后，同一个梳妆台在哪台手机上都在")
                benefit("sparkles", "主题与小组件", "按季节、按品类，换一张桌面")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24, tint: Theme.sage)
        .accessibilityElement(children: .contain)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.sage)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.sage.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，会员功能，\(detail)")
    }

    // MARK: 清单

    private var settingsList: some View {
        VStack(spacing: 0) {
            NavigationLink { RoutineTodayView() } label: {
                row("日常流程", detail: SharedStore.currentSlot().title, symbol: "list.bullet")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 34)

            Button { coordinator.showSettings = true } label: {
                row("提醒与数据", detail: nil, symbol: "bell")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 34)

            NavigationLink { AboutView() } label: {
                row("关于余香", detail: appVersion, symbol: "info.circle")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassPanel(cornerRadius: 22)
    }

    private func row(_ title: String, detail: String?, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title).font(.body)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

/// 关于：这个 App 现在是什么、数据在哪、接下来做什么
private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("余香 · Afterglow").font(.title2.weight(.semibold))
                    Text("版本 \(appVersion)").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                block("数据", "你的梳妆台全部存在这台手机上，App 和桌面小组件读的是同一份。没有账号，也不上传任何东西。")
                block("备份", "「设置 → 数据」可以把全部产品（含使用记录和照片）导出成一个文件，存到「文件」或 iCloud Drive；换手机、重装之前先导一份。恢复只补上这台手机上还没有的，不会覆盖现在的数据。")
                block("接下来", "云抠图（拍一张，自动抠掉背景）、会员、多设备同步。会员上线之前，所有功能都免费。")
                block("反馈", "哪里用着别扭，直接告诉作者——这一版还在长。")

                if let url = URL(string: "https://kali-zhu.github.io/Afterglow/privacy.html") {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Text("隐私政策").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal, 16)
                    .glassPanel(cornerRadius: 18)
                    .accessibilityLabel("在浏览器里打开隐私政策")
                }
            }
            .padding(20)
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity)
        }
        .background { ScreenBackground() }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 18)
    }
}
