import SwiftUI

/// Builds a coffee-bar drink: drink, size, milk, hot or iced, syrup. Logging remembers it as
/// the usual order.
struct CoffeeBarView: View {
    let onLog: (FoodEntry) -> Void

    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit
    @State private var order = CoffeeUsual.load() ?? CoffeeOrder()

    var body: some View {
        let entry = order.entry()
        Form {
            Section("Drink") {
                Picker("Drink", selection: Binding(
                    get: { order.drink },
                    set: { drink in
                        order.drink = drink
                        // Black drinks start without milk; milk drinks start with whole.
                        if drink.isMilkDrink, order.milk == .none { order.milk = .whole }
                        if !drink.isMilkDrink { order.milk = .none }
                    }
                )) {
                    ForEach(CoffeeDrink.allCases) { drink in
                        Text("\(drink.emoji) \(drink.displayName)").tag(drink)
                    }
                }
                .pickerStyle(.navigationLink)
                Picker("Size", selection: $order.size) {
                    ForEach(CoffeeSize.allCases) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Iced", isOn: $order.iced)
            }
            Section {
                Picker(order.drink.isMilkDrink ? "Milk" : "Splash of milk", selection: $order.milk) {
                    ForEach(CoffeeMilk.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper(order.syrupPumps == 0 ? String(localized: "No syrup")
                        : order.syrupPumps == 1 ? String(localized: "1 pump syrup") : String(localized: "\(order.syrupPumps) pumps syrup"),
                        value: $order.syrupPumps, in: 0...8)
            } header: {
                Text("Make it")
            }
            Section {
                LabeledContent(entry.name, value: energyUnit.format(kcal: entry.calories))
                LabeledContent("Sugar (total)", value: "\(Int((entry.sugar ?? 0).rounded())) g")
                LabeledContent("of which added", value: "\(Int((entry.addedSugar ?? 0).rounded())) g")
                LabeledContent("Protein", value: "\(Int(entry.protein.rounded())) g")
                LabeledContent("Caffeine", value: "\(Int((entry.caffeine ?? 0).rounded())) mg")
            } header: {
                Text("Estimate")
            } footer: {
                Text("Total sugar includes what's natural in milk; added sugar is the part from syrup and sweetened powders, which is what guidelines limit. Typical café recipes; brands vary, so edit the entry in your diary if yours differs.")
            }
        }
        .navigationTitle("Coffee Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") {
                    CoffeeUsual.save(order)
                    onLog(order.entry())
                }
            }
        }
    }
}

/// The "what's here" part of a collection: kinds of food place, each with an order screen
/// (coffee bar) or a typical menu, and a free-text note.
struct CollectionExtrasSection: View {
    let collectionID: UUID
    let onLog: (FoodEntry) -> Void

    @State private var store = FoodCollectionStore.shared
    @State private var note = ""
    @FocusState private var editingNote: Bool

    var body: some View {
        let collection = store.collection(id: collectionID)
        let kinds = collection?.placeKinds ?? []
        Section {
            ForEach(kinds) { kind in
                NavigationLink {
                    if kind.known == .coffeeBar {
                        CoffeeBarView(onLog: onLog)
                    } else {
                        TypicalMenuView(collectionID: collectionID, kind: kind, onLog: onLog)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(kind.displayName, systemImage: kind.systemImage)
                        Text(detail(for: kind, in: collection))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { store.toggleKind(kinds[index].raw, for: collectionID) }
            }
            NavigationLink {
                PlaceKindPicker(collectionID: collectionID)
            } label: {
                Label(kinds.isEmpty ? "Add a kind of place" : "Change kinds", systemImage: "plus.circle.fill")
            }
            LabeledContent {
                TextField("e.g. fruit basket, salad bar Tuesdays", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($editingNote)
                    .onSubmit { store.setAlsoHere(note, for: collectionID) }
                    .onChange(of: editingNote) { _, focused in
                        if !focused { store.setAlsoHere(note, for: collectionID) }
                    }
            } label: {
                Label("Also here", systemImage: "basket")
            }
        } header: {
            Text("What's here")
        } footer: {
            Text("Suggestions and Coach assume anything typical of these kinds of place is available. Each kind has a typical menu to log from; the coffee bar builds your exact drink.")
        }
        .listRowBackground(AppColors.appCard)
        .onAppear { note = collection?.alsoHere ?? "" }
        .onDisappear { store.setAlsoHere(note, for: collectionID) }
    }

    private func detail(for kind: PlaceKindKey, in collection: FoodCollection?) -> String {
        if kind.known == .coffeeBar { return String(localized: "Order a drink") }
        let count = collection?.typicalMenu(for: kind).count ?? 0
        return count == 0 ? String(localized: "Typical menu") : String(localized: "Typical menu · \(count) items")
    }
}

/// Picks the kinds of food place a collection has; any kind can be the user's own words.
private struct PlaceKindPicker: View {
    let collectionID: UUID

    @State private var store = FoodCollectionStore.shared
    @State private var custom = ""

    var body: some View {
        let selected = Set(store.collection(id: collectionID)?.placeKinds.map(\.raw) ?? [])
        let own = (store.collection(id: collectionID)?.placeKinds ?? []).filter { $0.known == nil }
        List {
            Section {
                ForEach(PlaceKind.allCases) { kind in
                    row(kind.displayName, systemImage: kind.systemImage, isOn: selected.contains(kind.rawValue)) {
                        store.toggleKind(kind.rawValue, for: collectionID)
                    }
                }
            } footer: {
                Text("Pick every kind that's here, e.g. a coffee bar and a vending machine.")
            }
            .listRowBackground(AppColors.appCard)
            Section {
                ForEach(own) { kind in
                    row(kind.displayName, systemImage: kind.systemImage, isOn: true) {
                        store.toggleKind(kind.raw, for: collectionID)
                    }
                }
                HStack {
                    TextField("e.g. sushi counter, taco truck", text: $custom)
                        .onSubmit(addCustom)
                    Button("Add", action: addCustom)
                        .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Other")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("What's Here")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addCustom() {
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = store.collection(id: collectionID)?.placeKinds.map(\.raw) ?? []
        if !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            store.toggleKind(trimmed, for: collectionID)
        }
        custom = ""
    }

    private func row(_ title: String, systemImage: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(AppColors.calorie)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { toggle() } }
    }
}

/// A typical menu for a kind of place, written once by the AI and saved on the collection.
/// Tap a food to log it; swipe to keep it in the collection.
struct TypicalMenuView: View {
    let collectionID: UUID
    let kind: PlaceKindKey
    let onLog: (FoodEntry) -> Void

    @Environment(FoodStore.self) private var foodStore
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit
    @State private var store = FoodCollectionStore.shared
    @State private var isWorking = false
    @State private var error: String?

    private var menu: [FoodEntry] { store.collection(id: collectionID)?.typicalMenu(for: kind) ?? [] }

    var body: some View {
        List {
            if kind.known?.prefersScan == true {
                Section {
                    Label("For what's actually stocked, go back, tap + and take a photo of it.", systemImage: "camera.viewfinder")
                        .font(.system(.subheadline, design: .rounded))
                }
                .listRowBackground(AppColors.appCard)
            }
            if isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Writing a typical menu…").foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            } else if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            }
            if !menu.isEmpty {
                Section {
                    ForEach(menu) { item in
                        let kept = store.contains(item, in: collectionID)
                        HStack(spacing: 12) {
                            Text(item.emoji ?? "🍽️").font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text(energyUnit.format(kcal: item.calories) + (kept ? " · " + String(localized: "in this collection") : ""))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppColors.calorie)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onLog(item) }
                        .swipeActions(edge: .trailing) {
                            if !kept {
                                Button { store.addItems([item], to: collectionID) } label: {
                                    Label("Keep", systemImage: "folder.badge.plus")
                                }
                                .tint(AppColors.calorie)
                            }
                        }
                        .listRowBackground(AppColors.appCard)
                    }
                } footer: {
                    Text("What's typical at this kind of place, estimated per serving; yours may differ. Tap to log, swipe to keep one in the collection.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { generate() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking)
            }
        }
        .task {
            if menu.isEmpty, !isWorking, error == nil { generate() }
        }
    }

    private func generate() {
        isWorking = true
        error = nil
        Task {
            do {
                let entries = try await TypicalMenuService.menu(
                    for: kind, healthLines: HealthContextPrompt.lines(foods: foodStore.entries, plan: [], onHand: [])
                )
                store.setTypicalMenu(entries, for: kind.raw, in: collectionID)
            } catch {
                self.error = GeminiService.analysisErrorMessage(error)
            }
            isWorking = false
        }
    }
}
