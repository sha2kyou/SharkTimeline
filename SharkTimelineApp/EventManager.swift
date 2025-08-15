// EventManager.swift
import Foundation
import EventKit
import Combine
import SwiftUI

// 定义一个通知名称，用于在设置更改时广播
extension Notification.Name {
    static let refreshIntervalChanged = Notification.Name("refreshIntervalChanged")
    static let manualRefreshRequested = Notification.Name("manualRefreshRequested")
    static let selectedCalendarsChanged = Notification.Name("selectedCalendarsChanged")
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
}

extension EventGroup {
    static func shouldMerge(event1: ScheduledEvent, event2: ScheduledEvent) -> Bool {
        // This logic is similar to the instance shouldMerge, but operates on two ScheduledEvents.
        // We need to decide which event acts as the "group" and which as the "new event".
        // Since the relationship is symmetric, we can pick one as "self" and the other as "event".
        // For the purpose of color comparison, we assume event1 is the "group".

        // Get the color of event1
        let groupColor = event1.color

        // Rule 1: Same color AND any overlap
        if groupColor == event2.color {
            // Check for any overlap between event1 and event2
            return event1.startDate < event2.endDate && event2.startDate < event1.endDate
        }
        // Rule 2: Different colors
        else {
            let startDiff = abs(event1.startDate.timeIntervalSince(event2.startDate)) / 60
            let endDiff = abs(event1.endDate.timeIntervalSince(event2.endDate)) / 60

            // Do NOT merge if start times are far apart OR end times are far apart
            if startDiff >= 15 || endDiff >= 15 {
                return false
            } else {
                return true // Merge if colors are different AND start/end times are close
            }
        }
    }
}

class EventManager: ObservableObject {
    @Published var groupedEvents: [EventGroup] = [] // Changed from 'events' to 'groupedEvents'
    @Published var now: Date = Date()
    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private var selectedCalendarIDs: [String] = [] // Managed manually with UserDefaults

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
        
        // 添加观察者，监听选定日历变化的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fetchTodaysEvents),
            name: .selectedCalendarsChanged,
            object: nil
        )
    }

    private func checkAuthorization() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            fetchTodaysEvents()
            setupTimer()
        
        case .notDetermined:
            requestAccess { [weak self] granted in
                if granted {
                    self?.fetchTodaysEvents()
                    self?.setupTimer()
                }
            }
        
        case .writeOnly, .denied, .restricted:
            break // Do nothing, UI will show appropriate message
        
        @unknown default:
            break // Do nothing
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        let completionHandler: (Bool, Error?) -> Void = { (granted, error) in
            if !granted, let error = error {
                print("Calendar access request failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(granted)
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
        
        // Load selectedCalendarIDs from UserDefaults
        selectedCalendarIDs = UserDefaults.standard.array(forKey: "selectedCalendarIDs") as? [String] ?? []

        let allCalendars = eventStore.calendars(for: .event)
        let calendars = allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        
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
        
        // --- Start of new grouping logic (Connected Components) ---

        // 1. Build the Adjacency List (Graph)
        // adjList[i] will contain indices of events that should merge with fetchedEvents[i]
        var adjList: [Int: [Int]] = [:]
        for i in 0..<fetchedEvents.count {
            adjList[i] = [] // Initialize empty list for each event
        }

        for i in 0..<fetchedEvents.count {
            for j in (i + 1)..<fetchedEvents.count { // Avoid duplicate pairs and self-loops
                let event1 = fetchedEvents[i]
                let event2 = fetchedEvents[j]

                if EventGroup.shouldMerge(event1: event1, event2: event2) {
                    adjList[i]?.append(j)
                    adjList[j]?.append(i) // Graph is undirected
                }
            }
        }

        // 2. Find Connected Components using DFS
        var visited: [Bool] = Array(repeating: false, count: fetchedEvents.count)
        var newGroupedEvents: [EventGroup] = []

        for i in 0..<fetchedEvents.count {
            if !visited[i] {
                var currentComponentEvents: [ScheduledEvent] = []
                var stack: [Int] = [i] // Use a stack for DFS

                visited[i] = true

                while !stack.isEmpty {
                    let currentIndex = stack.removeLast()
                    currentComponentEvents.append(fetchedEvents[currentIndex])

                    if let neighbors = adjList[currentIndex] {
                        for neighborIndex in neighbors {
                            if !visited[neighborIndex] {
                                visited[neighborIndex] = true
                                stack.append(neighborIndex)
                            }
                        }
                    }
                }

                // 3. Form EventGroup from the connected component
                if !currentComponentEvents.isEmpty {
                    // Sort events within the component by start date for consistent group properties
                    currentComponentEvents.sort { $0.startDate < $1.startDate }

                    let firstEventInComponent = currentComponentEvents.first!
                    var newGroup = EventGroup(event: firstEventInComponent)

                    for k in 1..<currentComponentEvents.count {
                        newGroup.addEvent(currentComponentEvents[k])
                    }
                    newGroupedEvents.append(newGroup)
                }
            }
        }

        // --- End of new grouping logic ---
        
        DispatchQueue.main.async {
            self.groupedEvents = newGroupedEvents // Assign to new groupedEvents property
        }
    }

    @objc private func setupTimer() {
        refreshTimer?.invalidate()
        
        var interval = UserDefaults.standard.double(forKey: "refreshInterval")
        if interval <= 0 {
            interval = 900
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchTodaysEvents()
            self?.now = Date()
        }
    }
}