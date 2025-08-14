// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var eventManager = EventManager()
    private let totalMinutesInDay: CGFloat = 24 * 60
    
    @State private var popoverEvent: ScheduledEvent?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 1. 时间线背景
                Rectangle()
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .frame(width: 5)
                    .cornerRadius(2.5)
                    .allowsHitTesting(false)
                    .position(x: 2.5, y: geometry.size.height / 2)

                // 2. 遍历并显示日程
                ForEach(eventManager.events) { event in
                    let today = Date()
                    let startOfDay = Calendar.current.startOfDay(for: today)
                    let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

                    let effectiveStartDate = max(event.startDate, startOfDay)
                    let effectiveEndDate = min(event.endDate, endOfDay)

                    let topOffset = calculateYOffset(for: effectiveStartDate, in: geometry.size.height)
                    let height = calculateHeight(from: effectiveStartDate, to: effectiveEndDate, in: geometry.size.height)

                    if height > 0 {
                        VStack(spacing: 0) {
                            Spacer(minLength: topOffset)
                            EventBarView(event: event, height: height, popoverEvent: $popoverEvent)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 5)
                    }
                }
                
                // 3. 代表当前时间的红色标记
                
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 5, height: 2)
                    .allowsHitTesting(false)
                    .position(x: 2.5, y: calculateYOffset(for: eventManager.now, in: geometry.size.height))
            }
        }
        .frame(width: 5) // 视图宽度为 5px
        .onAppear {
            eventManager.fetchTodaysEvents()
        }
    }

    private func calculateYOffset(for date: Date, in totalHeight: CGFloat) -> CGFloat {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let minutesFromStartOfDay = date.timeIntervalSince(startOfDay) / 60
        return (CGFloat(minutesFromStartOfDay) / totalMinutesInDay) * totalHeight
    }

    private func calculateHeight(from startDate: Date, to endDate: Date, in totalHeight: CGFloat) -> CGFloat {
        let durationInMinutes = CGFloat(endDate.timeIntervalSince(startDate) / 60)
        guard durationInMinutes > 0 else { return 0 }
        return max(2, (durationInMinutes / totalMinutesInDay) * totalHeight)
    }
}

struct EventBarView: View {
    let event: ScheduledEvent
    let height: CGFloat
    @Binding var popoverEvent: ScheduledEvent?
    
    @State private var workItem: DispatchWorkItem?

    var body: some View {
        let isPresentedBinding = Binding<Bool>(
            get: { self.popoverEvent?.id == event.id },
            set: { if !$0 { self.popoverEvent = nil } }
        )

        Rectangle()
            .fill(event.color.opacity(0.8))
            .frame(width: 5, height: height)
            .cornerRadius(2.5)
            .onHover { isHovering in
                if isHovering {
                    // 鼠标进入：窗口变为可交互，并准备显示气泡
                    NSApp.windows.first?.ignoresMouseEvents = false
                    let item = DispatchWorkItem {
                        self.popoverEvent = event
                    }
                    self.workItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
                } else {
                    // 鼠标离开：窗口恢复为可穿透，并取消显示气泡
                    NSApp.windows.first?.ignoresMouseEvents = true
                    self.workItem?.cancel()
                    self.popoverEvent = nil
                }
            }
            .popover(isPresented: isPresentedBinding, attachmentAnchor: .point(.center), arrowEdge: .leading) {
                HStack(spacing: 12) {
                    Capsule()
                        .fill(event.color)
                        .frame(width: 5)

                    VStack(alignment: .leading) {
                        Text(event.title)
                            .font(.headline)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            
                        Text(formatTimeRange(from: event.startDate, to: event.endDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let notes = event.notes, !notes.isEmpty {
                            Divider()
                                .padding(.vertical, 2)
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(maxWidth: 500)
            }
    }
    
    private func formatTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTimeRange(from startDate: Date, to endDate: Date) -> String {
        return "\(formatTime(from: startDate)) - \(formatTime(from: endDate))"
    }
}
