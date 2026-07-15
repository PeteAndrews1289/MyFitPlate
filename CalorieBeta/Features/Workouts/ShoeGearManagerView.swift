import MyFitPlateCore
import SwiftUI

public struct ShoeGearManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shoeStore = RunningShoeStore()
    @State private var showingAddShoeModal: Bool
    let runs: [Run]
    let onShoeSelected: ((RunningShoe) -> Void)?

    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    public init(
        runs: [Run] = [],
        onShoeSelected: ((RunningShoe) -> Void)? = nil,
        initiallyShowsAddShoe: Bool = false
    ) {
        self.runs = runs
        self.onShoeSelected = onShoeSelected
        _showingAddShoeModal = State(initialValue: initiallyShowsAddShoe)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Button {
                        HapticManager.instance.feedback(.light)
                        showingAddShoeModal = true
                    } label: {
                        Label("Add New Shoe", systemImage: "plus")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .padding(.horizontal, AppSpacing.screenHorizontal)

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
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                    }
                }
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Shoe Gear")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("shoe_gear_screen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .appTextRole(.control)
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
                        .foregroundColor(AppPalette.achievement)
                        .font(.system(size: 18))
                    Text("Shoe Performance Leaderboard")
                        .appTextRole(.control)
                        .foregroundColor(AppPalette.text)
                    Spacer()
                }

                ForEach(Array(ranked.enumerated()), id: \.element.0.id) { index, item in
                    let (shoe, pace) = item
                    let count = shoeStore.runCount(for: shoe.id, across: runs)
                    let longest = shoeStore.longestRunDistance(for: shoe.id, across: runs) ?? 0

                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .appTextRole(.caption)
                            .foregroundStyle(index == 0 ? AppPalette.text : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                (index == 0 ? AppPalette.achievement : AppPalette.control),
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(shoe.brand) \(shoe.name)")
                                .appTextRole(.control)
                                .foregroundColor(AppPalette.text)
                            Text("\(count) runs · Longest: \(RunFormat.distanceText(meters: longest, metric: useMetric))")
                                .appTextRole(.caption)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            if let paceStr = RunFormat.paceText(secondsPerKm: pace, metric: useMetric) {
                                Text(paceStr)
                                    .appTextRole(.control)
                                    .foregroundColor(index == 0 ? AppPalette.achievement : AppPalette.text)
                                    .monospacedDigit()
                            }
                            Text("AVG PACE")
                                .appTextRole(.caption)
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
            .padding(.horizontal, AppSpacing.screenHorizontal)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(UIColor.tertiaryLabel))
            Text("No shoes added yet")
                .appTextRole(.sectionTitle)
                .foregroundColor(AppPalette.text)
            Text("Track your gear mileage and get alerted when it's time for a replacement.")
                .appTextRole(.body)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .appSurface(.emphasized)
        .padding(.horizontal, AppSpacing.screenHorizontal)
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
                    .appTextRole(.sectionTitle)
                    .foregroundColor(shoe.isRetired ? Color(UIColor.tertiaryLabel) : AppPalette.effort)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(shoe.brand) · \(shoe.name)")
                            .appTextRole(.control)
                            .foregroundColor(shoe.isRetired ? Color(UIColor.secondaryLabel) : AppPalette.text)

                        if shoe.isDefault && !shoe.isRetired {
                            Text("Default")
                                .appTextRole(.caption)
                                .foregroundColor(AppPalette.brand)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppPalette.brand.opacity(0.12), in: Capsule())
                        }

                        if shoe.isRetired {
                            Text("Retired")
                                .appTextRole(.caption)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                        }
                    }

                    Text("\(distanceString) of \(maxDistanceString)")
                        .appTextRole(.secondary)
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
                        .appTextRole(.sectionTitle)
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
                            .fill(isWornOut ? AppPalette.caution : (shoe.isRetired ? Color(UIColor.secondaryLabel) : AppPalette.brand))
                            .frame(width: min(geometry.size.width * CGFloat(wear), geometry.size.width), height: 8)
                    }
                }
                .frame(height: 8)

                if isWornOut && !shoe.isRetired {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .appTextRole(.caption)
                            .foregroundColor(AppPalette.caution)
                        Text("Worn out - consider replacing to prevent injury")
                            .appTextRole(.caption)
                            .foregroundColor(AppPalette.caution)
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
                    .appTextRole(.caption)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.top, 4)
                }
            }
        }
        .appSurface(.quiet)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    mileageField(label: "Initial Mileage", placeholder: "0", value: $initialMileage)
                    mileageField(label: "Max Limit (\(useMetric ? "km" : "mi"))", placeholder: "350", value: $maxMileage)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas)
            .navigationTitle("Add New Shoe")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("add_shoe_screen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appTextRole(.control)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveShoe()
                    }
                    .appTextRole(.control)
                    .disabled(brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func mileageField(label: String, placeholder: String, value: Binding<String>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(label)
                    .appTextRole(.body)
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)
            }
        } else {
            HStack {
                Text(label)
                    .appTextRole(.body)
                Spacer()
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
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
