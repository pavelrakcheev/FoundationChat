#if os(iOS)
import SwiftUI
import UIKit

enum MobilePlatform {
    @MainActor
    static var deviceName: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            "iPad"
        case .phone:
            "iPhone"
        default:
            "устройстве"
        }
    }
}

@main
struct FoundationChatMobileApp: App {
    @State private var viewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(viewModel)
                .task { await viewModel.checkAvailability() }
        }
    }
}
#endif
