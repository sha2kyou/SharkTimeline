// EventManager.swift
import Foundation
import EventKit
import Combine
import SwiftUI

// 定义一个通知名称，用于在设置更改时广播
extension Notification.Name {
    static let refreshIntervalChanged = Notification.Name("refreshIntervalChanged")
    static let manualRefreshRequested = Notification.Name("manualRefreshRequested")
}

// 定义一个简单的结构体来存储我们关心的事件信息
struct ScheduledEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let color: Color
    let notes: String?
}

class EventManager: ObservableObject {
    @Published var events: [ScheduledEvent] = []
    @Published var now: Date = Date()
    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?

    init() {
        checkAuthorization()
        
        // 添加观察者，监听刷新间隔变化的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setupTimer),
            name: .refreshIntervalChanged,
            object: nil
        )
        
        // 添加观察者，监听手动刷新请求
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fetchTodaysEvents),
            name: .manualRefreshRequested,
            object: nil
        )
    }

    private func checkAuthorization() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            fetchTodaysEvents()
            setupTimer()
        
        case .notDetermined:
            requestAccess()
        
        case .writeOnly, .denied, .restricted:
            print("日历访问权限不足或被拒绝。")
        
        @unknown default:
            print("未知的日历授权状态。")
        }
    }

    private func requestAccess() {
        let completionHandler: (Bool, Error?) -> Void = { [weak self] (granted, error) in
            if granted {
                DispatchQueue.main.async {
                    self?.fetchTodaysEvents()
                    self?.setupTimer()
                }
            } else {
                print("日历访问请求失败。")
            }
        }

        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents(completion: completionHandler)
        } else {
            eventStore.requestAccess(to: .event, completion: completionHandler)
        }
    }

    @objc func fetchTodaysEvents() {
        eventStore.reset()
        
        let calendars = eventStore.calendars(for: .event)
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        
        let fetchedEvents = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map {
                ScheduledEvent(title: $0.title, startDate: $0.startDate, endDate: $0.endDate, color: Color($0.calendar.color), notes: $0.notes)
            }
        
        DispatchQueue.main.async {
            self.events = fetchedEvents
        }
    }

    @objc private func setupTimer() {
        refreshTimer?.invalidate()
        
        var interval = UserDefaults.standard.double(forKey: "refreshInterval")
        if interval <= 0 {
            interval = 900
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            print("正在刷新事件，间隔: \(interval)秒")
            self?.fetchTodaysEvents()
            self?.now = Date()
        }
    }
}