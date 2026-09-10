import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address: String = PlanService.baseURLOverride?.absoluteString ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(PlanService.defaultBaseURL.absoluteString, text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Server address")
                } footer: {
                    Text("The small service that holds the API key and generates the pictures. Leave this empty to use the built-in service — fill it in only to point the app at your own.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        PlanService.baseURLOverride = trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}
