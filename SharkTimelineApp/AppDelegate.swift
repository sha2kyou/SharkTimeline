// AppDelegate.swift
import Cocoa
import SwiftUI
import ServiceManagement // 引入 ServiceManagement 框架
import EventKit // Added EventKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    
    private let eventStore = EKEventStore() // Added EventStore instance
    private var selectedCalendarIDs: [String] = [] // Managed manually with UserDefaults
    
    private let intervalOptions: [(name: String, value: TimeInterval)] = [
        ("5分钟", 300),
        ("15分钟", 900),
        ("30分钟", 1800),
        ("1小时", 3600)
    ]
    
    private let positionOptions: [(name: String, value: String)] = [
        ("左侧", "left"),
        ("右侧", "right")
    ]

    var eventManager: EventManager! // Add this property

    var aboutWindow: NSWindow?
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize EventManager
        eventManager = EventManager()

        let contentView = ContentView()
            .environmentObject(eventManager)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 5, height: NSScreen.main?.frame.height ?? 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true

        updateWindowPosition()
        
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        setupMenuBar()
        
        // Register for screen parameter change notifications
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        // 注册工作区通知
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveWakeNote(note:)), name: NSWorkspace.didWakeNotification, object: nil)
    }
    
    @objc func receiveWakeNote(note: NSNotification) {
        // 当屏幕解锁时，执行刷新操作
        refreshNow()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Timeline App")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func statusItemClicked(sender: NSStatusItem) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let aboutItem = NSMenuItem(title: "关于", action: #selector(showAboutWindow), keyEquivalent: "")
            aboutItem.target = self
            menu.addItem(aboutItem)
            statusItem?.popUpMenu(menu)
        } else {
            let menu = constructMenu()
            statusItem?.popUpMenu(menu)
        }
    }

    func constructMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        
        // --- 组1: 立即刷新 ---
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())

        // --- 组2: 日历 ---
        let calendarMenu = NSMenu()
        let calendarParentItem = NSMenuItem(title: "日历", action: nil, keyEquivalent: "")
        calendarParentItem.submenu = calendarMenu
        menu.addItem(calendarParentItem)

        menu.addItem(NSMenuItem.separator())
        
        // --- 组3: 设置 ---
        let positionMenu = NSMenu()
        for option in positionOptions {
            let menuItem = NSMenuItem(title: option.name, action: #selector(positionSelected(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = option.value
            positionMenu.addItem(menuItem)
        }
        let positionParentItem = NSMenuItem(title: "侧栏位置", action: nil, keyEquivalent: "")
        positionParentItem.submenu = positionMenu
        menu.addItem(positionParentItem)

        let displayMenu = NSMenu()
        let displayParentItem = NSMenuItem(title: "显示器", action: nil, keyEquivalent: "")
        displayParentItem.submenu = displayMenu
        menu.addItem(displayParentItem)
        
        let intervalMenu = NSMenu()
        for option in intervalOptions {
            let menuItem = NSMenuItem(title: option.name, action: #selector(intervalSelected(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = option.value
            intervalMenu.addItem(menuItem)
        }
        let intervalParentItem = NSMenuItem(title: "后台刷新间隔", action: nil, keyEquivalent: "")
        intervalParentItem.submenu = intervalMenu
        menu.addItem(intervalParentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- 组4: 应用 ---
        let launchAtLoginItem = NSMenuItem(title: "开机自启动", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        return menu
    }

    @objc func showAboutWindow() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "关于 SharkTimeline"
            newWindow.styleMask = [.titled, .closable]
            newWindow.center()
            self.aboutWindow = newWindow
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 更新位置菜单的对勾
        let currentPosition = UserDefaults.standard.string(forKey: "timelinePosition") ?? "left"
        if let positionMenu = menu.item(withTitle: "侧栏位置")?.submenu {
            for item in positionMenu.items {
                if let itemPosition = item.representedObject as? String {
                    item.state = (itemPosition == currentPosition) ? .on : .off
                }
            }
        }
        
        // 更新刷新间隔菜单的对勾
        let currentInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        let effectiveInterval = currentInterval > 0 ? currentInterval : 900
        if let intervalMenu = menu.item(withTitle: "后台刷新间隔")?.submenu {
            for item in intervalMenu.items {
                if let itemInterval = item.representedObject as? TimeInterval {
                    item.state = (itemInterval == effectiveInterval) ? .on : .off
                }
            }
        }
        
        // Load selectedCalendarIDs from UserDefaults
        selectedCalendarIDs = UserDefaults.standard.array(forKey: "selectedCalendarIDs") as? [String] ?? []

        // 更新日历菜单
        if let calendarMenu = menu.item(withTitle: "日历")?.submenu {
            calendarMenu.removeAllItems() // 清除旧的菜单项
            
            // 检查日历访问权限
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess, .authorized:
                let availableCalendars = eventStore.calendars(for: .event).sorted { $0.title < $1.title }
                
                // 如果 selectedCalendarIDs 为空，则默认全选
                if selectedCalendarIDs.isEmpty {
                    selectedCalendarIDs = availableCalendars.map { $0.calendarIdentifier }
                    UserDefaults.standard.set(selectedCalendarIDs, forKey: "selectedCalendarIDs") // Save default selection
                }
                
                for calendar in availableCalendars {
                    let menuItem = NSMenuItem(title: calendar.title, action: #selector(calendarSelected(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = calendar.calendarIdentifier
                    menuItem.state = selectedCalendarIDs.contains(calendar.calendarIdentifier) ? .on : .off
                    calendarMenu.addItem(menuItem)
                }
            case .notDetermined:
                let requestAccessItem = NSMenuItem(title: "请求日历访问权限...", action: #selector(requestCalendarAccess), keyEquivalent: "")
                requestAccessItem.target = self
                calendarMenu.addItem(requestAccessItem)
            case .writeOnly, .denied, .restricted:
                let deniedItem = NSMenuItem(title: "日历访问权限被拒绝", action: nil, keyEquivalent: "")
                calendarMenu.addItem(deniedItem)
            @unknown default:
                let unknownItem = NSMenuItem(title: "未知日历状态", action: nil, keyEquivalent: "")
                calendarMenu.addItem(unknownItem)
            }
        }
        
        // 更新显示器菜单
        if let displayMenu = menu.item(withTitle: "显示器")?.submenu {
            displayMenu.removeAllItems() // 清除旧的菜单项
            let screens = NSScreen.screens
            let preferredScreenID = UserDefaults.standard.string(forKey: "preferredScreenIdentifier")
            
            for (index, screen) in screens.enumerated() {
                let menuItem = NSMenuItem(title: screen.localizedName, action: #selector(screenSelected(_:)), keyEquivalent: "")
                menuItem.target = self
                // Use screen.deviceDescription as a unique identifier for the screen
                if let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    menuItem.representedObject = screenID.stringValue
                } else {
                    menuItem.representedObject = "screen_\(index)" // Fallback identifier
                }
                
                if let itemScreenID = menuItem.representedObject as? String, itemScreenID == preferredScreenID {
                    menuItem.state = .on
                } else if preferredScreenID == nil && (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue == (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue {
                    // If no preferred screen is set, mark the main screen as selected
                    menuItem.state = .on
                } else {
                    menuItem.state = .off
                }
                displayMenu.addItem(menuItem)
            }
        }
        
        // 更新开机自启动的勾选状态
        if let launchAtLoginItem = menu.item(withTitle: "开机自启动") {
            var isLaunchAtLoginEnabled = false
            if #available(macOS 13.0, *) {
                isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            } else {
                // Fallback on earlier versions
                isLaunchAtLoginEnabled = UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
            }
            launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        }
    }
    
    @objc func refreshNow() {
        NotificationCenter.default.post(name: .manualRefreshRequested, object: nil)
    }
    
    @objc func positionSelected(_ sender: NSMenuItem) {
        guard let position = sender.representedObject as? String else { return }
        UserDefaults.standard.set(position, forKey: "timelinePosition")
        updateWindowPosition()
    }
    
    @objc func intervalSelected(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        UserDefaults.standard.set(interval, forKey: "refreshInterval")
        NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
    }

    @objc func screenSelected(_ sender: NSMenuItem) {
        guard let screenID = sender.representedObject as? String else { return }
        UserDefaults.standard.set(screenID, forKey: "preferredScreenIdentifier")
        updateWindowPosition()
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = (sender.state == .off) ? NSControl.StateValue.on : .off
        let enable = (newState == .on)

        Task { @MainActor in
            do {
                if enable {
                    if #available(macOS 13.0, *) {
                        try SMAppService.mainApp.register()
                    } else {
                        // Fallback on earlier versions
                        guard let bundleID = Bundle.main.bundleIdentifier else {
                            return
                        }
                        _ = SMLoginItemSetEnabled(bundleID as CFString, true)
                    }
                } else {
                    if #available(macOS 13.0, *) {
                        try SMAppService.mainApp.unregister()
                    } else {
                        // Fallback on earlier versions
                        guard let bundleID = Bundle.main.bundleIdentifier else {
                            return
                        }
                        _ = SMLoginItemSetEnabled(bundleID as CFString, false)
                    }
                }
                sender.state = newState
                UserDefaults.standard.set(enable, forKey: "launchAtLoginEnabled") // 更新 UserDefaults 状态
            } catch {
                print("设置开机自启动失败：\(error.localizedDescription)")
                // 失败时，将 UI 状态恢复到之前，避免误导用户
                sender.state = (enable) ? .off : .on
                UserDefaults.standard.set(!enable, forKey: "launchAtLoginEnabled")
            }
        }
    }
    
    func updateWindowPosition() {
        guard let window = self.window else { return }

        var targetScreen: NSScreen? = nil
        if let preferredScreenID = UserDefaults.standard.string(forKey: "preferredScreenIdentifier") {
            for screen in NSScreen.screens {
                if let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                   screenID.stringValue == preferredScreenID {
                    targetScreen = screen
                    break
                }
            }
        }

        // If no preferred screen is found or it's disconnected, default to the main screen
        if targetScreen == nil {
            targetScreen = NSScreen.main
            // Do not clear the preferred screen setting if it's no longer available, so it can be re-selected if it reconnects
        }

        guard let screen = targetScreen else { return }

        let position = UserDefaults.standard.string(forKey: "timelinePosition") ?? "left"

        let newX = (position == "right") ? (screen.frame.minX + screen.frame.width - window.frame.width) : screen.frame.minX
        window.setFrame(NSRect(x: newX, y: screen.frame.minY, width: window.frame.width, height: screen.frame.height), display: true)
    }

    @objc func calendarSelected(_ sender: NSMenuItem) {
        guard let calendarIdentifier = sender.representedObject as? String else { return }
        
        if selectedCalendarIDs.contains(calendarIdentifier) {
            selectedCalendarIDs.removeAll(where: { $0 == calendarIdentifier })
        } else {
            selectedCalendarIDs.append(calendarIdentifier)
        }
        
        // Save selectedCalendarIDs to UserDefaults
        UserDefaults.standard.set(selectedCalendarIDs, forKey: "selectedCalendarIDs")
        
        // Post notification when calendar selection changes
        NotificationCenter.default.post(name: .selectedCalendarsChanged, object: nil)
        
        // Update menu checkmarks
        statusItem?.menu?.update()
    }
    
    @objc func requestCalendarAccess() {
        eventManager.requestAccess { [weak self] granted in
            if granted {
                // Manually trigger a refresh so the UI updates.
                NotificationCenter.default.post(name: .manualRefreshRequested, object: nil)
                
                // The menu will update on its next opening via the menuNeedsUpdate delegate method.
                // To be safe and provide immediate feedback if the menu were to somehow stay open,
                // we can also call update().
                DispatchQueue.main.async {
                    self?.statusItem?.menu?.update()
                }
            }
        }
    }

    @objc func screenParametersDidChange(_ notification: Notification) {
        updateWindowPosition()
        statusItem?.menu?.update() // Refresh the menu to update screen selection checkmarks
    }
}
