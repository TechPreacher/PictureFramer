import SwiftUI

/// AI provider configuration: pick a provider, store its API key in the
/// Keychain, optionally validate the key with a cheap authenticated ping.
struct SettingsView: View {
    let settings: ProviderSettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: AIProvider?
    @State private var keys: [AIProvider: String] = [:]
    @State private var validationState: [AIProvider: ValidationState] = [:]

    private let validator = ProviderKeyValidator()

    enum ValidationState: Equatable {
        case validating
        case valid
        case invalid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("None").tag(AIProvider?.none)
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(AIProvider?.some(provider))
                        }
                    }
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text("Reflection removal sends the masked image region to the selected provider. Usage is billed to your own API key.")
                }

                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Section("\(provider.displayName) API Key") {
                        SecureField("API key", text: keyBinding(for: provider))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Button("Validate Key") {
                                Task { await validate(provider) }
                            }
                            .disabled((keys[provider] ?? "").isEmpty
                                      || validationState[provider] == .validating)
                            Spacer()
                            validationLabel(for: provider)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private func validationLabel(for provider: AIProvider) -> some View {
        switch validationState[provider] {
        case .validating:
            ProgressView()
        case .valid:
            Label("Valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Label("Invalid", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private func keyBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: { keys[provider] = $0; validationState[provider] = nil }
        )
    }

    private func load() {
        selectedProvider = settings.selectedProvider
        for provider in AIProvider.allCases {
            keys[provider] = settings.apiKey(for: provider) ?? ""
        }
    }

    private func save() {
        settings.selectedProvider = selectedProvider
        for provider in AIProvider.allCases {
            let key = (keys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            settings.setAPIKey(key.isEmpty ? nil : key, for: provider)
        }
    }

    private func validate(_ provider: AIProvider) async {
        let key = (keys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        validationState[provider] = .validating
        let ok = await validator.validate(provider: provider, apiKey: key)
        validationState[provider] = ok ? .valid : .invalid
    }
}
