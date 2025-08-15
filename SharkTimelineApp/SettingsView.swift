import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: TimeInterval = 900

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
                NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
            }
        }
        .padding()
        .frame(width: 300, height: 100) // Reverted height
    }
}
