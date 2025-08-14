// TimelineApp.swift
import SwiftUI

@main
struct TimelineApp: App {
    // 注册 AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 我们自己管理窗口，所以这里可以留空或使用一个隐藏的窗口
        Settings {
            SettingsView()
        }
    }
}
