import PhotosUI
import SwiftUI

/// What a collection scan reads: a photo of what is on hand, or one barcode.
enum CollectionScanInput: Identifiable {
    case photo(UIImage)
    case barcode(String)

    var id: String {
        switch self {
        case .photo(let image): "photo-\(ObjectIdentifier(image).hashValue)"
        case .barcode(let code): "barcode-\(code)"
        }
    }
}

/// The + menu on a collection: saved foods, a photo of what is on hand, or a barcode.
struct CollectionAddMenu: View {
    let collectionID: UUID

    @State private var isPicking = false
    @State private var showCamera = false
    @State private var showBarcode = false
    @State private var capturedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var scan: CollectionScanInput?
    @State private var pending: CollectionScanInput?

    private func presentPending() {
        scan = pending
        pending = nil
    }

    var body: some View {
        Menu {
            Button { isPicking = true } label: {
                Label("From Favorites, Frequent or Recent", systemImage: "clock.arrow.circlepath")
            }
            Button { showCamera = true } label: {
                Label("Take a photo of what's there", systemImage: "camera")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
            }
            Button { showBarcode = true } label: {
                Label("Scan a barcode", systemImage: "barcode.viewfinder")
            }
        } label: {
            Label("Add Foods", systemImage: "plus")
        }
        .sheet(isPresented: $isPicking) {
            FoodCollectionPicker(collectionID: collectionID)
        }
        // The review sheet is presented only once the camera or scanner is gone.
        .fullScreenCover(isPresented: $showCamera, onDismiss: presentPending) {
            CameraView(image: $capturedImage, onCancel: { showCamera = false }).ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showBarcode, onDismiss: presentPending) {
            BarcodeScannerView(
                onScan: { code in
                    pending = .barcode(code)
                    showBarcode = false
                },
                onCancel: { showBarcode = false }
            )
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            pending = .photo(image)
            showCamera = false
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    scan = .photo(image)
                }
            }
        }
        .sheet(item: $scan) { input in
            NavigationStack {
                CollectionScanReviewView(collectionID: collectionID, input: input)
            }
        }
    }
}

/// Reads the photo or barcode, then lets the user tick which foods to add.
struct CollectionScanReviewView: View {
    let collectionID: UUID
    let input: CollectionScanInput

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodStore.self) private var foodStore
    @State private var store = FoodCollectionStore.shared
    @State private var found: [FoodEntry] = []
    @State private var selected: Set<UUID> = []
    @State private var isWorking = true
    @State private var error: String?

    var body: some View {
        List {
            if isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(isBarcode ? "Looking up the barcode…" : "Finding the foods…")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            } else if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            } else {
                Section {
                    ForEach(found) { entry in
                        let inCollection = store.contains(entry, in: collectionID)
                        ScannedFoodRow(entry: entry, inCollection: inCollection, isSelected: selected.contains(entry.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !inCollection else { return }
                                if !selected.insert(entry.id).inserted { selected.remove(entry.id) }
                            }
                            .listRowBackground(AppColors.appCard)
                    }
                } footer: {
                    Text("Nutrition is an estimate per serving. You can adjust a food when you log it.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle(store.collection(id: collectionID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(selected.count == 1 ? String(localized: "Add 1") : String(localized: "Add \(selected.count)")) {
                    store.addItems(found.filter { selected.contains($0.id) }, to: collectionID)
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
        }
        .task { await run() }
    }

    private var isBarcode: Bool {
        if case .barcode = input { return true }
        return false
    }

    private func run() async {
        guard found.isEmpty else { return }
        do {
            switch input {
            case .photo(let image):
                found = try await CollectionScanService.scan(image)
            case .barcode(let code):
                let analysis = try await BarcodeProductLookup.lookup(
                    barcode: code,
                    savedLabelEntries: foodStore.entries,
                    usdaAPIKey: FoodDataCentralSettings.apiKey,
                    includesProductImage: false
                ).analysis
                found = [VoiceAssistantFoodBuilder.entry(from: analysis, images: [], source: .barcode, servings: 1,
                                                         timestamp: Date(), mealType: .snack)]
            }
            selected = Set(found.filter { !store.contains($0, in: collectionID) }.map(\.id))
        } catch {
            self.error = isBarcode
                ? String(localized: "Couldn't find that product. Try a photo instead.")
                : String(localized: "Couldn't read foods from that photo. Try a closer shot with the labels showing.")
        }
        isWorking = false
    }
}

private struct ScannedFoodRow: View {
    let entry: FoodEntry
    let inCollection: Bool
    let isSelected: Bool
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    private var detail: String {
        inCollection
            ? String(localized: "Already in this collection")
            : ([energyUnit.format(kcal: entry.calories)] + [entry.servingSizeGrams.map { FoodUnits.weightText(grams: $0) }].compactMap { $0 })
                .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji ?? "🍽️").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(AppColors.calorie)
        }
        .opacity(inCollection ? 0.5 : 1)
    }
}
