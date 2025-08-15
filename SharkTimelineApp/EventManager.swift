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
struct ScheduledEvent: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let color: Color
    let notes: String?
    let calendarName: String // Add this property
    
    // Conform to Hashable for easier comparison and set operations if needed
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ScheduledEvent, rhs: ScheduledEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct EventGroup: Identifiable {
    let id = UUID()
    var events: [ScheduledEvent]
    var startDate: Date
    var endDate: Date
    
    // Initialize with a single event
    init(event: ScheduledEvent) {
        self.events = [event]
        self.startDate = event.startDate
        self.endDate = event.endDate
    }
    
    // Add an event to the group and update start/end dates
    mutating func addEvent(_ event: ScheduledEvent) {
        self.events.append(event)
        self.startDate = min(self.startDate, event.startDate)
        self.endDate = max(self.endDate, event.endDate)
        // Sort events within the group by start date for consistent display
        self.events.sort { $0.startDate < $1.startDate }
    }
    
    // Check if a new event overlaps with this group's time range
    func overlaps(with event: ScheduledEvent) -> Bool {
        return event.startDate < self.endDate && event.endDate > self.startDate
    }

    // Check if a new event should be merged with this group based on overlap or small gap
    func shouldMerge(with event: ScheduledEvent) -> Bool {
        let startDiff = abs(self.startDate.timeIntervalSince(event.startDate)) / 60
        let endDiff = abs(self.endDate.timeIntervalSince(event.endDate)) / 60

        // If start times are far apart OR end times are far apart, DO NOT MERGE
        if startDiff > 15 || endDiff > 15 {
            return false
        }

        // Otherwise, use the previous logic (overlap or small gap)
        // Direct overlap
        if event.startDate < self.endDate && event.endDate > self.startDate {
            return true
        }

        // Gap is less than 15 minutes (event starts after group ends)
        let gap = event.startDate.timeIntervalSince(self.endDate) / 60 // Gap in minutes
        if gap >= 0 && gap < 15 {
            return true
        }

        return false
    }
}

class EventManager: ObservableObject {
    @Published var groupedEvents: [EventGroup] = [] // Changed from 'events' to 'groupedEvents'
    @Published var now: Date = Date()
    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?

    init() {
        print("EventManager init called.")
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
        print("EventManager observers set up.")
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
        print("Requesting calendar access...")
        let completionHandler: (Bool, Error?) -> Void = { [weak self] (granted, error) in
            if granted {
                print("Calendar access granted.")
                DispatchQueue.main.async {
                    self?.fetchTodaysEvents()
                    self?.setupTimer()
                }
            } else {
                print("Calendar access request failed: \(error?.localizedDescription ?? "Unknown error").")
            }
        }

        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents(completion: completionHandler)
        } else {
            eventStore.requestAccess(to: .event, completion: completionHandler)
        }
    }

    @objc func fetchTodaysEvents() {
        print("fetchTodaysEvents called.")
        eventStore.reset()
        
        let calendars = eventStore.calendars(for: .event)
        print("Found \(calendars.count) calendars.")
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        
        let fetchedEvents = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { ekEvent in
                // Use a default color if calendar.color is nil
                let eventColor = ekEvent.calendar.color != nil ? Color(ekEvent.calendar.color) : Color.blue
                return ScheduledEvent(title: ekEvent.title, startDate: ekEvent.startDate, endDate: ekEvent.endDate, color: eventColor, notes: ekEvent.notes, calendarName: ekEvent.calendar.title)
            }
            .sorted { $0.startDate < $1.startDate } // Sort by start date for grouping
        
        print("Fetched \(fetchedEvents.count) raw events.")
        
        var newGroupedEvents: [EventGroup] = []
        
        for event in fetchedEvents {
            // If newGroupedEvents is empty, or the current event does not overlap with the last group,
            // start a new group.
            if newGroupedEvents.isEmpty || !newGroupedEvents.last!.shouldMerge(with: event) {
                newGroupedEvents.append(EventGroup(event: event))
            } else {
                // Otherwise, add the event to the last group.
                newGroupedEvents[newGroupedEvents.count - 1].addEvent(event)
            }
        }
        
        print("Grouped \(newGroupedEvents.count) event groups.")
        
        DispatchQueue.main.async {
            self.groupedEvents = newGroupedEvents // Assign to new groupedEvents property
            print("groupedEvents updated on main thread.")
        }
    }

    @objc private func setupTimer() {
        print("setupTimer called.")
        refreshTimer?.invalidate()
        
        var interval = UserDefaults.standard.double(forKey: "refreshInterval")
        if interval <= 0 {
            interval = 900
        }
        
        print("Setting refresh interval to \(interval) seconds.")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            print("Timer fired: Refreshing events.")
            self?.fetchTodaysEvents()
            self?.now = Date()
        }
    }
}