// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var eventManager: EventManager
    @State private var popoverGroup: EventGroup? // State to control popover visibility for a group
    @AppStorage("timelinePosition") private var timelinePosition: String = "left"

    let totalMinutesInDay: CGFloat = 1440.0 // Define totalMinutesInDay here

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

                // 2. 遍历并显示日程组
                ForEach(eventManager.groupedEvents) { group in
                    let today = Date()
                    let startOfDay = Calendar.current.startOfDay(for: today)
                    let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

                    let effectiveStartDate = max(group.startDate, startOfDay)
                    let effectiveEndDate = min(group.endDate, endOfDay)

                    let topOffset = calculateYOffset(for: effectiveStartDate, in: geometry.size.height)
                    let height = calculateHeight(from: effectiveStartDate, to: effectiveEndDate, in: geometry.size.height)

                    if height > 0 {
                        VStack(spacing: 0) {
                            EventGroupView(group: group, height: height, popoverGroup: $popoverGroup)
                        }
                        .frame(width: 5)
                        .offset(y: topOffset)
                    }
                }
                
                // 3. 代表当前时间的红色标记
                
                TriangleShape(isLeftAligned: timelinePosition == "left") // Dynamically set direction based on settings
                    .fill(Color.primary)
                    .frame(width: 5, height: 5) // Width 5px, Height 5px
                    .position(x: 2.5, y: calculateYOffset(for: eventManager.now, in: geometry.size.height))
                    .allowsHitTesting(false)
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

struct EventGroupView: View {
    let group: EventGroup
    let height: CGFloat
    @Binding var popoverGroup: EventGroup?
    
    @State private var workItem: DispatchWorkItem?

    var body: some View {
        let isPresentedBinding = Binding<Bool>(
            get: { self.popoverGroup?.id == group.id },
            set: { if !$0 { self.popoverGroup = nil } }
        )

        Rectangle()
            .fill(group.events.first?.color.opacity(0.8) ?? Color.gray.opacity(0.8)) // Use first event's color or default
            .frame(width: 5, height: height)
            .cornerRadius(2.5)
            .onHover { isHovering in
                if isHovering {
                    // 鼠标进入：窗口变为可交互，并准备显示气泡
                    NSApp.windows.first?.ignoresMouseEvents = false
                    let item = DispatchWorkItem {
                        // Set the popover event to the first event in the group for display
                        self.popoverGroup = group
                    }
                    self.workItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
                } else {
                    // 鼠标离开：窗口恢复为可穿透，并取消显示气泡
                    NSApp.windows.first?.ignoresMouseEvents = true
                    self.workItem?.cancel()
                    self.popoverGroup = nil
                }
            }
            .popover(isPresented: isPresentedBinding, attachmentAnchor: .point(.center), arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(popoverGroup?.events ?? []) { event in
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
                                
                                Text(event.calendarName)
                                    .font(.caption)
                                    .foregroundColor(event.color)
                                
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
                        .padding(.vertical, 4)
                        .background(Color.clear)
                    }
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

struct TriangleShape: Shape {
    var isLeftAligned: Bool // This will determine the direction of the arrow

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if isLeftAligned {
            // Tip at (rect.maxX, rect.midY)
            // Base at (rect.minX, rect.minY) and (rect.minX, rect.maxY)
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        } else {
            // Tip at (rect.minX, rect.midY)
            // Base at (rect.maxX, rect.minY) and (rect.maxX, rect.maxY)
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}