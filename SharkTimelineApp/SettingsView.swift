import SwiftUI

struct SettingsView: View {
    // 使用 @AppStorage 直接将UI与UserDefaults中的数据绑定
    // 我们存储的是秒数 (TimeInterval)，默认值为 900秒 (15分钟)
    @AppStorage("refreshInterval") private var refreshInterval: TimeInterval = 900

    // 定义可用的选项
    private let intervalOptions: [(name: String, value: TimeInterval)] = [
        ("5分钟", 300),
        ("15分钟", 900),
        ("30分钟", 1800),
        ("1小时", 3600)
    ]

    var body: some View {
        Form {
            Picker("刷新间隔", selection: $refreshInterval) {
                ForEach(intervalOptions, id: \.value) { option in
                    Text(option.name).tag(option.value)
                }
            }
            .onChange(of: refreshInterval) {
                // 当值改变时，发送通知
                NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
            }
        }
        .padding()
        .frame(width: 300, height: 100)
    }
}
