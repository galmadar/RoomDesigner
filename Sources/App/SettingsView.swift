import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address: String = PlanService.baseURLOverride?.absoluteString ?? ""

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Where the pictures\ncome from").question()
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 18)

                        TextField(PlanService.defaultBaseURL.absoluteString, text: $address)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17))
                            .foregroundStyle(Paper.ink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 56)
                            .paperCard()
                            .padding(.horizontal, 20)

                        Text("The small service that holds the API key and generates the pictures. Leave this empty to use the built-in service — fill it in only to point the app at your own.")
                            .font(.system(size: 13))
                            .foregroundStyle(Paper.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16))
                        .foregroundStyle(Paper.secondaryInk)
                }
            }
        }
    }

    private func save() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        PlanService.baseURLOverride = trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}
