import MapKit
import SwiftUI

extension CollectionSchedule {
    /// "Weekdays, 8:00 AM – 6:00 PM".
    func summary(calendar: Calendar = .current) -> String {
        let days: String
        if weekdays.count == 7 {
            days = String(localized: "Every day")
        } else if weekdays == [2, 3, 4, 5, 6] {
            days = String(localized: "Weekdays")
        } else if weekdays == [1, 7] {
            days = String(localized: "Weekends")
        } else {
            days = CollectionSchedule.orderedWeekdays(calendar: calendar)
                .filter { weekdays.contains($0) }
                .map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        }
        return "\(days), \(Self.timeText(startMinute, calendar: calendar)) – \(Self.timeText(endMinute, calendar: calendar))"
    }

    /// Weekday numbers starting from the calendar's first weekday.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    static func timeText(_ minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: Date())) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

extension FoodCollection {
    /// "Place · Weekdays, 8:00 AM – 6:00 PM", or nil when the collection is not tied to either.
    var availabilitySummary: String? {
        let parts = [place == nil ? nil : String(localized: "Place"), schedule?.summary()].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Where and when a collection is on hand: a saved spot with a radius, a weekday schedule, or both.
struct CollectionPlaceView: View {
    let collectionID: UUID

    @Environment(\.openURL) private var openURL
    @State private var store = FoodCollectionStore.shared
    @State private var location = PlaceLocationService.shared
    @State private var isLocating = false
    @State private var failed = false

    private var collection: FoodCollection? { store.collection(id: collectionID) }

    var body: some View {
        Form {
            placeSection
            scheduleSection
        }
        .navigationTitle("Place & Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var placeSection: some View {
        Section {
            if let place = collection?.place {
                let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: place.radiusMeters * 3.5,
                                                                longitudinalMeters: place.radiusMeters * 3.5))) {
                    MapCircle(center: center, radius: place.radiusMeters)
                        .foregroundStyle(AppColors.calorie.opacity(0.2))
                        .stroke(AppColors.calorie, lineWidth: 2)
                    Marker(collection?.name ?? "", systemImage: "fork.knife", coordinate: center)
                        .tint(AppColors.calorie)
                }
                .id("\(place.latitude),\(place.longitude),\(place.radiusMeters)")
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)

                Picker("Radius", selection: Binding(
                    get: { place.radiusMeters },
                    set: { radius in
                        var updated = place
                        updated.radiusMeters = radius
                        store.setPlace(updated, for: collectionID)
                    }
                )) {
                    ForEach(CollectionPlace.radiusChoices, id: \.self) { radius in
                        Text(Measurement(value: radius, unit: UnitLength.meters)
                            .formatted(.measurement(width: .abbreviated, usage: .road))).tag(radius)
                    }
                }
                Button {
                    useCurrentLocation(radius: place.radiusMeters)
                } label: {
                    locatingLabel(String(localized: "Move to my current location"))
                }
                .disabled(isLocating)
                Button("Remove Place", role: .destructive) {
                    store.setPlace(nil, for: collectionID)
                }
            } else {
                Button {
                    useCurrentLocation(radius: 150)
                } label: {
                    locatingLabel(String(localized: "Use my current location"))
                }
                .disabled(isLocating || location.authorization == .denied || location.authorization == .restricted)
            }
            if location.authorization == .denied || location.authorization == .restricted {
                Button("Turn on location in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if failed {
                Text("Couldn't find your location. Try again in a moment.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Place")
        } footer: {
            Text("Save this while you're there, e.g. at your desk. Fud AI checks your location only while the app is open, and it never leaves this iPhone.")
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        let schedule = collection?.schedule
        Section {
            Toggle("On a schedule", isOn: Binding(
                get: { schedule != nil },
                set: { store.setSchedule($0 ? CollectionSchedule() : nil, for: collectionID) }
            ))
            if let schedule {
                HStack(spacing: 6) {
                    ForEach(CollectionSchedule.orderedWeekdays(), id: \.self) { weekday in
                        let isOn = schedule.weekdays.contains(weekday)
                        Button {
                            var updated = schedule
                            if isOn { updated.weekdays.remove(weekday) } else { updated.weekdays.insert(weekday) }
                            store.setSchedule(updated, for: collectionID)
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(isOn ? Color.white : Color.primary)
                                .background(isOn ? AppColors.calorie : Color.secondary.opacity(0.15), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                DatePicker("From", selection: minuteBinding(schedule, \.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: minuteBinding(schedule, \.endMinute), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Shows this collection on Home during these hours, with or without location. Use it alone if you'd rather not share location.")
        }
    }

    private func locatingLabel(_ title: String) -> some View {
        HStack {
            Label(title, systemImage: "location.fill")
            if isLocating {
                Spacer()
                ProgressView()
            }
        }
    }

    private func useCurrentLocation(radius: Double) {
        isLocating = true
        failed = false
        location.requestCurrentLocation { coordinate in
            isLocating = false
            guard let coordinate else {
                failed = location.isAllowed
                return
            }
            store.setPlace(CollectionPlace(latitude: coordinate.latitude, longitude: coordinate.longitude, radiusMeters: radius),
                           for: collectionID)
        }
    }

    private func minuteBinding(_ schedule: CollectionSchedule, _ keyPath: WritableKeyPath<CollectionSchedule, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return Binding(
            get: { calendar.date(byAdding: .minute, value: schedule[keyPath: keyPath], to: start) ?? start },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                var updated = schedule
                updated[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                store.setSchedule(updated, for: collectionID)
            }
        )
    }
}

/// Home card: the collections on hand where and when the user is, with one-tap logging.
struct AtPlaceCardView: View {
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = FoodCollectionStore.shared
    @State private var location = PlaceLocationService.shared
    @State private var logged: Set<String> = []
    @State private var showing: FoodCollection?
    @State private var orderingCoffee = false

    private static let shownItems = 4

    var body: some View {
        let active = Calendar.current.isDateInToday(date) ? store.activeCollections(at: location.coordinate) : []
        Group {
            if let collection = active.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: isAtPlace(collection) ? "location.fill" : "clock.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.calorie)
                        Text(collection.name)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Spacer()
                        if collection.items.count > Self.shownItems || active.count > 1 {
                            Button("All") { showing = collection }
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .buttonStyle(.borderless)
                        }
                    }
                    ForEach(collection.items.prefix(Self.shownItems)) { item in
                        HStack(spacing: 10) {
                            Text(item.emoji ?? "🍽️").font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                Text("\(item.calories) kcal")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if logged.contains(item.favoriteKey) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppColors.calorie)
                                    .accessibilityLabel("Logged")
                            } else {
                                Button("Log") { log(item) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppColors.calorie)
                            }
                        }
                    }
                    if collection.hasCoffeeBar {
                        coffeeRow
                    }
                    if let note = collection.alsoHereNote {
                        Text(String(localized: "Also here: \(note)"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if active.count > 1 {
                        Text("Also on hand: \(active.dropFirst().map(\.name).joined(separator: ", "))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .progressCardStyle()
                .sheet(isPresented: $orderingCoffee) {
                    NavigationStack {
                        CoffeeBarView(onLog: { log($0); orderingCoffee = false })
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { orderingCoffee = false } } }
                    }
                }
                .sheet(item: $showing) { collection in
                    NavigationStack {
                        FoodCollectionDetailView(collectionID: collection.id, onLog: { log($0); showing = nil })
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showing = nil } } }
                    }
                }
            }
        }
        .onAppear { location.refreshIfNeeded(collections: store.collections) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refreshIfNeeded(collections: store.collections) }
        }
    }

    /// The usual coffee-bar order with one-tap logging, and a way to order something else.
    private var coffeeRow: some View {
        let usual = CoffeeUsual.load()
        let entry = (usual ?? CoffeeOrder()).entry()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(entry.emoji ?? "☕️").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(usual == nil ? String(localized: "Coffee bar") : entry.name)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    Text(usual == nil ? String(localized: "Order any drink") : String(localized: "Your usual · \(entry.calories) kcal"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if usual == nil {
                    Button("Order") { orderingCoffee = true }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.calorie)
                } else if logged.contains(entry.favoriteKey) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.calorie)
                        .accessibilityLabel("Logged")
                } else {
                    Button("Log") { log(entry) }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.calorie)
                }
            }
            if usual != nil {
                Button("Order a different drink") { orderingCoffee = true }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .buttonStyle(.borderless)
                    .padding(.leading, 32)
            }
        }
    }

    private func isAtPlace(_ collection: FoodCollection) -> Bool {
        guard let place = collection.place, let coordinate = location.coordinate else { return false }
        return place.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func log(_ item: FoodEntry) {
        withAnimation {
            _ = foodStore.addEntry(item.duplicatedForLogging(at: Date()))
            logged.insert(item.favoriteKey)
        }
    }
}
