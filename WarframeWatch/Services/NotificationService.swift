import Foundation
import UserNotifications

public final class NotificationService {
    public static let shared = NotificationService()
    
    private init() {}
    
    public func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    public func checkPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
    
    public func scheduleReminder(for item: WatchItem) {
        guard let exp = item.expiry else { return }
        
        let leadSeconds: TimeInterval = 30 * 60 // 30 minutes before
        let targetDate = exp.addingTimeInterval(-leadSeconds)
        let timeInterval = targetDate.timeIntervalSince(Date())
        
        guard timeInterval > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Warframe 任务即将到期"
        content.subtitle = item.label
        content.body = "该条目将在 30 分钟后到期，请尽快上线完成！"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId(for: item.key), content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error.localizedDescription)")
            }
        }
    }
    
    public func cancelReminder(for key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId(for: key)])
    }
    
    private func notificationId(for key: String) -> String {
        "wf_watch_\(key)"
    }
}
