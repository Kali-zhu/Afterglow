import SwiftUI
import SwiftData
import UserNotifications

@main
struct BeautyShelfApp: App {
    init() {
        // App 在前台时也显示提醒横幅
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            LiveContextHost {
                RootView()
            }
        }
        // App Group 里的共享数据库：小组件读写同一份
        .modelContainer(SharedStore.container)
    }
}

/// 小组件（另一个进程）改过数据库后，主上下文里还是旧对象。
/// 回到前台时如果发现外部修改，就换一个新的 ModelContext，让 @Query 重新读取。
struct LiveContextHost<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.modelContext) private var defaultContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveContext: ModelContext? = nil

    var body: some View {
        content
            .modelContext(liveContext ?? defaultContext)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, SharedStore.consumeExternalChange() else { return }
                let fresh = ModelContext(SharedStore.container)
                fresh.autosaveEnabled = true
                liveContext = fresh
            }
    }
}

/// 首次打开显示欢迎页；之后进入三个标签页
struct RootView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @Query private var products: [Product]
    @Environment(\.modelContext) private var context
    @State private var startWithAdd = false

    var body: some View {
        Group {
            if onboarded || !products.isEmpty {
                MainTabView(startWithAdd: startWithAdd)
                    .transition(.opacity)
            } else {
                WelcomeView(
                    onAddFirst: {
                        startWithAdd = true
                        withAnimation(.easeInOut(duration: 0.35)) { onboarded = true }
                    },
                    onSamples: {
                        SampleData.insert(into: context)
                        withAnimation(.easeInOut(duration: 0.35)) { onboarded = true }
                    }
                )
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    RootView().modelContainer(for: Product.self, inMemory: true)
}
