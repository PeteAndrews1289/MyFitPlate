import SwiftUI

struct AITextLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var mealDescription = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var estimatedItems: [FoodItem]?
    @State private var showResults = false
    @FocusState private var descriptionIsFocused: Bool

    private let textLogService = AITextLogService()

    init() {
        #if DEBUG
        guard ScreenshotDemoMode.isEnabled else { return }
        let screen = ScreenshotDemoData.requestedScreen
        if screen == "ai-text-log" || screen == "ai-text-results" {
            _mealDescription = State(
                initialValue: "A chicken burrito bowl with brown rice, black beans, fajita vegetables, guacamole, salsa, and a small handful of tortilla chips."
            )
        }
        if screen == "ai-text-results" {
            _estimatedItems = State(initialValue: ScreenshotDemoData.aiTextDemoFoods)
            _showResults = State(initialValue: true)
        }
        #endif
    }

    private var trimmedDescription: String {
        mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        AppScreenHeader(
                            eyebrow: "Maia Quick Log",
                            title: "Describe a Meal",
                            subtitle: "Write what you ate in your own words. Maia will separate it into foods for you to review."
                        )
                        .accessibilityIdentifier("ai_text_header")

                        descriptionSection
                        detailGuidance

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .appTextRole(.secondary)
                                .foregroundStyle(AppPalette.critical)
                                .fixedSize(horizontal: false, vertical: true)
                                .appSurface(.quiet)
                                .accessibilityIdentifier("ai_text_error")
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                    .padding(.bottom, AppSpacing.group)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppPalette.canvas.ignoresSafeArea())
                .navigationTitle("Describe Meal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .tint(AppPalette.brand)
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { descriptionIsFocused = false }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(action: analyzeText) {
                        Label("Review Estimate", systemImage: "sparkles")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(isLoading || trimmedDescription.isEmpty)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.row)
                    .padding(.bottom, AppSpacing.compact)
                    .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppPalette.separator)
                            .frame(height: 1)
                    }
                    .accessibilityIdentifier("ai_text_review_action")
                }
                .sheet(isPresented: $showResults) {
                    if let estimatedItems {
                        AITextResultsView(foodItems: estimatedItems) {
                            dismiss()
                        }
                    }
                }

                if isLoading {
                    loadingOverlay
                }
            }
        }
        .accessibilityIdentifier("ai_text_log")
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Meal Description",
                subtitle: "One sentence is enough. Include amounts when you know them."
            )

            ZStack(alignment: .topLeading) {
                if trimmedDescription.isEmpty {
                    Text("Example: oatmeal with blueberries and peanut butter, plus a coffee with milk")
                        .appTextRole(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, AppSpacing.group)
                        .padding(.vertical, AppSpacing.group + 2)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $mealDescription)
                    .appTextRole(.body)
                    .foregroundStyle(AppPalette.text)
                    .focused($descriptionIsFocused)
                    .padding(AppSpacing.compact)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 250 : 190)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Meal description")
                    .accessibilityIdentifier("ai_text_description")
            }
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_text_description_section")
    }

    private var detailGuidance: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Details That Help",
                subtitle: "Add only what you remember. You can correct every item before logging."
            )

            AITextGuidanceRow(icon: "scalemass", text: "Portion or serving size")
            Divider()
            AITextGuidanceRow(icon: "tag", text: "Brand or restaurant")
            Divider()
            AITextGuidanceRow(icon: "drop", text: "Sauces, oils, and toppings")
            Divider()
            AITextGuidanceRow(icon: "frying.pan", text: "Cooking method")

            Label(
                "Maia provides an estimate, not a verified database match. Nothing is logged until you review it.",
                systemImage: "checkmark.shield"
            )
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, AppSpacing.compact)
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_text_guidance")
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()

            VStack(spacing: AppSpacing.row) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppPalette.brand)

                Text("Building your review")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text("Maia is separating foods and estimating portions.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appSurface(.emphasized)
            .padding(AppSpacing.screenHorizontal)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ai_text_loading")
        }
    }

    private func analyzeText() {
        descriptionIsFocused = false
        isLoading = true
        errorMessage = nil

        Task {
            let result = await textLogService.estimateNutrition(from: trimmedDescription)
            isLoading = false

            switch result {
            case .success(let foodItems):
                estimatedItems = foodItems
                showResults = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AITextGuidanceRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .appTextRole(.body)
            .foregroundStyle(AppPalette.text)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}
