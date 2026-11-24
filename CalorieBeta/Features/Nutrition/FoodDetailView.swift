import SwiftUI
import UIKit
import MyFitPlateCore

struct FoodTrustResolution: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

final class FoodDetailPresentationState: ObservableObject {
    @Published var correctionDraft: FoodDetailCorrectionDraft?
}

struct FoodDetailView: View {
    var initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    var date: Date
    var source: String
    var targetMealName: String?
    var isPresentedModally: Bool
    var onLogUpdated: () -> Void
    private let onFoodAccepted: ((FoodDetailSaveCheckpoint, UUID?) -> Void)?
    private let onExpandNutrition: (() -> Void)?
    var onUpdate: ((FoodItem) -> Void)?
    var onUpdateAccepted: ((FoodItem) -> Bool)?
    private let reviewActionTitle: String?
    private let reviewNavigationTitle: String?
    @StateObject private var saveSession: FoodDetailSaveSession

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var bannerService: BannerService
    private let foodAPIService = FatSecretFoodAPIService()
    private let imageModel = MLImageModel()

    @State private var foodName: String
    @State private var availableServings: [ServingSizeOption] = []
    @State private var selectedServingID: UUID?
    @State private var quantity: String = "1"
    @State private var portionBasis: Double
    @State private var displayMassUnit: String?
    @State private var massText = ""
    @FocusState private var amountFocused: Bool
    @State private var showNutritionDetails = false
    @State private var isLoadingDetails: Bool = false
    @State private var errorLoading: String?

    @State private var isLoggedItem: Bool
    
    @State private var isSavedAsCustom: Bool = false
    @State private var hasSavedBarcodeCorrection: Bool = false
    @State private var customFoodForAction: FoodItem?
    @State private var pendingCustomFoodID = UUID().uuidString

    @State private var showingImagePicker = false
    @StateObject private var presentationState: FoodDetailPresentationState
    @State private var showingTrustReceipt = false
    @State private var showingNutrientProfile = false
    @State private var recipeVariation: FoodItem?
    @State private var correctionEditorDidSubmit = false
    @State private var correctionCalibrationContext: FoodTrustCalibrationContext?
    @State private var persistedTrustItem: FoodItem?
    @State private var trustResolution: FoodTrustResolution?
    @State private var isSavingTrustCorrection = false
    @State private var hasLoggedSuspiciousData = false
    @State private var hasLoggedTrustCardView = false
    @State private var isProcessingLabel = false
    @State private var labelAnalysisID: UUID?
    @State private var labelScanFailed = false
    @State private var linkedInventory: InventoryIntakeLink?

    // MARK: - Robust Initializer
    // Updated to use new model fields if available, ensuring stability.
    init(
        initialFoodItem inputFoodItem: FoodItem,
        dailyLog: Binding<DailyLog?>,
        date: Date = Date(),
        source: String = "log",
        targetMealName: String? = nil,
        isPresentedModally: Bool = false,
        presentationState: FoodDetailPresentationState = FoodDetailPresentationState(),
        onLogUpdated: @escaping () -> Void,
        onUpdate: ((FoodItem) -> Void)? = nil,
        onUpdateAccepted: ((FoodItem) -> Bool)? = nil,
        reviewActionTitle: String? = nil,
        reviewNavigationTitle: String? = nil,
        dayContext: DiaryDayContext? = nil,
        trainingFuelTarget: TrainingFuelTarget? = nil,
        onFoodAccepted: ((FoodDetailSaveCheckpoint, UUID?) -> Void)? = nil,
        onExpandNutrition: (() -> Void)? = nil
    ) {
        let userID = DIContainer.shared.authService.currentUserID
        let sourceLog = dailyLog.wrappedValue.flatMap { log in
            let matchesEntry = source.starts(with: "log_") && log.meals.flatMap(\.foodItems).contains { $0.id == inputFoodItem.id }
            let calendar = dayContext?.calendar ?? Calendar.current
            let matchesDay = log.id != nil && log.id == dayContext?.dayKey
                || log.date == date || calendar.isDate(log.date, inSameDayAs: date)
            return matchesEntry || matchesDay ? log : nil
        }
        let capturedDay = userID.flatMap { owner in
            if let dayContext { return dayContext }
            if let sourceLog, let key = sourceLog.id {
                return DiaryDayContext(userID: owner, date: sourceLog.date, timeZone: .current, dayKey: key)
            }
            return DiaryDayContext(userID: owner, date: Calendar.current.startOfDay(for: date))
        }
        let session = FoodDetailSaveSession(food: inputFoodItem, userID: userID,
            date: date, mealName: targetMealName ?? DailyLogRules.determineMealType(), source: source,
            isEditing: source.starts(with: "log_"), restoresExisting: onUpdate == nil && onUpdateAccepted == nil,
            dayContext: capturedDay, trainingFuelTarget: trainingFuelTarget)
        _saveSession = StateObject(wrappedValue: session)
        let initialFoodItem = session.restoredReview ? session.checkpoint.food : inputFoodItem
        self.initialFoodItem = initialFoodItem
        self._dailyLog = dailyLog
        self.date = session.checkpoint.date
        self.source = source
        self.targetMealName = targetMealName ?? session.checkpoint.mealName
        self.isPresentedModally = isPresentedModally
        self._presentationState = StateObject(wrappedValue: presentationState)
        self.onExpandNutrition = onExpandNutrition
        self.onFoodAccepted = onFoodAccepted
        self.onLogUpdated = onLogUpdated
        self.onUpdate = onUpdate
        self.onUpdateAccepted = onUpdateAccepted
        self.reviewActionTitle = reviewActionTitle
        self.reviewNavigationTitle = reviewNavigationTitle
        
        let isEditingLoggedItem = source.starts(with: "log_")
        self._isLoggedItem = State(initialValue: isEditingLoggedItem)
        self._foodName = State(initialValue: initialFoodItem.name)
        self._pendingCustomFoodID = State(initialValue: MyFoodsLibraryRules.savedCopyID(for: initialFoodItem))

        let previousAmount = isEditingLoggedItem || source == "image_result_edit"
            ? ServingNutritionCalculator.parseQuantity(from: initialFoodItem.servingSize).quantity : 1
        let amount = initialFoodItem.quantityValue ?? previousAmount
        let openingAmount = amount.isFinite && amount > 0 ? amount : 1
        _quantity = State(initialValue: Self.amountText(openingAmount))
        _portionBasis = State(initialValue: openingAmount)
    }

    // Helper to parse old string format (Backward Compatibility)
    private func parseQuantityFromServing(_ servingDesc: String) -> (qty: Double, baseDesc: String) {
        let parsed = ServingNutritionCalculator.parseQuantity(from: servingDesc)
        return (parsed.quantity, parsed.baseDescription)
    }

    private var selectedServingOption: ServingSizeOption? {
        guard let selectedID = selectedServingID else { return nil }
        return availableServings.first { $0.id == selectedID }
    }

    private func destinationDateText(style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        let context = saveSession.checkpoint.dayContext
        formatter.calendar = context?.calendar ?? Calendar(identifier: .gregorian)
        formatter.timeZone = context?.timeZone ?? .current
        formatter.dateStyle = style
        return formatter.string(from: context?.displayDate ?? saveSession.checkpoint.date)
    }

    private var isShowingDetailsLoading: Bool {
        isLoadingDetails && !isLoggedItem && source != "recent_tap" && source != "search_result_no_detail_fetch"
    }

    private var canChangeServing: Bool {
        !isLoggedItem || source == "recent_tap" || source == "image_result_edit" || (availableServings.count > 1 && source != "log_swipe_direct_edit_no_picker")
    }

    private var sourceDescriptor: FoodSourceDescriptor {
        FoodSourceClassifier.descriptor(
            for: source,
            foodID: persistedTrustItem?.id ?? initialFoodItem.id,
            metadata: trustMetadata
        )
    }

    private var barcodeForCorrection: String? {
        let barcode = BarcodeCorrectionRules.normalizedBarcode(initialFoodItem.sourceMetadata?.barcode ?? "")
        return barcode.isEmpty ? nil : barcode
    }

    private var shouldShowBarcodeCorrectionCard: Bool {
        barcodeForCorrection != nil &&
            !hasSavedBarcodeCorrection &&
            sourceDescriptor.sourceKey != "custom_barcode"
    }

    private var correctionBaseServing: ServingSizeOption {
        selectedServingOption ?? ServingNutritionCalculator.baseServing(from: initialFoodItem)
    }

    // Sanity-checks the currently selected base serving (per one serving, not quantity-scaled,
    // so a big quantity can't trip the physical-plausibility rules).
    private var sanityCheckItem: FoodItem {
        let serving = correctionBaseServing
        return FoodItem(
            name: foodName,
            calories: serving.calories,
            protein: serving.protein,
            carbs: serving.carbs,
            fats: serving.fats,
            saturatedFat: serving.saturatedFat,
            polyunsaturatedFat: serving.polyunsaturatedFat,
            monounsaturatedFat: serving.monounsaturatedFat,
            fiber: serving.fiber,
            servingSize: serving.description,
            servingWeight: serving.servingWeightGrams ?? 1.0,
            calcium: serving.calcium,
            iron: serving.iron,
            potassium: serving.potassium,
            sodium: serving.sodium,
            vitaminA: serving.vitaminA,
            vitaminC: serving.vitaminC,
            vitaminD: serving.vitaminD,
            vitaminB12: serving.vitaminB12,
            folate: serving.folate,
            magnesium: serving.magnesium,
            phosphorus: serving.phosphorus,
            zinc: serving.zinc,
            copper: serving.copper,
            manganese: serving.manganese,
            selenium: serving.selenium,
            vitaminB1: serving.vitaminB1,
            vitaminB2: serving.vitaminB2,
            vitaminB3: serving.vitaminB3,
            vitaminB5: serving.vitaminB5,
            vitaminB6: serving.vitaminB6,
            vitaminE: serving.vitaminE,
            vitaminK: serving.vitaminK
        )
    }

    private var sanityFindings: [FoodDataSanity.Finding] {
        FoodDataSanity.findings(for: sanityCheckItem)
    }

    private var trustMetadata: FoodSourceMetadata? {
        let trustItem = persistedTrustItem ?? initialFoodItem
        guard var metadata = trustItem.sourceMetadata else { return nil }
        if metadata.hasCrossDatabaseAgreement,
           !FoodSourceAgreement.preservesAgreementEvidence(sanityCheckItem, initialFoodItem) {
            metadata.crossVerifiedBy = nil
            metadata.crossVerificationEvidence = nil
        }
        return metadata
    }

    private var trustEvaluation: FoodTrustEvaluation {
        FoodTrustEvaluation.evaluate(
            item: sanityCheckItem,
            descriptor: sourceDescriptor,
            metadata: trustMetadata
        )
    }

    private var trustCalibrationContext: FoodTrustCalibrationContext {
        FoodTrustCalibrationContext(
            item: sanityCheckItem,
            descriptor: sourceDescriptor,
            metadata: trustMetadata
        )
    }

    /// Trust telemetry links source/evidence categories to coarse correction outcomes so model
    /// weights can be calibrated from persisted behavior rather than impressions.
    private func logCorrectionAction(
        _ action: String,
        correctionScope: String? = nil,
        resultingItem: FoodItem? = nil,
        context: FoodTrustCalibrationContext? = nil
    ) {
        let context = context ?? correctionCalibrationContext ?? trustCalibrationContext
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.correctionAction.rawValue,
            parameters: context.analyticsParameters(
                action: action,
                correctionScope: correctionScope,
                resultingItem: resultingItem
            )
        )
    }

    private func logTrustAction(_ action: String) {
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trustAction.rawValue,
            parameters: trustCalibrationContext.analyticsParameters(action: action)
        )
    }

    private func logTrustCardViewedIfNeeded() {
        guard !hasLoggedTrustCardView else { return }
        hasLoggedTrustCardView = true
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trustCardViewed.rawValue,
            parameters: trustCalibrationContext.analyticsParameters()
        )
    }

    private var nutrientCoverageBucket: String {
        let reportedCount = MicronutrientKey.vitaminAndMineralKeys.filter {
            adjustedNutrients.micronutrientValue(for: $0) != nil
        }.count

        switch reportedCount {
        case 0:
            return "none"
        case 1...5:
            return "low"
        case 6...12:
            return "medium"
        default:
            return "high"
        }
    }

    private func logNutrientProfileAction(_ action: String) {
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.nutrientProfileAction.rawValue,
            parameters: [
                "action": action,
                "panel_bucket": nutrientCoverageBucket,
                "source": sourceDescriptor.sourceKey
            ]
        )
    }

    private func openCorrectionEditor(action: String) {
        guard !isSavingTrustCorrection else { return }
        correctionEditorDidSubmit = false
        correctionCalibrationContext = trustCalibrationContext
        logCorrectionAction(action, context: correctionCalibrationContext)
        presentationState.correctionDraft = FoodDetailCorrectionDraft(
            foodName: foodName,
            serving: correctionBaseServing
        )
    }

    private func logSuspiciousDataIfNeeded() {
        guard !hasLoggedSuspiciousData else { return }
        let findings = sanityFindings
        guard findings.contains(where: { $0.severity == .warning }) else { return }
        hasLoggedSuspiciousData = true
        DIContainer.shared.analyticsManager?.logEvent("food_data_suspicious", parameters: [
            "kinds": findings.map(\.id).joined(separator: ","),
            "source": sourceDescriptor.sourceKey
        ])
    }

    // MARK: - Adjusted Nutrients Calculation
    private var adjustedNutrients: AdjustedServingNutrition {
        let baseNutrients = selectedServingOption ?? ServingNutritionCalculator.baseServing(from: initialFoodItem)
        return ServingNutritionCalculator.adjustedNutrition(
            base: baseNutrients,
            quantityText: quantity
        )
    }

    private var adjustedConsistencyStatus: NutritionCalorieConsistency.Status {
        let nutrients = adjustedNutrients
        return NutritionCalorieConsistency.status(
            calories: nutrients.calories,
            protein: nutrients.protein,
            carbs: nutrients.carbs,
            fats: nutrients.fats,
            fiber: nutrients.fiber
        )
    }

    var body: some View {
        ZStack {
            presentedDetailContent
                .opacity(presentationState.correctionDraft == nil ? 1 : 0)
                .allowsHitTesting(presentationState.correctionDraft == nil)
                .accessibilityHidden(presentationState.correctionDraft != nil)

            if let correctionDraft = presentationState.correctionDraft {
                correctionEditorView(draft: correctionDraft)
                    .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private var presentedDetailContent: some View {
        if isPresentedModally {
            // Keep the review and correction editor in separate navigation containers.
            NavigationStack { detailContent }
        } else {
            detailContent
        }
    }

    private var boundedNutrition: AnyView { AnyView(detailedNutrition) }

    private var nutritionDisclosure: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Button {
                    showNutritionDetails.toggle()
                    if showNutritionDetails { onExpandNutrition?() }
                } label: {
                    HStack(spacing: AppSpacing.row) {
                        Label("Nutrition and sources", systemImage: "list.bullet").appTextRole(.control)
                        Spacer()
                        Image(systemName: showNutritionDetails ? "chevron.up" : "chevron.down").appTextRole(.caption)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showNutritionDetails ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("food_detail_more")
                if showNutritionDetails {
                    if !trustEvaluation.requiresCorrection { trustSummary }
                    FoodDetailMacroGrid(calories: adjustedNutrients.calories, protein: adjustedNutrients.protein,
                                        carbs: adjustedNutrients.carbs, fats: adjustedNutrients.fats)
                    boundedNutrition
                }
            }
        )
    }

    private var portionNotices: AnyView {
        AnyView(Group {
            if let linkedInventory { linkedStockReview(linkedInventory) }

            let consistencyStatus = adjustedConsistencyStatus
            if consistencyStatus.hasMeaningfulMismatch && consistencyStatus.delta > 0 {
                NutritionConsistencyNoticeCard(status: consistencyStatus, style: .detail)
            }

            if trustEvaluation.requiresCorrection {
                trustSummary
            }

            if shouldShowBarcodeCorrectionCard, trustEvaluation.action == nil {
                FoodDetailBarcodeMemoryAction(
                    rememberAction: {
                        logCorrectionAction("remember")
                        saveAsCustomFood()
                    }
                )
            }

            if isShowingDetailsLoading {
                FoodDetailLoadingCard()
            } else {
                if let error = errorLoading {
                    FoodDetailNoticeCard(
                        title: "Serving details could not fully refresh",
                        message: error
                    )
                }

                if labelScanFailed {
                    LabelScanFailureCard(
                        retry: { showingImagePicker = true },
                        continueManually: { labelScanFailed = false }
                    )
                }
            }
        })
    }

    private var detailContent: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: AppSpacing.group) {
                        if let target = saveSession.checkpoint.trainingFuelTarget {
                            TrainingFuelTargetContextView(target: target, currentCalories: adjustedNutrients.calories,
                                currentProtein: adjustedNutrients.protein, currentCarbs: adjustedNutrients.carbs,
                                onDismiss: saveSession.checkpoint.isSubmitted || saveSession.isSaving ? nil : { _ = saveSession.removeFuelContext() })
                        }
                        FoodDetailHeroCard(
                            identity: FoodDisplayIdentity(name: foodName, brandName: initialFoodItem.sourceMetadata?.brandName),
                            servingDescription: displayedServingDescription
                        )

                        AnyView(servingControlsCard)
                        portionNotices
                        nutritionDisclosure
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                    .padding(.bottom, AppSpacing.row)
                    .disabled(saveSession.checkpoint.isSubmitted)
                }
                .scrollDismissesKeyboard(.interactively)

                if let message = saveSession.errorMessage {
                    Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .accessibilityIdentifier("food_detail_save_error")
                }
                if onUpdate == nil && onUpdateAccepted == nil {
                    Text(isLoggedItem ? saveSession.checkpoint.mealName + " · " + destinationDateText(style: .medium) : destinationDateText(style: .medium))
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("\(saveSession.checkpoint.mealName), \(destinationDateText(style: .full))")
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(AppPalette.canvas)
                        .accessibilityIdentifier("food_detail_destination")
                }

                FoodDetailActionBar(
                    title: buttonText(),
                    isEnabled: logButtonEnabled,
                    action: handleButtonAction
                )
            }.blur(radius: isProcessingLabel ? 3 : 0)
            
            if isProcessingLabel {
                ImageProcessingView(kind: .nutritionLabel) {
                    labelAnalysisID = nil
                    isProcessingLabel = false
                }
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(navigationTitleText()).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("food_detail_cancel")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleSavedState) {
                    Image(systemName: isSavedAsCustom ? "star.fill" : "star")
                        .foregroundColor(isSavedAsCustom ? AppPalette.achievement : AppPalette.brandText)
                }
                .accessibilityLabel(isSavedAsCustom ? "Unsave food" : "Save food")
                .accessibilityIdentifier("food_detail_saved")
            }
        }
        .onTapGesture { hideKeyboard() }
        .interactiveDismissDisabled(saveSession.isSaving)
        .onAppear {
            setupInitialData()
            checkIfSaved()
        }
        .task(id: initialFoodItem.id) {
            guard isLoggedItem, onUpdate == nil, onUpdateAccepted == nil, let owner = saveSession.userID,
                  DIContainer.shared.authService.currentUserID == owner else { return }
            let link = try? await DIContainer.shared.nutritionRepository.fetchInventoryIntakeLink(userID: owner, foodID: initialFoodItem.id)
            guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == owner else { return }
            linkedInventory = link
        }
        .imageSourceDialog(isPresented: $showingImagePicker) { image in
                let requestID = UUID()
                labelAnalysisID = requestID
                labelScanFailed = false
                self.isProcessingLabel = true
                imageModel.parseNutritionLabel(from: image) { result in
                    guard labelAnalysisID == requestID else { return }
                    labelAnalysisID = nil
                    self.isProcessingLabel = false
                    switch result {
                    case .success(let nutrition):
                        self.handleScannedNutrition(nutrition)
                    case .failure(let error):
                        AppLog.data.error("Nutrition label scan failed: \(error.localizedDescription, privacy: .public)")
                        self.labelScanFailed = true
                    }
                }
        }
        .sheet(item: $recipeVariation) { food in
            RecipeVariationReviewView(food: food)
        }
        .sheet(isPresented: $showingTrustReceipt) {
            trustReceiptSheet
        }
        .sheet(isPresented: $showingNutrientProfile) {
            FoodNutrientProfileSheet(
                foodName: foodName,
                servingDescription: adjustedNutrients.servingDescription,
                nutrients: adjustedNutrients,
                onScanLabel: presentLabelScannerAfterSheet
            )
            .presentationDetents([.large])
        }
    }

    private func correctionEditorView(draft: FoodDetailCorrectionDraft) -> some View {
        FoodDetailCorrectionSheet(
            draft: draft,
            barcode: barcodeForCorrection,
            onCancel: closeCorrectionEditor
        ) { correctedName, correctedServing in
            applyFoodCorrectionAndRemember(
                foodName: correctedName,
                serving: correctedServing
            )
            closeCorrectionEditor()
        }
    }

    private func closeCorrectionEditor() {
        if !correctionEditorDidSubmit {
            logCorrectionAction(
                "correction_abandoned",
                context: correctionCalibrationContext
            )
        }
        correctionEditorDidSubmit = false
        correctionCalibrationContext = nil
        presentationState.correctionDraft = nil
    }

    private var trustReceiptSheet: some View {
        NavigationStack {
            ScrollView {
                FoodTrustReceipt(
                    item: persistedTrustItem ?? initialFoodItem,
                    descriptor: sourceDescriptor,
                    evaluation: trustEvaluation,
                    metadata: trustMetadata,
                    findings: sanityFindings,
                    isSavingCorrection: isSavingTrustCorrection,
                    resolution: trustResolution,
                    onAction: trustEvaluation.action.map { _ in
                        {
                            logTrustAction("correction_opened_from_receipt")
                            showingTrustReceipt = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                openCorrectionEditor(action: "trust_fix_opened_from_receipt")
                            }
                        }
                    }
                )
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingTrustReceipt = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func presentLabelScannerAfterSheet() {
        logNutrientProfileAction("label_scan_from_profile")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showingImagePicker = true
        }
    }

    private var trustSummary: some View {
        FoodTrustSummaryCard(
            item: persistedTrustItem ?? initialFoodItem,
            descriptor: sourceDescriptor,
            evaluation: trustEvaluation,
            metadata: trustMetadata,
            isSavingCorrection: isSavingTrustCorrection,
            resolution: trustResolution,
            onOpenReceipt: {
                logTrustAction("receipt_opened")
                showingTrustReceipt = true
            },
            onAction: trustEvaluation.action.map { _ in
                {
                    logTrustAction("correction_opened")
                    openCorrectionEditor(action: "trust_fix_opened")
                }
            }
        )
        .onAppear {
            logTrustCardViewedIfNeeded()
            logSuspiciousDataIfNeeded()
        }
    }

    @ViewBuilder private var detailedNutrition: some View {
        FoodNutrientProfileCard(
            nutrients: adjustedNutrients,
            onOpenProfile: {
                logNutrientProfileAction("profile_opened")
                showingNutrientProfile = true
            },
            onScanLabel: {
                logNutrientProfileAction("label_scan_from_summary")
                showingImagePicker = true
            }
        )

        if initialFoodItem.recipePortionSnapshot?.adjustedIngredientFoods?.isEmpty == false {
            Button {
                guard saveSession.userID != nil, saveSession.userID == DIContainer.shared.authService.currentUserID else { return }
                recipeVariation = initialFoodItem
            } label: {
                Label("Save adjusted recipe as a variation", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityIdentifier("recipe_save_logged_variation")
        }

        nutritionDetailsCard
        FoodDetailLabelScanCard {
            logNutrientProfileAction("label_scan_from_detail")
            showingImagePicker = true
        }
    }

    @ViewBuilder private var servingControlsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Rectangle().fill(AppPalette.text).frame(height: 2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(adjustedNutrients.calories.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                Text("cal").appTextRole(.body)
                Spacer()
                Text("\(adjustedNutrients.protein.formatted(.number.precision(.fractionLength(0...1)))) g protein")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(adjustedNutrients.calories.formatted(.number.precision(.fractionLength(0)))) cal · \(adjustedNutrients.protein.formatted(.number.precision(.fractionLength(0...1)))) g protein")
            .accessibilityIdentifier("food_detail_portion_total")
            Divider()

            let basis = ServingNutritionCalculator.displayPortion(initialFoodItem.servingSize)
            if let label = initialFoodItem.sourceMetadata?.labeledServing, !label.isEmpty, !basis.isEmpty,
               label.caseInsensitiveCompare(basis) != .orderedSame {
                HStack(spacing: AppSpacing.compact) {
                    Text("Package serving \(label) · nutrition per \(basis)")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("food_portion_package_serving")
                    if let labeled = labeledMassPortion(label) {
                        Spacer(minLength: 0)
                        Button("Use label") {
                            displayMassUnit = nativeMassUnit(selectedServingOption?.description) == labeled.unit ? nil : labeled.unit
                            applyQuantity(labeled.quantity)
                        }
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.brandText)
                        .fixedSize()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("food_portion_use_label")
                    }
                }
            }

            servingSelectionControl
            quantityControl
            HStack(spacing: AppSpacing.compact) {
                ForEach([0.5, 1, 2], id: \.self) { factor in
                    Button {
                        applyQuantity(portionBasis * factor)
                    } label: {
                        Text(factor == 0.5 ? "½×" : factor == 1 ? "1×" : "2×")
                            .appTextRole(.control).frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedServingOption == nil)
                    .accessibilityLabel("\(factor.formatted()) times starting portion")
                    .accessibilityIdentifier("food_portion_" + (factor == 0.5 ? "half" : factor == 1 ? "original" : "double"))
                }
            }
        }
        .padding(.bottom, AppSpacing.row)
    }

    private var displayedServingDescription: String {
        if let unit = displayMassUnit, !massText.isEmpty { return massText + " " + unit }
        if let amount = Double(quantity), let unit = nativeMassUnit(selectedServingOption?.description) {
            return Self.displayAmount(amount) + " " + unit
        }
        return ServingNutritionCalculator.displayPortion(adjustedNutrients.servingDescription)
    }

    private static func displayAmount(_ amount: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
        return amount.formatted(amount > 0 && amount < 0.001
            ? style.precision(.significantDigits(1...3)) : style.precision(.fractionLength(0...3)))
    }

    private var gramsPerSelectedServing: Double? {
        selectedServingOption.flatMap { ServingNutritionCalculator.measuredGrams(in: $0.description) }
    }

    private static func amountText(_ amount: Double) -> String {
        let text = String(amount)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private func chooseServing(_ option: ServingSizeOption) {
        displayMassUnit = nil
        guard option.id != selectedServingID else { return }
        if let previousGrams = gramsPerSelectedServing,
           let nextGrams = ServingNutritionCalculator.measuredGrams(in: option.description),
           let previousAmount = Double(quantity) {
            let ratio = previousGrams / nextGrams
            portionBasis *= ratio
            quantity = Self.amountText(previousAmount * ratio)
        } else {
            portionBasis = 1
            quantity = "1"
        }
        selectedServingID = option.id
    }

    private func applyQuantity(_ amount: Double) {
        quantity = Self.amountText(amount)
        if let displayMassUnit, let grams = gramsPerSelectedServing,
           let mass = InventoryQuantityRules.convert(amount * grams, from: "g", to: displayMassUnit) {
            massText = Self.displayAmount(mass)
        }
    }

    private var displayedQuantity: Binding<String> {
        Binding(get: {
            if displayMassUnit != nil { return massText }
            guard !amountFocused, let amount = Double(quantity), amount.isFinite else { return quantity }
            return Self.displayAmount(amount)
        }, set: { text in
            let decimal = text.replacingOccurrences(of: ",", with: ".")
            if let displayMassUnit, let basis = gramsPerSelectedServing {
                massText = text
                quantity = Double(decimal).flatMap { InventoryQuantityRules.convert($0, from: displayMassUnit, to: "g") }
                    .map { String($0 / basis) } ?? ""
            } else { quantity = decimal }
        })
    }

    private func nativeMassUnit(_ description: String?) -> String? {
        guard let description else { return nil }
        let unit = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^1(?:\.0+)?\s+"#, with: "", options: .regularExpression)
        switch unit {
        case "g", "gram", "grams": return "g"
        case "oz", "ounce", "ounces": return "oz"
        default: return nil
        }
    }

    // A counted item or fluid ounce has no implied mass. Only use an explicit
    // amount and mass unit when applying a package label to the nutrition basis.
    private func labeledMassPortion(_ label: String) -> (quantity: Double, unit: String)? {
        let parts = label.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let amount = Double(parts[0]), amount.isFinite, amount > 0,
              let unit = nativeMassUnit(String(parts[1])), let basis = gramsPerSelectedServing, basis > 0,
              let grams = InventoryQuantityRules.convert(amount, from: unit, to: "g") else { return nil }
        let quantity = grams / basis
        return quantity.isFinite && quantity > 0 ? (quantity, unit) : nil
    }

    private var amountStep: (label: String, quantity: Double) {
        let unit = displayMassUnit ?? nativeMassUnit(selectedServingOption?.description)
        let step = unit == "g" ? 5.0 : unit == "oz" ? 1.0 : 0.5
        if let displayMassUnit, let basis = gramsPerSelectedServing,
           let grams = InventoryQuantityRules.convert(step, from: displayMassUnit, to: "g") {
            return (Self.amountText(step), grams / basis)
        }
        return (step == 0.5 ? "½" : Self.amountText(step), step)
    }

    private func stepButton(increasing: Bool) -> some View {
        let step = amountStep
        let next = (Double(quantity) ?? 0) + (increasing ? step.quantity : -step.quantity)
        return Button {
            applyQuantity(next)
        } label: {
            Text((increasing ? "+" : "−") + step.label)
                .appTextRole(.control).monospacedDigit()
                .frame(minWidth: 48, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.brandText)
        .disabled(selectedServingOption == nil || !next.isFinite || next <= 0)
        .accessibilityLabel((increasing ? "Increase" : "Decrease") + " amount by " + step.label)
        .accessibilityIdentifier(increasing ? "food_portion_increase" : "food_portion_decrease")
    }

    private var quantityControl: some View {
        HStack(spacing: AppSpacing.compact) {
            Text("Amount").appTextRole(.control)
            Spacer(minLength: AppSpacing.compact)
            HStack(spacing: 0) {
                stepButton(increasing: false)
                TextField("Quantity", text: displayedQuantity)
                    .focused($amountFocused)
                    .accessibilityLabel("Quantity")
                    .keyboardType(.decimalPad)
                    .appTextRole(.sectionTitle).monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 78, idealWidth: 100, maxWidth: 120, minHeight: 44)
                    .layoutPriority(1)
                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control))
                stepButton(increasing: true)
            }
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
        }
    }

    private func servingChoice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).appTextRole(.control)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 40)
                .foregroundStyle(selected ? AppPalette.brandText : AppPalette.text)
                .background(selected ? AppPalette.brand.opacity(0.15) : AppPalette.control, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var servingSelectionControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Serving size").appTextRole(.control)
                .accessibilityIdentifier("food_detail_serving_controls")
            if let current = selectedServingOption {
                let options = canChangeServing && availableServings.count <= 3 ? availableServings : [current]
                let nativeUnits = options.compactMap { nativeMassUnit($0.description) }
                ScrollView(.horizontal) {
                    HStack(spacing: AppSpacing.compact) {
                        ForEach(options) { option in
                            servingChoice(option.description,
                                          selected: displayMassUnit == nil && selectedServingID == option.id,
                                          id: nativeMassUnit(option.description).map { "food_portion_" + $0 } ?? "food_portion_serving_" + option.id.uuidString) {
                                chooseServing(option)
                            }
                        }
                        if gramsPerSelectedServing != nil {
                            ForEach(["g", "oz"].filter { !nativeUnits.contains($0) }, id: \.self) { unit in
                                servingChoice(unit, selected: displayMassUnit == unit, id: "food_portion_" + unit) {
                                    displayMassUnit = unit
                                    if let amount = Double(quantity) { applyQuantity(amount) } else { massText = "" }
                                }
                            }
                        }
                        if canChangeServing && availableServings.count > 3 {
                            Menu {
                                ForEach(availableServings) { option in
                                    Button(option.description) { chooseServing(option) }
                                }
                            } label: {
                                Label("More", systemImage: "chevron.down")
                                    .appTextRole(.control).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("food_portion_unit")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                Text(isLoadingDetails ? "Loading options" : adjustedNutrients.servingDescription)
                    .appTextRole(.secondary)
            }
        }
    }

    @ViewBuilder private var nutritionDetailsCard: some View {
        let nutrients = adjustedNutrients
        let totalUnsaturatedFat = nutrients.fats - (nutrients.saturatedFat ?? 0)

        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "More nutrition")

            DisclosureGroup("Fat breakdown and fiber") {
                VStack(spacing: 8) {
                    nutrientRow(label: "Saturated fat", value: nutrients.saturatedFat, unit: "g")
                    nutrientRow(label: "Polyunsaturated fat", value: nutrients.polyunsaturatedFat, unit: "g")
                    nutrientRow(label: "Monounsaturated fat", value: nutrients.monounsaturatedFat, unit: "g")
                    nutrientRow(label: "Unsaturated fat", value: totalUnsaturatedFat > 0 ? totalUnsaturatedFat : nil, unit: "g")
                    nutrientRow(label: "Dietary fiber", value: nutrients.fiber, unit: "g")
                }
                .padding(.top, 8)
            }
        }
        .tint(AppPalette.brand)
        .appSurface(.quiet)
        .accessibilityIdentifier("food_detail_nutrition_details")
    }

    private var labelScannerButton: some View {
        Button {
            showingImagePicker = true
        } label: {
            Label("Not correct? Take a photo of the nutrition label.", systemImage: "camera.fill")
        }
        .tint(AppPalette.effort)
        .padding(.top, 5)
    }

    private func handleScannedNutrition(_ data: NutritionLabelData) {
        self.foodName = data.foodName
        let scannedServing = ServingSizeOption(
            description: data.servingDescription ?? "Scanned from label",
            servingWeightGrams: data.servingWeightGrams,
            calories: data.calories,
            protein: data.protein,
            carbs: data.carbs,
            fats: data.fats,
            saturatedFat: data.saturatedFat,
            polyunsaturatedFat: data.polyunsaturatedFat,
            monounsaturatedFat: data.monounsaturatedFat,
            fiber: data.fiber,
            calcium: data.calcium,
            iron: data.iron,
            potassium: data.potassium,
            sodium: data.sodium,
            vitaminA: data.vitaminA,
            vitaminC: data.vitaminC,
            vitaminD: data.vitaminD,
            vitaminB12: data.vitaminB12,
            folate: data.folate,
            magnesium: data.magnesium,
            phosphorus: data.phosphorus,
            zinc: data.zinc,
            copper: data.copper,
            manganese: data.manganese,
            selenium: data.selenium,
            vitaminB1: data.vitaminB1,
            vitaminB2: data.vitaminB2,
            vitaminB3: data.vitaminB3,
            vitaminB5: data.vitaminB5,
            vitaminB6: data.vitaminB6,
            vitaminE: data.vitaminE,
            vitaminK: data.vitaminK
        )
        self.availableServings.insert(scannedServing, at: 0)
        self.selectedServingID = scannedServing.id
        self.quantity = "1"
        portionBasis = 1
        displayMassUnit = nil
    }

    private func buttonText() -> String {
        if saveSession.isSaving { return "Saving…" }
        if saveSession.checkpoint.isSubmitted { return "Retry food save" }
        if onUpdate != nil || onUpdateAccepted != nil {
            return reviewActionTitle ?? "Update item"
        }
        return isLoggedItem ? "Update logged item" : "Log to " + saveSession.checkpoint.mealName
    }

    private func navigationTitleText() -> String {
        if onUpdate != nil || onUpdateAccepted != nil {
            return reviewNavigationTitle ?? "Edit item"
        }
        return isLoggedItem ? "Edit logged item" : "Log food"
    }

    private func handleButtonAction() {
        if onUpdate != nil || onUpdateAccepted != nil {
            updateItem()
        } else {
            logAdjustedFood()
        }
    }
    
    // MARK: - Update Item (Refactored)
    private func updateItem() {
        guard let quantityValue = Double(quantity), quantityValue > 0 else { return }
        
        let finalNutrients = adjustedNutrients
        let rawUpdatedFoodItem = FoodItem(
            id: initialFoodItem.id,
            name: foodName, calories: finalNutrients.calories,
            protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber,
            servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: initialFoodItem.timestamp ?? Date(),
            sourceMetadata: initialFoodItem.sourceMetadata,
            calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium,
            vitaminA: finalNutrients.vitaminA, vitaminC: finalNutrients.vitaminC,
            vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        let updatedFoodItem = rawUpdatedFoodItem
            .normalizedForEstimatedSource(source)
            .markedUserEdited(
                sourceType: inferredSourceType(for: source),
                originalItem: initialFoodItem
            )
            .preservingRecipePortion(from: initialFoodItem, quantity: finalNutrients.quantityValue, unit: finalNutrients.servingUnit)
        if let onUpdateAccepted {
            if onUpdateAccepted(updatedFoodItem) { dismiss() } else {
                bannerService.showBanner(title: "Changes not saved", message: "Your portion is still in this editor. Keep it open and try again.",
                    iconName: "exclamationmark.triangle.fill", iconColor: AppPalette.caution)
            }
        } else {
            onUpdate?(updatedFoodItem)
            dismiss()
        }
    }

    private var proposedStockScale: Double? {
        guard let linkedInventory else { return nil }
        var desired = initialFoodItem
        desired.servingSize = adjustedNutrients.servingDescription
        desired.servingWeight = adjustedNutrients.servingWeightGrams
        desired.quantityValue = nil; desired.servingUnit = nil
        return try? InventoryIntakeRules.scale(food: desired, link: linkedInventory)
    }
    private func linkedStockReview(_ link: InventoryIntakeLink) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("Linked stock", systemImage: "shippingbox").appTextRole(.control)
            if let source = try? link.source.mutation(), let scale = proposedStockScale {
                ForEach(source.before) { item in
                    let consumed = item.quantity - (source.after.first { $0.id == item.id }?.quantity ?? item.quantity)
                    Text("\(item.name): \((consumed * link.currentScale).formatted()) → \((consumed * scale).formatted()) \(item.unit) used")
                        .appTextRole(.secondary)
                }
            } else {
                Text("Choose a compatible serving to review its linked stock amount before saving.")
                    .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
            }
            Text("Saving adjusts only this intake's original stock use. Later purchases stay intact; cooked ingredients are not deducted again. Delete and diary Undo keep the same link. Review the receipt in Pantry history.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }.appSurface(.quiet).accessibilityElement(children: .contain).accessibilityIdentifier("food_linked_stock_review")
    }

    private var logButtonEnabled: Bool {
        guard !saveSession.isSaving, !saveSession.isAccepted else { return false }
        if saveSession.checkpoint.isSubmitted { return true }
        let quantityValue = Double(quantity) ?? 0
        return !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityValue.isFinite && quantityValue > 0 && selectedServingOption != nil
            && (linkedInventory == nil || proposedStockScale != nil)
    }

    private func toggleSavedState() {
        if isSavedAsCustom {
            unsaveCustomFood()
        } else {
            saveAsCustomFood()
        }
    }

    private func saveAsCustomFood() {
        let serving = selectedServingOption ?? ServingNutritionCalculator.baseServing(from: initialFoodItem)
        let quantityValue = Double(quantity) ?? 1
        saveCustomFood(foodName: foodName, serving: serving, quantityValue: quantityValue)
    }

    private func saveCustomFood(
        foodName: String,
        serving: ServingSizeOption,
        quantityValue: Double,
        correctionScope: String? = nil,
        calibrationContext: FoodTrustCalibrationContext? = nil,
        completion: ((Bool, FoodItem?) -> Void)? = nil
    ) {
        guard let userID = saveSession.userID, DIContainer.shared.authService.currentUserID == userID else {
            if let correctionScope {
                logCorrectionAction(
                    "correction_save_failed",
                    correctionScope: correctionScope,
                    context: calibrationContext
                )
            }
            completion?(false, nil)
            return
        }
        guard quantityValue.isFinite, quantityValue > 0 else {
            bannerService.showBanner(title: "Review amount", message: "Enter a positive amount before saving this food.", iconName: "exclamationmark.triangle.fill", iconColor: AppPalette.caution)
            completion?(false, nil)
            return
        }
        let finalNutrients = ServingNutritionCalculator.adjustedNutrition(
            base: serving,
            quantityValue: quantityValue
        )
        
        let rawItemToSave = FoodItem(
            id: customFoodForAction?.id ?? pendingCustomFoodID,
            name: foodName,
            calories: finalNutrients.calories, protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber, servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: nil,
            sourceMetadata: initialFoodItem.sourceMetadata,
            calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium, vitaminA: finalNutrients.vitaminA,
            vitaminC: finalNutrients.vitaminC, vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        let itemToSave = rawItemToSave
            .normalizedForEstimatedSource(source)
            .savedAsCustomFood(
                barcode: initialFoodItem.sourceMetadata?.barcode,
                originalItem: initialFoodItem
            )
            .preservingRecipePortion(from: initialFoodItem, quantity: finalNutrients.quantityValue, unit: finalNutrients.servingUnit)
        guard MyFoodsLibraryRules.isValidSavedSnapshot(itemToSave) else {
            bannerService.showBanner(title: "Review nutrition", message: "Review the name, amount and nutrition before saving this food.", iconName: "exclamationmark.triangle.fill", iconColor: AppPalette.caution)
            completion?(false, nil)
            return
        }

        let finishSave: (Bool, FoodItem?) -> Void = { success, persistedItem in
            Task { @MainActor in
                guard self.saveSession.userID == userID, DIContainer.shared.authService.currentUserID == userID else {
                    completion?(false, nil); return
                }
                if success, let persistedItem {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = persistedItem.sourceMetadata?.barcode?.isEmpty == false
                    self.customFoodForAction = persistedItem
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self.persistedTrustItem = persistedItem
                    }
                    let message = self.hasSavedBarcodeCorrection
                        ? "\(foodName) will be used for future scans of this barcode."
                        : "\(foodName) added to My Foods."
                    bannerService.showBanner(title: "Saved", message: message)
                    self.contributeToCommunityPoolIfEligible(persistedItem)
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not save custom food.", iconName: "xmark.circle.fill", iconColor: AppPalette.critical)
                }
                if let correctionScope {
                    self.logCorrectionAction(
                        success ? "correction_saved" : "correction_save_failed",
                        correctionScope: correctionScope,
                        resultingItem: persistedItem,
                        context: calibrationContext
                    )
                }
                completion?(success, persistedItem)
            }
        }

        if itemToSave.sourceMetadata?.barcode?.isEmpty == false {
            dailyLogService.customFoodStore.saveBarcodeCorrection(
                for: userID,
                foodItem: itemToSave
            ) { result in
                switch result {
                case .success(let persistedItem):
                    finishSave(true, persistedItem)
                case .failure:
                    finishSave(false, nil)
                }
            }
        } else {
            dailyLogService.customFoodStore.saveCustomFood(for: userID, foodItem: itemToSave) { success in
                finishSave(success, success ? itemToSave : nil)
            }
        }
    }

    /// Shares a saved barcode correction with the community pool when the feature flag is
    /// on and the entry passes the sanity checker. Best-effort: failures stay silent.
    private func contributeToCommunityPoolIfEligible(_ item: FoodItem) {
        guard let barcode = item.sourceMetadata?.barcode else { return }
        let flagEnabled = DIContainer.shared.featureFlagService?.boolValue(for: .communityBarcodeCorrections) ?? false
        let decision = CommunityBarcodeRules.contributionDecision(item, barcode: barcode, flagEnabled: flagEnabled)
        DIContainer.shared.analyticsManager?.logEvent("community_barcode_contribution_evaluated", parameters: [
            "eligible": decision.isEligible,
            "reason": decision.reason,
            "flag_enabled": flagEnabled,
            "source": sourceDescriptor.sourceKey
        ])
        guard decision.isEligible, let store = DIContainer.shared.communityBarcodeStore else { return }
        Task {
            await store.contribute(item, barcode: barcode)
        }
    }

    private func applyFoodCorrectionAndRemember(foodName correctedName: String, serving correctedServing: ServingSizeOption) {
        let originalServing = correctionBaseServing
        let correctionScope = FoodCorrectionTelemetry.scope(
            originalName: foodName,
            originalServing: originalServing,
            correctedName: correctedName,
            correctedServing: correctedServing
        )
        let calibrationContext = correctionCalibrationContext ?? trustCalibrationContext
        correctionEditorDidSubmit = true
        logCorrectionAction(
            "correction_submitted",
            correctionScope: correctionScope,
            context: calibrationContext
        )
        isSavingTrustCorrection = true
        saveCustomFood(
            foodName: correctedName,
            serving: correctedServing,
            quantityValue: 1,
            correctionScope: correctionScope,
            calibrationContext: calibrationContext
        ) { success, persistedItem in
            self.isSavingTrustCorrection = false
            guard success, persistedItem != nil else { return }

            withAnimation(.easeInOut(duration: 0.24)) {
                self.foodName = correctedName
                self.availableServings.removeAll { $0.id == correctedServing.id }
                self.availableServings.insert(correctedServing, at: 0)
                self.selectedServingID = correctedServing.id
                self.quantity = "1"
                self.portionBasis = 1
                self.displayMassUnit = nil
                self.trustResolution = FoodTrustResolution(
                    title: "Correction saved",
                    detail: self.barcodeForCorrection == nil
                        ? "Trust now reflects your saved review"
                        : "Future scans will use this reviewed entry"
                )
            }
            HapticManager.instance.notification(.success)
        }
    }
    
    private func unsaveCustomFood() {
        guard let userID = saveSession.userID, DIContainer.shared.authService.currentUserID == userID,
              let foodID = customFoodForAction?.id else { return }
        dailyLogService.customFoodStore.deleteCustomFood(for: userID, foodItemID: foodID) { success in
            Task { @MainActor in
                guard self.saveSession.userID == userID, DIContainer.shared.authService.currentUserID == userID else { return }
                if success {
                    self.isSavedAsCustom = false
                    if let barcode = self.barcodeForCorrection,
                       let customFoodForAction = self.customFoodForAction,
                       BarcodeCorrectionRules.matches(customFoodForAction, barcode: barcode) {
                        self.hasSavedBarcodeCorrection = false
                    }
                    self.customFoodForAction = nil
                    bannerService.showBanner(title: "Removed", message: "\(foodName) removed from My Foods.", iconName: "star.slash.fill")
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not remove custom food.", iconName: "xmark.circle.fill", iconColor: AppPalette.critical)
                }
            }
        }
    }
    
    private func checkIfSaved() {
        guard let userID = saveSession.userID, DIContainer.shared.authService.currentUserID == userID else { return }
        dailyLogService.customFoodStore.fetchMyFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                guard self.saveSession.userID == userID, DIContainer.shared.authService.currentUserID == userID else { return }
                guard case .success(let items) = result else { return }

                if let barcode = self.barcodeForCorrection,
                   let savedBarcodeItem = BarcodeCorrectionRules.bestCorrectedFood(
                       in: items,
                       barcode: barcode
                   ) {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = true
                    self.customFoodForAction = savedBarcodeItem
                    self.persistedTrustItem = savedBarcodeItem
                } else if let savedItem = MyFoodsLibraryRules.savedCopy(of: self.initialFoodItem, in: items) {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = false
                    self.customFoodForAction = savedItem
                    if savedItem.id == self.initialFoodItem.id {
                        self.persistedTrustItem = savedItem
                    }
                }
            }
        }
    }
    
    // MARK: - Setup Initial Data
    // Updated to handle logic for new quantity/unit fields logic
    private func setupInitialData() {

        if source.starts(with: "log_") || source.starts(with: "image_result_edit") {
            let singleUnitNutrients = ServingNutritionCalculator.baseServing(from: initialFoodItem)
            self.availableServings = [singleUnitNutrients]
            self.selectedServingID = singleUnitNutrients.id
            self.isLoadingDetails = false
            
        } else if source == "recent_tap" {
            let singleUnitNutrients = ServingNutritionCalculator.baseServing(from: initialFoodItem)
            self.availableServings = [singleUnitNutrients]
            self.selectedServingID = singleUnitNutrients.id
            self.isLoadingDetails = false

        } else if source == "search_result" || source == "barcode_result" || source == "image_result" {
            fetchAPIServingDetails()
        } else {
            let baseServingOption = ServingNutritionCalculator.baseServing(from: initialFoodItem)
            self.availableServings = [baseServingOption]
            self.selectedServingID = baseServingOption.id
            self.isLoadingDetails = false
        }
    }
    
    private func fetchAPIServingDetails() {
        guard !isLoadingDetails else { return }
        let likelyApiId = FoodSearchRanking.isFatSecretID(initialFoodItem.id)
        
        if likelyApiId && availableServings.isEmpty {
            isLoadingDetails = true; errorLoading = nil
            foodAPIService.fetchFoodDetails(foodId: initialFoodItem.id) { result in
                DispatchQueue.main.async {
                    self.isLoadingDetails = false
                    switch result {
                    case .success(let (foodInfo, servings)):
                        self.foodName = foodInfo.name
                        self.availableServings = servings.isEmpty ? [self.createFallbackServing(from: foodInfo)] : servings
                        if let matchingServing = self.availableServings.first(where: { $0.description == self.initialFoodItem.servingSize && $0.servingWeightGrams == self.initialFoodItem.servingWeight }) {
                            self.selectedServingID = matchingServing.id
                        } else if let firstServing = self.availableServings.first {
                            self.selectedServingID = firstServing.id
                        } else {
                            self.selectedServingID = nil
                            self.errorLoading = "No servings found for item."
                        }
                    case .failure(let error):
                        errorLoading = error.localizedDescription
                        self.availableServings = [self.createFallbackServing(from: self.initialFoodItem)]
                        self.selectedServingID = self.availableServings.first?.id
                    }
                }
            }
        } else if availableServings.isEmpty {
            self.availableServings = [self.createFallbackServing(from: self.initialFoodItem)]
            self.selectedServingID = self.availableServings.first?.id
            self.isLoadingDetails = false
        }
    }
    
    private func createFallbackServing(from foodItem: FoodItem) -> ServingSizeOption {
        ServingNutritionCalculator.baseServing(from: foodItem)
    }

    // MARK: - Save Data (Robust)
    private func logAdjustedFood() {
        guard logButtonEnabled, saveSession.userID == DIContainer.shared.authService.currentUserID else { return }
        if saveSession.checkpoint.isSubmitted { saveReviewedFood(saveSession.checkpoint.food); return }
        guard selectedServingOption != nil else { return }
        guard let quantityValue = Double(quantity), quantityValue > 0 else { return }

        let finalNutrients = adjustedNutrients
        
        var itemSourceToLog = "unknown_detail_view"
        if !isLoggedItem {
            switch self.source {
            case "barcode_result": itemSourceToLog = "barcode_scan"
            case "search_result": itemSourceToLog = "api"
            case "image_result": itemSourceToLog = "image_scan"
            case "recent_tap":
                let parsedInfo = parseQuantityFromServing(initialFoodItem.servingSize)
                if initialFoodItem.id.count < 20 && !initialFoodItem.id.contains("-") && !parsedInfo.baseDesc.lowercased().contains("recipe") && !parsedInfo.baseDesc.lowercased().contains("ai est.") {
                    itemSourceToLog = "api_recent"
                } else if parsedInfo.baseDesc.lowercased().contains("recipe") {
                    itemSourceToLog = "recipe_recent"
                } else if parsedInfo.baseDesc.lowercased().contains("ai est.") || initialFoodItem.name.lowercased().contains("ai logged") {
                    itemSourceToLog = "ai_recent"
                } else {
                    itemSourceToLog = "manual_recent"
                }
            default: itemSourceToLog = self.source
            }
        }
        
        let rawLoggedFoodItem = FoodItem(
            id: isLoggedItem ? initialFoodItem.id : UUID().uuidString,
            name: foodName, calories: finalNutrients.calories,
            protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber,
            servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: isLoggedItem ? initialFoodItem.timestamp : Date(),
            sourceMetadata: initialFoodItem.sourceMetadata,
            calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium,
            vitaminA: finalNutrients.vitaminA, vitaminC: finalNutrients.vitaminC,
            vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        let loggedFoodItem = rawLoggedFoodItem
            .normalizedForEstimatedSource(itemSourceToLog)
            .markedUserConfirmed(
                sourceType: inferredSourceType(for: itemSourceToLog),
                originalItem: initialFoodItem
            )
            .preservingRecipePortion(from: initialFoodItem, quantity: finalNutrients.quantityValue, unit: finalNutrients.servingUnit)

        saveReviewedFood(loggedFoodItem)
    }

    private func saveReviewedFood(_ food: FoodItem) {
        let previousUndoID = dailyLogService.undoChangeID
        saveSession.save(food: food, using: dailyLogService) { accepted in
            guard accepted else { return }
            HapticManager.instance.feedback(.medium)
            onFoodAccepted?(saveSession.checkpoint, previousUndoID)
            onLogUpdated()
            dismiss()
        }
    }

    @ViewBuilder private func nutrientRow(label: String, value: Double?, unit: String, specifier: String = "%.1f") -> some View {
        if let unwrappedValue = value, unwrappedValue.isFinite, unwrappedValue >= 0 {
            HStack { Text(label).appFont(size: 15); Spacer(); Text("\(unwrappedValue, specifier: specifier) \(unit)").appFont(size: 15).foregroundColor(Color(UIColor.secondaryLabel)) }
        } else {
            EmptyView()
        }
    }
    @ViewBuilder private func nutrientRow(label: String, value: String) -> some View {
        HStack { Text(label).appFont(size: 15); Spacer(); Text(value).appFont(size: 15).foregroundColor(Color(UIColor.secondaryLabel)) }
    }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

    private func inferredSourceType(for source: String) -> FoodSourceType? {
        let normalizedSource = source.lowercased()
        let sourceWords = normalizedSource.components(separatedBy: CharacterSet.alphanumerics.inverted)
        if FoodSourceClassifier.descriptor(for: source).sourceKey == "chain_builder" { return .chainBuilder }
        if normalizedSource.contains("usda") { return .usda }
        if normalizedSource.contains("open_food_facts") { return .openFoodFacts }
        if normalizedSource.contains("barcode") || normalizedSource.contains("fatsecret") { return .fatSecret }
        if sourceWords.contains("menu") || normalizedSource == "aimenu" { return .aiMenu }
        if sourceWords.contains("text") || normalizedSource == "aitext" { return .aiText }
        if sourceWords.contains("ai") || sourceWords.contains("image") || ["aiimage", "aichat", "aibulk"].contains(normalizedSource) { return .aiImage }
        if normalizedSource.contains("recipe") { return .recipe }
        if normalizedSource.contains("meal_plan") { return .mealPlan }
        if normalizedSource.contains("manual") || normalizedSource.contains("custom") { return .manual }
        if normalizedSource.contains("recent") { return .recent }
        return nil
    }
}

struct FoodTrustReceipt: View {
    let item: FoodItem
    let descriptor: FoodSourceDescriptor
    let evaluation: FoodTrustEvaluation
    let metadata: FoodSourceMetadata?
    let findings: [FoodDataSanity.Finding]
    let isSavingCorrection: Bool
    let resolution: FoodTrustResolution?
    let onAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsScoreDetails = false
    @State private var showsSourceDetails = false
    @State private var showsCoverageDetails = false
    @State private var presentedResolution: FoodTrustResolution?

    private var tint: Color {
        switch evaluation.level {
        case .excellent, .strong:
            return .accentPositiveText
        case .review:
            return AppPalette.caution
        case .low:
            return evaluation.requiresCorrection ? AppPalette.critical : AppPalette.caution
        }
    }

    private var sourceName: String {
        metadata?.sourceName ?? descriptor.title
    }

    private var passport: FoodTrustPassport {
        FoodTrustPassport.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: metadata
        )
    }

    private var coreScope: FoodTrustEvidenceScope {
        passport.coreNutrition
    }

    private var supportingEvidence: [FoodVerificationEvidence] {
        metadata?.validatedCrossVerificationEvidence ?? []
    }

    private var reviewText: String {
        switch metadata?.reviewStatus {
        case .userEdited:
            return "Nutrition edited"
        case .userConfirmed:
            return "Serving reviewed"
        case .notRequired, .unreviewed, nil:
            return "Serving not reviewed"
        }
    }

    private var visibleReasons: [FoodTrustReason] {
        evaluation.reasonDetails.filter { $0.kind != .evidence }
    }

    private var reviewTint: Color {
        switch metadata?.reviewStatus {
        case .userEdited, .userConfirmed:
            return .accentPositiveText
        case .notRequired:
            return Color(UIColor.secondaryLabel)
        case .unreviewed, nil:
            return descriptor.isEstimated ? AppPalette.caution : Color(UIColor.secondaryLabel)
        }
    }

    private var sanityText: String {
        let warningCount = findings.filter { $0.severity == .warning }.count
        if warningCount > 0 {
            return warningCount == 1 ? "1 warning" : "\(warningCount) warnings"
        }
        if findings.isEmpty {
            return "No warnings found"
        }
        return "1 detail to review"
    }

    private var sanityTint: Color {
        if findings.contains(where: { $0.severity == .warning }) {
            return AppPalette.critical
        }
        return findings.isEmpty ? .accentPositiveText : AppPalette.caution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            receiptHeader

            if let presentedResolution {
                resolutionNotice(presentedResolution)
                    .transition(.opacity)
            }

            evidenceFingerprint

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                receiptStep(
                    icon: descriptor.systemImage,
                    title: "Source",
                    value: sourceName,
                    detail: "\(passport.lineage.title). \(descriptor.detail)",
                    rowTint: tint,
                    isLast: false
                )
                receiptStep(
                    icon: "checkmark.seal.fill",
                    title: "Core Nutrition",
                    value: coreScope.state.label,
                    detail: coreScope.detail,
                    rowTint: evidenceTint(coreScope.state),
                    isLast: false
                )
                nutritionStep
                receiptStep(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Your Review",
                    value: reviewText,
                    detail: reviewDetail,
                    rowTint: reviewTint,
                    isLast: true,
                    isEmphasized: presentedResolution != nil
                )
            }

            if !supportingEvidence.isEmpty {
                sourceAgreementDisclosure
            }

            evidenceCoverage

            scoreDisclosure

            if let action = evaluation.action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 8) {
                        if isSavingCorrection {
                            ProgressView()
                        } else {
                            Image(systemName: action == "Fix data" ? "pencil" : "slider.horizontal.3")
                        }
                        Text(isSavingCorrection ? "Saving correction" : action)
                    }
                }
                .buttonStyle(AppActionButtonStyle(evaluation.requiresCorrection ? .destructive : .secondary))
                .disabled(isSavingCorrection)
                .accessibilityIdentifier("food_trust_action")
                .accessibilityLabel(isSavingCorrection ? "Saving correction" : action)
                .accessibilityHint("Opens the nutrition editor for this food.")
            }
        }
        .padding(.vertical, 4)
        .task(id: resolution?.id) {
            await presentResolutionIfNeeded()
        }
    }

    private var receiptHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    receiptIdentity
                    scoreSummary
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    receiptIdentity
                    Spacer(minLength: AppSpacing.group)
                    scoreSummary
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var receiptIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Source details")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
                .accessibilityIdentifier("food_trust_receipt")
            Text(evaluation.label)
                .appFont(size: 12, weight: .bold)
                .foregroundColor(tint)
        }
    }

    private var scoreSummary: some View {
        Label(coreScope.state.label, systemImage: evidenceIcon(coreScope.state))
            .appFont(size: 10, weight: .bold)
            .foregroundColor(evidenceTint(coreScope.state))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(evidenceTint(coreScope.state).opacity(0.10), in: Capsule())
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("food_trust_score")
            .accessibilityLabel("Trust rating")
            .accessibilityValue(
                "\(evaluation.label). \(coreScope.state.label). Evidence index \(evaluation.score) out of 99"
            )
    }

    private var evidenceFingerprint: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Source summary")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: AppSpacing.compact),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                ),
                alignment: .leading,
                spacing: AppSpacing.compact
            ) {
                fingerprintCell(
                    icon: descriptor.systemImage,
                    title: "Source type",
                    value: passport.lineage.title,
                    color: tint
                )
                fingerprintCell(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Agreement",
                    value: agreementFingerprintText,
                    color: supportingEvidence.isEmpty ? .secondary : .accentPositiveText
                )
                fingerprintCell(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Your review",
                    value: reviewText,
                    color: reviewTint
                )
                fingerprintCell(
                    icon: freshnessIcon,
                    title: "Freshness",
                    value: freshnessFingerprintText,
                    color: freshnessTint
                )
            }
        }
        .padding(AppSpacing.row)
        .background(
            AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .accessibilityIdentifier("food_trust_fingerprint")
    }

    private func fingerprintCell(
        icon: String,
        title: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            Image(systemName: icon)
                .appFont(size: 12, weight: .bold)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var agreementFingerprintText: String {
        supportingEvidence.isEmpty
            ? "No attached comparison"
            : "\(supportingEvidence.count + 1) comparable records"
    }

    private var freshnessFingerprintText: String {
        switch passport.freshness.state {
        case .current: "Current record"
        case .aging: "Older record"
        case .stale: "May be stale"
        case .retrieved: "Retrieval date only"
        case .unknown: "Date unavailable"
        }
    }

    private var evidenceCoverage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.14) : AppMotion.visibility) {
                    showsCoverageDetails.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nutrient sources")
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Text("Identity, serving, detailed nutrients, and ingredients")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: showsCoverageDetails ? "chevron.up" : "chevron.down")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsCoverageDetails ? "Hide field evidence" : "Show field evidence")

            if showsCoverageDetails {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    ForEach(passport.scopes.filter { $0.field != .coreNutrition }) { scope in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: evidenceIcon(scope.state))
                                .appFont(size: 11, weight: .bold)
                                .foregroundColor(evidenceTint(scope.state))
                                .frame(width: 24, height: 24)
                                .background(evidenceTint(scope.state).opacity(0.10), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(scope.title)
                                        .appFont(size: 11, weight: .bold)
                                        .foregroundColor(.textPrimary)
                                    Spacer(minLength: 4)
                                    Text(scope.state.label)
                                        .appFont(size: 9, weight: .bold)
                                        .foregroundColor(evidenceTint(scope.state))
                                        .multilineTextAlignment(.trailing)
                                }
                                Text(scope.detail)
                                    .appFont(size: 10, weight: .medium)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Label(freshnessText, systemImage: freshnessIcon)
                        .appFont(size: 10, weight: .semibold)
                        .foregroundColor(freshnessTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private var sourceAgreementDisclosure: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.2)) {
                    showsSourceDetails.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.accentPositiveText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sources in agreement")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text(sourceAgreementSummary)
                            .appFont(size: 10, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: showsSourceDetails ? "chevron.up" : "chevron.down")
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsSourceDetails
                    ? "Hide agreeing source details"
                    : "Show agreeing source details"
            )

            if showsSourceDetails {
                VStack(alignment: .leading, spacing: 10) {
                    sourceEvidenceRow(
                        name: sourceName,
                        lineage: metadata?.effectiveEvidenceLineage ?? .unknown,
                        date: metadata?.sourceUpdatedAt ?? metadata?.sourceObservedAt,
                        isPrimary: true
                    )

                    ForEach(supportingEvidence, id: \.sourceName) { evidence in
                        sourceEvidenceRow(
                            name: evidence.sourceName,
                            lineage: evidence.lineage,
                            date: evidence.sourceUpdatedAt ?? evidence.observedAt,
                            isPrimary: false
                        )
                    }

                    Text(sourceAgreementCaveat)
                        .appFont(size: 10, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }
        }
        .accessibilityIdentifier("food_trust_source_agreement")
    }

    private func sourceEvidenceRow(
        name: String,
        lineage: FoodEvidenceLineage,
        date: Date?,
        isPrimary: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isPrimary ? "checkmark.circle.fill" : "plus.circle.fill")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(isPrimary ? .brandForeground : .accentPositiveText)
                .frame(width: 22, height: 22)
                .background(
                    (isPrimary ? Color.brandPrimary : Color.accentPositiveText).opacity(0.10),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(.textPrimary)
                    if isPrimary {
                        Text("Primary")
                            .appFont(size: 8, weight: .bold)
                            .foregroundColor(.brandForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.brandPrimary.opacity(0.10), in: Capsule())
                    }
                }

                Text(lineage.title)
                    .appFont(size: 10, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                if let date {
                    Text("Record date \(date.formatted(.dateTime.year().month(.abbreviated).day()))")
                        .appFont(size: 9, weight: .medium)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceAgreementSummary: String {
        let names = supportingEvidence.map(\.sourceName)
        return ([sourceName] + names).joined(separator: " + ")
    }

    private var sourceAgreementCaveat: String {
        let hasBarcode = !(metadata?.barcode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
        if hasBarcode {
            return "These databases report comparable core nutrition for the matched barcode. They may still reproduce the same manufacturer label, so provider count is not laboratory verification."
        }
        return "These reference records match the search description and report comparable core nutrition after serving normalization. This supports the core values, not exact packaged-product identity."
    }

    private func resolutionNotice(_ resolution: FoodTrustResolution) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentPositiveText)
            VStack(alignment: .leading, spacing: 1) {
                Text(resolution.title)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(resolution.detail)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentPositiveText)
                .frame(width: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(resolution.title). \(resolution.detail)")
    }

    private func receiptStep(
        icon: String,
        title: String,
        value: String,
        detail: String,
        rowTint: Color,
        isLast: Bool,
        showsFindings: Bool = false,
        isEmphasized: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 12, weight: .bold)
                .foregroundColor(rowTint)
                .frame(width: 30, height: 30)
                .background(rowTint.opacity(0.11), in: Circle())
                .overlay {
                    Circle()
                        .stroke(rowTint.opacity(isEmphasized ? 0.48 : 0), lineWidth: 2)
                        .padding(-3)
                }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsFindings, !findings.isEmpty {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(findingFieldTitle(finding))
                                .appFont(size: 10, weight: .bold)
                                .foregroundColor(finding.severity == .warning ? AppPalette.critical : AppPalette.caution)
                            Text(finding.message)
                                .appFont(size: 11, weight: .medium)
                                .foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 3)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(finding.severity == .warning ? AppPalette.critical : AppPalette.caution)
                                .frame(width: 2)
                        }
                    }
                } else {
                    Text(detail)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .overlay(alignment: .topLeading) {
            if !isLast {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color(UIColor.separator).opacity(0.55))
                        .frame(width: 2, height: max(0, proxy.size.height - 27))
                        .offset(x: 14, y: 30)
                }
                .allowsHitTesting(false)
            }
        }
        .background(isEmphasized ? rowTint.opacity(0.055) : Color.clear)
        .scaleEffect(isEmphasized && !reduceMotion ? 1.01 : 1, anchor: .leading)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.22),
            value: isEmphasized
        )
        .accessibilityElement(children: .combine)
    }

    private var nutritionStep: some View {
        receiptStep(
            icon: "checkmark.shield.fill",
            title: "Nutrition Check",
            value: sanityText,
            detail: "No contradictions found in the serving, calories, macros, or fat breakdown.",
            rowTint: sanityTint,
            isLast: false,
            showsFindings: true,
            isEmphasized: presentedResolution != nil
        )
    }

    private var scoreDisclosure: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.2)) {
                    showsScoreDetails.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Why this rating")
                        .appFont(size: 12, weight: .bold)
                    Spacer(minLength: 0)
                    Image(systemName: showsScoreDetails ? "chevron.up" : "chevron.down")
                        .appFont(size: 10, weight: .bold)
                }
                .foregroundColor(.textPrimary)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsScoreDetails ? "Hide Trust rating details" : "Show Trust rating details")

            if showsScoreDetails {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Source index")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Spacer(minLength: 4)
                    Text("\(evaluation.score) / 99")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(tint)
                }

                Text(evaluation.summary)
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * CGFloat(evaluation.score) / 99)
                        }
                }
                .frame(height: 5)
                .accessibilityHidden(true)

                ForEach(Array(visibleReasons.prefix(3))) { reason in
                    Label(reason.text, systemImage: reasonIcon(for: reason))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(reasonTint(for: reason))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("The evidence index ranks source support and consistency. It is not a probability that every field is correct.")
                    .appFont(size: 10, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var reviewDetail: String {
        switch metadata?.reviewStatus {
        case .userEdited:
            return "Your saved nutrition correction is part of this entry."
        case .userConfirmed:
            return "You confirmed the serving or nutrition for this entry."
        case .notRequired:
            return "No personal correction is attached."
        case .unreviewed, nil:
            return descriptor.isEstimated
                ? "Review the serving before relying on this estimate."
                : "No personal review is attached."
        }
    }

    private func evidenceTint(_ state: FoodTrustEvidenceState) -> Color {
        switch state {
        case .crossDatabaseAgreement, .userReviewed:
            return .accentPositiveText
        case .sourceReported:
            return .accentProtein
        case .estimated:
            return AppPalette.caution
        case .needsCorrection:
            return AppPalette.critical
        case .unavailable, .notChecked:
            return Color(UIColor.secondaryLabel)
        }
    }

    private func evidenceIcon(_ state: FoodTrustEvidenceState) -> String {
        switch state {
        case .crossDatabaseAgreement: return "checkmark.seal.fill"
        case .userReviewed: return "person.crop.circle.badge.checkmark"
        case .sourceReported: return "doc.text.fill"
        case .estimated: return "sparkles"
        case .needsCorrection: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        case .notChecked: return "minus.circle.fill"
        }
    }

    private var freshnessText: String {
        let dateText = freshnessDateText
        switch passport.freshness.state {
        case .current:
            if passport.lineage == .governmentCompilation {
                return "Reference dataset released \(dateText ?? "recently")"
            }
            return "Source record updated \(dateText ?? "recently")"
        case .aging:
            if passport.lineage == .governmentCompilation {
                return "Reference dataset was released \(dateText ?? "over 18 months ago")"
            }
            return "Source record was last updated \(dateText ?? "over 18 months ago")"
        case .stale:
            if passport.lineage == .governmentCompilation {
                return "Reference dataset may be stale; release \(dateText ?? "is over three years old")"
            }
            return "Source record may be stale; last update \(dateText ?? "is over three years old")"
        case .retrieved:
            switch passport.lineage {
            case .personalReview:
                return "Saved \(dateText ?? "previously"); no external formulation date"
            case .modelEstimate:
                return "Estimated \(dateText ?? "previously"); no provider formulation date"
            case .derivedEntry:
                return "Created \(dateText ?? "previously"); source formulation date unavailable"
            case .restaurantCatalog:
                return "Catalog observed \(dateText ?? "previously"); menu update date unavailable"
            case .manufacturerLabel:
                return "Label record retrieved \(dateText ?? "previously"); manufacturer update date unavailable"
            default:
                return "Retrieved \(dateText ?? "previously"); provider formulation date unavailable"
            }
        case .unknown:
            return "Provider formulation date unavailable"
        }
    }

    private var freshnessDateText: String? {
        guard let date = passport.freshness.date else { return nil }
        guard passport.lineage == .governmentCompilation else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }

        // CNF release values are calendar dates, not local timestamps. Formatting midnight UTC
        // in a western timezone otherwise shows the previous day.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var freshnessIcon: String {
        switch passport.freshness.state {
        case .current: return "checkmark.circle.fill"
        case .aging: return "clock.fill"
        case .stale: return "exclamationmark.arrow.triangle.2.circlepath"
        case .retrieved: return "tray.and.arrow.down.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var freshnessTint: Color {
        switch passport.freshness.state {
        case .current: return .accentPositiveText
        case .aging: return AppPalette.caution
        case .stale: return AppPalette.critical
        case .retrieved, .unknown: return Color(UIColor.secondaryLabel)
        }
    }

    private func findingFieldTitle(_ finding: FoodDataSanity.Finding) -> String {
        switch finding.id {
        case "saturated_fat_exceeds_total": return "Saturated fat + Total fat"
        case "fiber_exceeds_carbs": return "Fiber + Total carbs"
        case "macros_exceed_serving_weight": return "Macros + Serving weight"
        case "serving_weight_implausible", "energy_density_impossible": return "Serving weight"
        case "sodium_unit_suspect", "sodium_high_for_entry": return "Sodium"
        case "potassium_unit_suspect", "potassium_high_for_entry": return "Potassium"
        case "macros_without_calories", "calories_undercount", "calories_below_macro_estimate",
             "calories_exceed_macros": return "Calories + Macros"
        default: return "Nutrition values"
        }
    }

    @MainActor
    private func presentResolutionIfNeeded() async {
        guard let resolution else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.22)) {
            presentedResolution = resolution
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(resolution.title). \(resolution.detail)"
        )
        do {
            try await Task.sleep(nanoseconds: 2_600_000_000)
        } catch {
            return
        }
        guard presentedResolution?.id == resolution.id else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.14 : 0.2)) {
            presentedResolution = nil
        }
    }

    private func reasonIcon(for reason: FoodTrustReason) -> String {
        switch reason.kind {
        case .evidence:
            return "checkmark.circle.fill"
        case .caution:
            return "exclamationmark.circle.fill"
        case .correction:
            return "exclamationmark.triangle.fill"
        }
    }

    private func reasonTint(for reason: FoodTrustReason) -> Color {
        switch reason.kind {
        case .evidence:
            return Color(UIColor.secondaryLabel)
        case .caution:
            return AppPalette.caution
        case .correction:
            return AppPalette.critical
        }
    }
}
