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
                LabeledContent("Sugar", value: "\(Int((entry.sugar ?? 0).rounded())) g")
                if (entry.addedSugar ?? 0) > 0 {
                    LabeledContent("Added sugar", value: "\(Int((entry.addedSugar ?? 0).rounded())) g")
                }
                LabeledContent("Protein", value: "\(Int(entry.protein.rounded())) g")
                LabeledContent("Caffeine", value: "\(Int((entry.caffeine ?? 0).rounded())) mg")
            } header: {
                Text("Estimate")
            } footer: {
                Text("Typical café recipes; brands vary. Edit the entry in your diary if yours differs.")
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

/// The "what's here" part of a collection: a coffee bar and a free-text note.
struct CollectionExtrasSection: View {
    let collectionID: UUID
    let onLog: (FoodEntry) -> Void

    @State private var store = FoodCollectionStore.shared
    @State private var note = ""
    @FocusState private var editingNote: Bool

    var body: some View {
        let collection = store.collection(id: collectionID)
        Section {
            Toggle(isOn: Binding(
                get: { collection?.hasCoffeeBar ?? false },
                set: { store.setCoffeeBar($0, for: collectionID) }
            )) {
                Label("Has a coffee bar", systemImage: "cup.and.saucer.fill")
            }
            if collection?.hasCoffeeBar == true {
                NavigationLink {
                    CoffeeBarView(onLog: onLog)
                } label: {
                    Label("Order a drink", systemImage: "plus.circle.fill")
                }
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
            Text("With a coffee bar, Suggestions and Coach assume any standard barista drink is available, and lattes, matcha, chai and teas log in a couple of taps.")
        }
        .listRowBackground(AppColors.appCard)
        .onAppear { note = collection?.alsoHere ?? "" }
        .onDisappear { store.setAlsoHere(note, for: collectionID) }
    }
}
