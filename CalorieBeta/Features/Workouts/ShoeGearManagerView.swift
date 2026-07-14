import MyFitPlateCore
import SwiftUI

public struct ShoeGearManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shoeStore = RunningShoeStore()
    @State private var showingAddShoeModal = false
    let runs: [Run]
    let onShoeSelected: ((RunningShoe) -> Void)?

    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    public init(runs: [Run] = [], onShoeSelected: ((RunningShoe) -> Void)? = nil) {
        self.runs = runs
        self.onShoeSelected = onShoeSelected
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        HapticManager.instance.feedback(.light)
                        showingAddShoeModal = true
                    } label: {
                        Label("Add New Shoe", systemImage: "plus")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    if shoeStore.shoes.isEmpty {
                        emptyStateView
                    } else {
                        if !runs.isEmpty {
                            leaderboardSection
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(shoeStore.shoes) { shoe in
                                shoeCard(for: shoe)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Shoe Gear Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .appFont(size: 16, weight: .semibold)
                }
            }
            .sheet(isPresented: $showingAddShoeModal) {
                AddShoeModal(shoeStore: shoeStore)
            }
        }
    }

    private var leaderboardSection: some View {
        let validShoes = shoeStore.shoes.filter { !$0.isRetired }
        let ranked = validShoes.compactMap { shoe -> (RunningShoe, Double)? in
            guard let pace = shoeStore.averagePaceSecondsPerKm(for: shoe.id, across: runs) else { return nil }
            return (shoe, pace)
        }.sorted(by: { $0.1 < $1.1 })

        guard !ranked.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 18))
                    Text("Shoe Performance Leaderboard")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                ForEach(Array(ranked.enumerated()), id: \.element.0.id) { index, item in
                    let (shoe, pace) = item
                    let count = shoeStore.runCount(for: shoe.id, across: runs)
                    let longest = shoeStore.longestRunDistance(for: shoe.id, across: runs) ?? 0

                    HStack(spacing: 12) {
                        Text(index == 0 ? "🥇" : (index == 1 ? "🥈" : (index == 2 ? "🥉" : "#\(index + 1)")))
                            .font(.system(size: 18))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(shoe.brand) \(shoe.name)")
                                .appFont(size: 14, weight: .bold)
                                .foregroundColor(.textPrimary)
                            Text("\(count) runs · Longest: \(RunFormat.distanceText(meters: longest, metric: useMetric))")
                                .appFont(size: 11)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            if let paceStr = RunFormat.paceText(secondsPerKm: pace, metric: useMetric) {
                                Text(paceStr)
                                    .appFont(size: 15, weight: .bold)
                                    .foregroundColor(index == 0 ? .yellow : .textPrimary)
                                    .monospacedDigit()
                            }
                            Text("AVG PACE")
                                .appFont(size: 9, weight: .bold)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                    }
                    .padding(.vertical, 4)
                    if index < ranked.count - 1 {
                        Divider()
                    }
                }
            }
            .appSurface(.emphasized)
            .padding(.horizontal)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(UIColor.tertiaryLabel))
            Text("No shoes added yet")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
            Text("Track your gear mileage and get alerted when it's time for a replacement.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .appSurface(.emphasized)
        .padding(.horizontal)
    }

    private func shoeCard(for shoe: RunningShoe) -> some View {
        let totalMeters = shoeStore.totalMeters(for: shoe.id, across: runs)
        let wear = shoeStore.wearPercentage(for: shoe.id, across: runs)
        let isWornOut = shoeStore.isWornOut(shoeID: shoe.id, across: runs)

        let distanceString = RunFormat.distanceText(meters: totalMeters, metric: useMetric)
        let maxDistanceString = RunFormat.distanceText(meters: shoe.maxMeters, metric: useMetric)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "shoeprints.fill")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(shoe.isRetired ? Color(UIColor.tertiaryLabel) : .accentProtein)
                    .frame(width: 42, height: 42)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(shoe.brand) · \(shoe.name)")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(shoe.isRetired ? Color(UIColor.secondaryLabel) : .textPrimary)

                        if shoe.isDefault && !shoe.isRetired {
                            Text("Default")
                                .appFont(size: 10, weight: .bold)
                                .foregroundColor(.accentProtein)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentProtein.opacity(0.15), in: Capsule())
                        }

                        if shoe.isRetired {
                            Text("Retired")
                                .appFont(size: 10, weight: .bold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                        }
                    }

                    Text("\(distanceString) of \(maxDistanceString)")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .monospacedDigit()
                }

                Spacer()

                Menu {
                    if !shoe.isDefault && !shoe.isRetired {
                        Button {
                            HapticManager.instance.feedback(.light)
                            shoeStore.setDefaultShoe(id: shoe.id)
                        } label: {
                            Label("Set as Default", systemImage: "star.fill")
                        }
                    }

                    if !shoe.isRetired {
                        Button(role: .destructive) {
                            HapticManager.instance.feedback(.medium)
                            shoeStore.retireShoe(id: shoe.id)
                        } label: {
                            Label("Retire Shoe", systemImage: "archivebox")
                        }
                    } else {
                        Button {
                            HapticManager.instance.feedback(.light)
                            var reactivated = shoe
                            reactivated.isRetired = false
                            shoeStore.updateShoe(reactivated)
                        } label: {
                            Label("Reactivate Shoe", systemImage: "arrow.uturn.backward")
                        }
                    }

                    if let onShoeSelected = onShoeSelected {
                        Button {
                            onShoeSelected(shoe)
                            dismiss()
                        } label: {
                            Label("Select for Run", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 36, height: 36)
                }
            }

            // Mileage Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(height: 8)

                        Capsule()
                            .fill(isWornOut ? Color.accentSignal : (shoe.isRetired ? Color(UIColor.secondaryLabel) : Color.brandPrimary))
                            .frame(width: min(geometry.size.width * CGFloat(wear), geometry.size.width), height: 8)
                    }
                }
                .frame(height: 8)

                if isWornOut && !shoe.isRetired {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .appFont(size: 11, weight: .bold)
                            .foregroundColor(.accentSignal)
                        Text("Worn out — consider replacing to prevent injury")
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(.accentSignal)
                    }
                    .padding(.top, 2)
                }

                let count = shoeStore.runCount(for: shoe.id, across: runs)
                if count > 0 {
                    HStack {
                        if let pace = shoeStore.averagePaceSecondsPerKm(for: shoe.id, across: runs),
                           let paceStr = RunFormat.paceText(secondsPerKm: pace, metric: useMetric) {
                            Label("Avg Pace: \(paceStr)", systemImage: "timer")
                        }
                        Spacer()
                        if let longest = shoeStore.longestRunDistance(for: shoe.id, across: runs) {
                            Label("Longest: \(RunFormat.distanceText(meters: longest, metric: useMetric))", systemImage: "arrow.left.and.right")
                        }
                    }
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let onShoeSelected = onShoeSelected {
                onShoeSelected(shoe)
                dismiss()
            }
        }
    }
}

private struct AddShoeModal: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var shoeStore: RunningShoeStore
    @State private var brand = ""
    @State private var name = ""
    @State private var initialMileage = ""
    @State private var maxMileage = "350"
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Shoe Details")) {
                    TextField("Brand (e.g. Nike, Hoka, Brooks)", text: $brand)
                        .appFont(size: 16)
                    TextField("Model Name (e.g. Pegasus 40, Clifton 9)", text: $name)
                        .appFont(size: 16)
                }

                Section(header: Text("Mileage Tracking (\(useMetric ? "km" : "miles"))"), footer: Text("Default recommended replacement limit is ~350 miles (560 km).")) {
                    HStack {
                        Text("Initial Mileage")
                            .appFont(size: 16)
                        Spacer()
                        TextField("0", text: $initialMileage)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Max Limit (\(useMetric ? "km" : "mi"))")
                            .appFont(size: 16)
                        Spacer()
                        TextField("350", text: $maxMileage)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            }
            .navigationTitle("Add New Shoe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appFont(size: 16)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveShoe()
                    }
                    .appFont(size: 16, weight: .bold)
                    .disabled(brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveShoe() {
        let brandClean = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameClean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brandClean.isEmpty, !nameClean.isEmpty else { return }

        let initialVal = Double(initialMileage) ?? 0.0
        let maxVal = Double(maxMileage) ?? (useMetric ? 560.0 : 350.0)

        let initialMeters = useMetric ? (initialVal * 1000.0) : (initialVal * RunFormat.metersPerMile)
        let maxMeters = useMetric ? (maxVal * 1000.0) : (maxVal * RunFormat.metersPerMile)

        let newShoe = RunningShoe(
            name: nameClean,
            brand: brandClean,
            initialMeters: initialMeters,
            maxMeters: maxMeters,
            isRetired: false,
            isDefault: shoeStore.shoes.isEmpty
        )

        shoeStore.addShoe(newShoe)
        HapticManager.instance.notification(.success)
        dismiss()
    }
}
