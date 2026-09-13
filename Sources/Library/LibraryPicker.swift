import SwiftData
import SwiftUI

/// Chooses one product from the shared library.
struct LibraryPicker: View {
    let title: String
    let footnote: String
    /// Why a product can't be chosen here, or nil if it can.
    var unavailable: (LibraryObject) -> String? = { _ in nil }
    let onPick: (LibraryObject) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibraryObject.createdAt, order: .reverse) private var objects: [LibraryObject]
    @StateObject private var thumbnails = ProductThumbnails()

    var body: some View {
        NavigationStack {
            ZStack {
                Paper.sheet.ignoresSafeArea()
                if objects.isEmpty { empty } else { list }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Paper.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16))
                        .foregroundStyle(Paper.secondaryInk)
                }
            }
            .task(id: objects.map(\.id)) { await thumbnails.load(objects) }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "sofa")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Paper.mutedInk)
            Text("Your library is empty")
                .question()
                .multilineTextAlignment(.center)
            Text("Add products from the Library button on the Rooms screen, then come back here.")
                .font(.system(size: 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(objects) { row($0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Text(footnote)
                .font(.system(size: 13))
                .foregroundStyle(Paper.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
    }

    private func row(_ object: LibraryObject) -> some View {
        let reason = unavailable(object)
        return Button {
            onPick(object)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                FilledImage(image: thumbnails.images[object.id], symbol: "photo")
                    .frame(width: 76, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(object.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                        .lineLimit(2)
                    Text(reason ?? object.furnitureKind?.label ?? "No floor shape")
                        .font(.system(size: 13))
                        .foregroundStyle(Paper.secondaryInk)
                        .lineLimit(2)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 84)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard()
            .opacity(reason == nil ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .accessibilityLabel(object.name)
    }
}
