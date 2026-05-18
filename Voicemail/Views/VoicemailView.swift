import SwiftUI

struct VoicemailView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GlassEffectContainer {
                    VStack(spacing: 16) {
                        Image(systemName: "recordingtape")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)
                        Text("语音留言")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("语音留言将显示在此处")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("语音留言")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
