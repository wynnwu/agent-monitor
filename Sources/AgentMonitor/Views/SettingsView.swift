import SwiftUI

struct SettingsView: View {
    @Bindable var prefs: HotKeyPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Shortcut").font(.headline)

            Toggle("Enable global shortcut", isOn: $prefs.enabled)

            HStack {
                Text("Shortcut").foregroundStyle(.secondary)
                Spacer()
                ShortcutRecorder(prefs: prefs)
                    .frame(width: 170, height: 26)
            }
            .opacity(prefs.enabled ? 1 : 0.4)
            .disabled(!prefs.enabled)

            Text("Press your shortcut from anywhere to toggle the Agent Monitor popover. Press it again, click away, or hit Esc to close. Off by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
        .environment(\.colorScheme, .dark)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}
