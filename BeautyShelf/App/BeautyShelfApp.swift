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
            RootView()
        }
        .modelContainer(for: Product.self)
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
