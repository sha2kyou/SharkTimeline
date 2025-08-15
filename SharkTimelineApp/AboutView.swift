
// AboutView.swift
import SwiftUI

struct AboutView: View {
    @State private var showEasterEgg = false

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "版本 \(version) (Build \(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("SharkTimeline")
                .font(.title)
            Text(versionString)
                .font(.body)
            Text(showEasterEgg ? "你需要一艘更大的船！" : "一个在桌面边缘显示日历事件的时间轴应用。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .onTapGesture {
                    showEasterEgg.toggle()
                }
            
            Divider()
            
            Text("© 2025 李慕白. All rights reserved.")
                .font(.footnote)
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
