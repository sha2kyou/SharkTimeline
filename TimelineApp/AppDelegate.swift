// AppDelegate.swift
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    
    // 定义刷新间隔的选项
    private let intervalOptions: [(name: String, value: TimeInterval)] = [
        ("5分钟", 300),
        ("15分钟", 900),
        ("30分钟", 1800),
        ("1小时", 3600)
    ]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let contentView = ContentView()

        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: screenRect.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false

        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        setupMenuBar()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "Timeline App")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self // 设置代理，用于在菜单打开前更新状态
        
        // --- 创建刷新间隔子菜单 ---
        let intervalMenu = NSMenu()
        for option in intervalOptions {
            let menuItem = NSMenuItem(
                title: option.name,
                action: #selector(intervalSelected(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            // 将秒数存入 representedObject 以便在点击时获取
            menuItem.representedObject = option.value
            intervalMenu.addItem(menuItem)
        }
        
        let intervalParentItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        intervalParentItem.submenu = intervalMenu
        menu.addItem(intervalParentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- 创建退出菜单项 ---
        let quitItem = NSMenuItem(
            title: "Quit TimelineApp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // 菜单即将打开时，系统会调用这个代理方法
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 读取当前保存的间隔值，默认为900
        let currentInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        let effectiveInterval = currentInterval > 0 ? currentInterval : 900
        
        // 遍历子菜单，更新对勾状态
        if let intervalMenu = menu.item(withTitle: "刷新间隔")?.submenu {
            for item in intervalMenu.items {
                if let itemInterval = item.representedObject as? TimeInterval {
                    item.state = (itemInterval == effectiveInterval) ? .on : .off
                }
            }
        }
    }
    
    // 当点击某个间隔选项时调用
    @objc func intervalSelected(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        
        // 保存新值到 UserDefaults
        UserDefaults.standard.set(interval, forKey: "refreshInterval")
        
        // 发送通知，让 EventManager 更新计时器
        NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
    }
}
