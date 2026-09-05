import SwiftUI

struct SettingsDisplaySection: View {
    @AppStorage("claudebar.showStatusBarIndicator") private var showStatusBarIndicator: Bool = true
    @AppStorage("claudebar.showIconTinting") private var showIconTinting: Bool = true
    @AppStorage("claudebar.costAlertThreshold") private var costAlertThreshold: Double = 0
    @AppStorage("claudebar.contextAlertThreshold") private var contextAlertThreshold: Double = 90

    var body: some View {
        displaySection()
    }
    @ViewBuilder
    private func displaySection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Status bar indicator toggle
                Toggle(isOn: $showStatusBarIndicator) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status bar indicator")
                            .font(.subheadline)
                        Text("Show the 5h limit forecast and reset countdown next to the menu bar icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Icon tinting toggle
                Toggle(isOn: $showIconTinting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage-based icon tinting")
                            .font(.subheadline)
                        Text("Color the brain icon orange/red when API usage is high")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Cost alert threshold
                HStack {
                    Label("Daily cost alert", systemImage: "dollarsign.circle")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $costAlertThreshold) {
                        Text("Off").tag(0.0)
                        Text("$1").tag(1.0)
                        Text("$5").tag(5.0)
                        Text("$10").tag(10.0)
                        Text("$25").tag(25.0)
                        Text("$50").tag(50.0)
                    }
                    .frame(width: 80)
                }

                // Context compaction alert threshold
                HStack {
                    Label("Context alert", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $contextAlertThreshold) {
                        Text("Off").tag(0.0)
                        Text("80%").tag(80.0)
                        Text("85%").tag(85.0)
                        Text("90%").tag(90.0)
                        Text("95%").tag(95.0)
                    }
                    .frame(width: 80)
                }
            }
            .padding(8)
        } label: {
            SettingsSectionLabel("Display & Alerts")
        }
        .padding(.horizontal, 12)
    }

}

