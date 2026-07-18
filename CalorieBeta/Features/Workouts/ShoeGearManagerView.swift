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
                                .foregroundColor(AppPalette.brandText)
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
    @State private var hasPreparedUnits = false
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canSave: Bool {
        !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var distanceUnit: String {
        useMetric ? "km" : "mi"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    shoeSetupHeader

                    shoeDetailsSection
                    mileageSection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Shoe Setup")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("add_shoe_screen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveShoe) {
                    Label("Save Shoe", systemImage: "checkmark")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!canSave)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("add_shoe_save")
            }
        }
        .onAppear(perform: prepareUnitDefaults)
    }

    private var shoeSetupHeader: some View {
        HStack(alignment: .top, spacing: AppSpacing.group) {
            VStack(alignment: .leading, spacing: 4) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("RUNNING GEAR")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text("Add a Shoe")
                    .appFont(size: 28, weight: .bold)
                    .foregroundStyle(AppPalette.text)

                Text("Track mileage automatically and know when a pair is nearing its replacement range.")
                    .appFont(size: 13, weight: .medium)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            Image(systemName: "figure.run")
                .appFont(size: 21, weight: .bold)
                .foregroundStyle(AppPalette.effort)
                .frame(width: 54, height: 54)
                .background(
                    AppPalette.effort.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }

    private var shoeDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            ShoeSetupSectionHeader(
                title: "Identity",
                subtitle: "This is how the shoe will appear in run history."
            )

            ShoeSetupField(title: "Brand", icon: "building.2.fill") {
                TextField("Nike, Hoka, Brooks", text: $brand)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("add_shoe_brand")
            }

            ShoeSetupField(title: "Model", icon: "shoeprints.fill") {
                TextField("Pegasus 40, Clifton 9", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("add_shoe_name")
            }
        }
        .appSurface(.quiet)
    }

    private var mileageSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            ShoeSetupSectionHeader(
                title: "Mileage Tracking",
                subtitle: "Start from the distance already on this pair, then choose a replacement reminder."
            )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AppSpacing.row) {
                        mileageField(
                            title: "Current Mileage",
                            icon: "gauge.with.dots.needle.33percent",
                            placeholder: "0",
                            value: $initialMileage
                        )
                        mileageField(
                            title: "Replacement Range",
                            icon: "flag.checkered",
                            placeholder: useMetric ? "560" : "350",
                            value: $maxMileage
                        )
                    }
                } else {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        mileageField(
                            title: "Current Mileage",
                            icon: "gauge.with.dots.needle.33percent",
                            placeholder: "0",
                            value: $initialMileage
                        )
                        mileageField(
                            title: "Replacement Range",
                            icon: "flag.checkered",
                            placeholder: useMetric ? "560" : "350",
                            value: $maxMileage
                        )
                    }
                }
            }

            Label(
                "Most running shoes are replaced around 350 mi (560 km), but comfort and wear still matter.",
                systemImage: "info.circle.fill"
            )
            .appFont(size: 11, weight: .semibold)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .appSurface(.quiet)
    }

    private func mileageField(
        title: String,
        icon: String,
        placeholder: String,
        value: Binding<String>
    ) -> some View {
        ShoeSetupField(title: title, icon: icon) {
            HStack(spacing: AppSpacing.compact) {
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)

                Spacer()

                Text(distanceUnit)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prepareUnitDefaults() {
        guard !hasPreparedUnits else { return }
        hasPreparedUnits = true
        maxMileage = useMetric ? "560" : "350"
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

private struct ShoeSetupField<Content: View>: View {
    let title: String
    let icon: String
    private let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label(title, systemImage: icon)
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)

            content
                .appFont(size: 16)
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, AppSpacing.row)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(
                    AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShoeSetupSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundStyle(AppPalette.text)

            Text(subtitle)
                .appFont(size: 13, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
