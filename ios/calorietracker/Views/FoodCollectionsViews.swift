import SwiftUI

/// The Collections list, shown inside the saved-meals sheet (`RecentsView`) so a
/// collection item logs through the same review flow as a favorite.
struct FoodCollectionsSection: View {
    let searchText: String
    let onLog: (FoodEntry) -> Void

    @State private var store = FoodCollectionStore.shared
    @State private var isNaming = false
    @State private var newName = ""
    @State private var pendingDelete: FoodCollection?

    private var visibleCollections: [FoodCollection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.collections }
        func matches(_ text: String) -> Bool {
            text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return store.collections.filter { matches($0.name) || $0.items.contains { matches($0.name) } }
    }

    var body: some View {
        Section {
            if visibleCollections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.calorie.opacity(0.4))
                    Text(searchText.isEmpty
                         ? String(localized: "No collections yet\nGroup foods you pick from often, like work snacks")
                         : String(localized: "No matching collections"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(AppColors.appCard)
            } else {
                ForEach(visibleCollections) { collection in
                    NavigationLink {
                        FoodCollectionDetailView(collectionID: collection.id, onLog: onLog)
                    } label: {
                        FoodCollectionRow(collection: collection)
                    }
                    .listRowBackground(AppColors.appCard)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = collection
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }

        Section {
            Button {
                newName = ""
                isNaming = true
            } label: {
                Label("New Collection", systemImage: "folder.badge.plus")
                    .font(.system(.body, design: .rounded, weight: .medium))
            }
            .listRowBackground(AppColors.appCard)
            .disabled(store.isPersistenceBlocked)
        }
        .onAppear { store.reload() }
        .alert("New Collection", isPresented: $isNaming) {
            TextField("Work snacks", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Create") { store.create(named: newName) }
        }
        .confirmationDialog(
            String(localized: "Delete \(pendingDelete?.name ?? "")?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let pendingDelete { withAnimation { store.delete(pendingDelete.id) } }
                pendingDelete = nil
            }
        } message: {
            Text("The foods stay in your diary and favorites.")
        }
    }
}

private struct FoodCollectionRow: View {
    let collection: FoodCollection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(AppColors.calorie)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text([collection.items.count == 1 ? String(localized: "1 food") : String(localized: "\(collection.items.count) foods"),
                      collection.availabilitySummary].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One collection: tap a food to log it; add, remove, reorder, rename or delete.
struct FoodCollectionDetailView: View {
    let collectionID: UUID
    let onLog: (FoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = FoodCollectionStore.shared
    @State private var isPicking = false
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isConfirmingDelete = false

    private var collection: FoodCollection? { store.collection(id: collectionID) }

    var body: some View {
        List {
            if let collection {
                if collection.items.isEmpty {
                    Section {
                        Button {
                            isPicking = true
                        } label: {
                            Label("Add foods from Favorites, Frequent or Recent", systemImage: "plus.circle.fill")
                        }
                        .listRowBackground(AppColors.appCard)
                    } footer: {
                        Text("Or tap + to photograph what's there, like a snack drawer or vending machine, or scan a barcode.")
                    }
                } else {
                    Section {
                        ForEach(collection.items) { item in
                            FoodCollectionItemRow(entry: item, accessory: "plus.circle.fill")
                                .listRowBackground(AppColors.appCard)
                                .contentShape(Rectangle())
                                .onTapGesture { onLog(item) }
                        }
                        .onDelete { store.removeItems(at: $0, from: collectionID) }
                        .onMove { store.moveItems(from: $0, to: $1, in: collectionID) }
                    }
                }
                Section {
                    NavigationLink {
                        CollectionPlaceView(collectionID: collectionID)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Place & Schedule", systemImage: "location.circle")
                            Text(collection.availabilitySummary ?? String(localized: "Show this on Home at a place, like the office"))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(AppColors.appCard)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle(collection?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                CollectionAddMenu(collectionID: collectionID)
                Menu {
                    EditButton()
                    Button {
                        newName = collection?.name ?? ""
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPicking) {
            FoodCollectionPicker(collectionID: collectionID)
        }
        .alert("Rename Collection", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { store.rename(collectionID, to: newName) }
        }
        .confirmationDialog(
            String(localized: "Delete \(collection?.name ?? "")?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                store.delete(collectionID)
                dismiss()
            }
        } message: {
            Text("The foods stay in your diary and favorites.")
        }
    }
}

/// Picks foods for a collection from Favorites, Frequent and Recent; tap toggles membership.
struct FoodCollectionPicker: View {
    let collectionID: UUID

    @Environment(FoodStore.self) private var foodStore
    @Environment(\.dismiss) private var dismiss
    @State private var store = FoodCollectionStore.shared
    @State private var searchText = ""

    private func filtered(_ entries: [FoodEntry]) -> [FoodEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return entries.filter { entry in
            guard seen.insert(entry.favoriteKey).inserted else { return false }
            return query.isEmpty || entry.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        let favorites = filtered(foodStore.favorites)
        let frequent = filtered(foodStore.frequentGroups(days: 90).map(\.template))
        let recent = filtered(foodStore.recentEntries(days: 30))
        NavigationStack {
            List {
                section("Favorites", favorites)
                section("Frequent", frequent)
                section("Recent", recent)
                if favorites.isEmpty, frequent.isEmpty, recent.isEmpty {
                    Text(searchText.isEmpty ? "Log a few foods first, then add them here." : "No matching foods")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppColors.appCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle(store.collection(id: collectionID)?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search foods"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ entries: [FoodEntry]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    let isIn = store.contains(entry, in: collectionID)
                    FoodCollectionItemRow(entry: entry, accessory: isIn ? "checkmark.circle.fill" : "circle")
                        .listRowBackground(AppColors.appCard)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { store.toggle(entry, in: collectionID) } }
                }
            }
        }
    }
}

private struct FoodCollectionItemRow: View {
    let entry: FoodEntry
    let accessory: String
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji ?? "🍽️")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "\(energyUnit.format(kcal: entry.calories)) · P \(Int(entry.protein.rounded())) · C \(Int(entry.carbs.rounded())) · F \(Int(entry.fat.rounded()))"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: accessory)
                .font(.title3)
                .foregroundStyle(AppColors.calorie)
        }
    }
}
