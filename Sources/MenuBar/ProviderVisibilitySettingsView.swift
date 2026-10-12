import SwiftUI
import CLIProxyBarCore

struct ProviderVisibilitySettingsView: View {
    @Bindable var preferences: DisplayPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Providers").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Provider").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Menu bar").frame(width: 74)
                    Text("Drop-down").frame(width: 74)
                }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(preferences.availableProviders) { provider in
                    GridRow {
                        Text(preferences.providerName(provider))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(preferences.providerName(provider))
                        Toggle("Show \(preferences.providerName(provider)) in the menu bar", isOn: Binding(
                            get: { preferences.showsInMenuBar(provider) },
                            set: { preferences.setMenuBarVisible($0, for: provider) }
                        ))
                        .toggleStyle(.checkbox).labelsHidden().frame(width: 74)
                        .help("Show \(preferences.providerName(provider)) in the menu bar")
                        Toggle("Show \(preferences.providerName(provider)) in the drop-down", isOn: Binding(
                            get: { preferences.showsInDropdown(provider) },
                            set: { preferences.setDropdownVisible($0, for: provider) }
                        ))
                        .toggleStyle(.checkbox).labelsHidden().frame(width: 74)
                        .help("Show \(preferences.providerName(provider)) in the drop-down")
                    }
                }
            }
            Text("Visibility does not change quota refreshes or your alert settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
