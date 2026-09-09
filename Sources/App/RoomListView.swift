import RoomPlan
import SwiftData
import SwiftUI

struct RoomListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScannedRoom.createdAt, order: .reverse) private var rooms: [ScannedRoom]

    @State private var isScanning = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if rooms.isEmpty {
                    ContentUnavailableView {
                        Label("No rooms yet", systemImage: "arkit")
                    } description: {
                        Text("Scan a room to get started.")
                    } actions: {
                        Button("Scan a room") { isScanning = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(rooms) { room in
                            NavigationLink(value: room) {
                                RoomRow(room: room)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Rooms")
            .navigationDestination(for: ScannedRoom.self) { RoomDetailView(room: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                if !rooms.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isScanning = true } label: { Label("Scan", systemImage: "plus") }
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .fullScreenCover(isPresented: $isScanning) {
                ScanFlowView { captured in
                    let room = ScannedRoom(name: "Room \(rooms.count + 1)")
                    room.capturedRoom = captured
                    context.insert(room)
                }
            }
            .overlay(alignment: .bottom) {
                if !RoomCaptureSession.isSupported {
                    UnsupportedDeviceNotice()
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(rooms[index]) }
    }
}

private struct RoomRow: View {
    let room: ScannedRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name).font(.headline)
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        guard let captured = room.capturedRoom else { return "Not scanned" }
        let area = FloorPlan(room: captured).floorAreaSquareMetres
        return String(format: "%.1f m² · %d objects", area, captured.objects.count)
    }
}

private struct UnsupportedDeviceNotice: View {
    var body: some View {
        Text("This device has no LiDAR scanner, so rooms can't be scanned on it.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
    }
}
