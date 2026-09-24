import SwiftUI

struct SettingsSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Theme.Font.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

