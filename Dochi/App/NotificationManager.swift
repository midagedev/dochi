import Foundation
import UserNotifications

/// Manages macOS Notification Center integration for Dochi heartbeat alerts.
/// Registers categories/actions, sends category-specific notifications, and handles user responses.
@MainActor
final class NotificationManager: NSObject, Observable, UNUserNotificationCenterDelegate {

    // MARK: - Category & Action Identifiers

    enum Category: String, CaseIterable {
        case calendar = "dochi-calendar"
        case kanban = "dochi-kanban"
        case reminder = "dochi-reminder"
        case memory = "dochi-memory"
    }

    enum ActionIdentifier: String {
        case reply = "reply"
        case openApp = "open-app"
        case dismiss = "dismiss"
    }

    // MARK: - Callbacks

    /// Called when user replies via notification text input (text, category, original body).
    var onReply: ((String, String, String) -> Void)?

    /// Called when user taps "Open App" action (category).
    var onOpenApp: ((String) -> Void)?

    // MARK: - State

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let settings: AppSettings

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    // MARK: - Setup

    /// Register notification categories and actions. Call at app launch.
    /// Respects `settings.notificationReplyEnabled` to include or exclude reply actions.
    func registerCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: ActionIdentifier.reply.rawValue,
            title: "답장",
            options: [],
            textInputButtonTitle: "보내기",
            textInputPlaceholder: "도치에게 답장..."
        )

        let openAppAction = UNNotificationAction(
            identifier: ActionIdentifier.openApp.rawValue,
            title: "앱 열기",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: ActionIdentifier.dismiss.rawValue,
            title: "닫기",
            options: .destructive
        )

        let replyEnabled = settings.notificationReplyEnabled

        // Calendar and reminder categories support reply when enabled
        let calendarActions: [UNNotificationAction] = replyEnabled
            ? [replyAction, openAppAction, dismissAction]
            : [openAppAction, dismissAction]

        let calendarCategory = UNNotificationCategory(
            identifier: Category.calendar.rawValue,
            actions: calendarActions,
            intentIdentifiers: [],
            options: []
        )

        let kanbanCategory = UNNotificationCategory(
            identifier: Category.kanban.rawValue,
            actions: [openAppAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        let reminderActions: [UNNotificationAction] = replyEnabled
            ? [replyAction, openAppAction, dismissAction]
            : [openAppAction, dismissAction]

        let reminderCategory = UNNotificationCategory(
            identifier: Category.reminder.rawValue,
            actions: reminderActions,
            intentIdentifiers: [],
            options: []
        )

        let memoryCategory = UNNotificationCategory(
            identifier: Category.memory.rawValue,
            actions: [openAppAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            calendarCategory, kanbanCategory, reminderCategory, memoryCategory
        ])
        Log.app.info("NotificationManager: registered 4 notification categories (replyEnabled: \(replyEnabled))")
    }

    /// Request notification permission if not already granted.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let currentSettings = await center.notificationSettings()
        authorizationStatus = currentSettings.authorizationStatus

        if currentSettings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorizationStatus = granted ? .authorized : .denied
                Log.app.info("NotificationManager: authorization \(granted ? "granted" : "denied")")
            } catch {
                Log.app.error("NotificationManager: authorization request failed: \(error.localizedDescription)")
                authorizationStatus = .denied
            }
        }
    }

    /// Refresh the current authorization status.
    func refreshAuthorizationStatus() async {
        let currentSettings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = currentSettings.authorizationStatus
    }

    // MARK: - Send Notifications

    func sendCalendarNotification(events: String) {
        guard settings.notificationCalendarEnabled else { return }
        sendNotification(
            title: "도치 - 일정 알림",
            body: events,
            category: .calendar
        )
    }

    func sendKanbanNotification(tasks: String) {
        guard settings.notificationKanbanEnabled else { return }
        sendNotification(
            title: "도치 - 칸반 알림",
            body: tasks,
            category: .kanban
        )
    }

    func sendReminderNotification(reminders: String) {
        guard settings.notificationReminderEnabled else { return }
        sendNotification(
            title: "도치 - 미리알림",
            body: reminders,
            category: .reminder
        )
    }

    func sendMemoryNotification(warning: String) {
        guard settings.notificationMemoryEnabled else { return }
        sendNotification(
            title: "도치 - 메모리 알림",
            body: warning,
            category: .memory
        )
    }

    // MARK: - Private

    private func sendNotification(title: String, body: String, category: Category) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.threadIdentifier = "dochi-heartbeat-\(category.rawValue)"

        if settings.notificationSoundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "dochi-\(category.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("NotificationManager: failed to send \(category.rawValue) notification: \(error.localizedDescription)")
            } else {
                Log.app.info("NotificationManager: sent \(category.rawValue) notification")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let body = response.notification.request.content.body

        switch response.actionIdentifier {
        case ActionIdentifier.reply.rawValue:
            if let textResponse = response as? UNTextInputNotificationResponse {
                let replyText = textResponse.userText
                Task { @MainActor in
                    Log.app.info("NotificationManager: user replied to \(categoryIdentifier): \(replyText)")
                    self.onReply?(replyText, categoryIdentifier, body)
                }
            }
        case ActionIdentifier.openApp.rawValue:
            Task { @MainActor in
                Log.app.info("NotificationManager: user opened app from \(categoryIdentifier)")
                self.onOpenApp?(categoryIdentifier)
            }
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            Task { @MainActor in
                Log.app.info("NotificationManager: user tapped \(categoryIdentifier) notification")
                self.onOpenApp?(categoryIdentifier)
            }
        default:
            break
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
