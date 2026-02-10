import Foundation

@MainActor
final class CloudController {
    func setupCloudServices(_ vm: DochiViewModel) {
        if let cloudContext = vm.contextService as? CloudContextService {
            Task { await cloudContext.pullFromCloud() }
            cloudContext.onContextChanged = {
                Log.app.info("Realtime: 컨텍스트 변경 감지")
            }
            cloudContext.subscribeToRealtimeChanges()
        }
        if let cloudConversation = vm.conversationService as? CloudConversationService {
            Task {
                await cloudConversation.pullFromCloud()
                vm.conversationManager.loadAll()
            }
            cloudConversation.onConversationsChanged = { [weak vm] in
                vm?.conversationManager.loadAll()
            }
            cloudConversation.subscribeToRealtimeChanges()
        }
        if case .signedIn = vm.supabaseService.authState {
            Task {
                do { try await vm.deviceService.registerDevice() }
                catch { Log.cloud.warning("디바이스 등록 실패: \(error, privacy: .public)") }
                vm.deviceService.startHeartbeat()
            }
        }
    }

    func cleanupCloudServices(_ vm: DochiViewModel) {
        if let cloudContext = vm.contextService as? CloudContextService {
            cloudContext.unsubscribeFromRealtime()
            cloudContext.onContextChanged = nil
        }
        if let cloudConversation = vm.conversationService as? CloudConversationService {
            cloudConversation.unsubscribeFromRealtime()
            cloudConversation.onConversationsChanged = nil
        }
        vm.deviceService.stopHeartbeat()
        Log.app.info("클라우드 서비스 정리 완료")
    }
}

