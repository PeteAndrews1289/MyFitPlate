import SwiftUI

struct HealthDisclaimerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Safety & Sources",
                        title: "How to Use MyFitPlate",
                        subtitle: "Understand what is estimated, where key guidance comes from, and when to consult a professional."
                    )

                    VStack(spacing: 0) {
                        DisclaimerRow(
                            icon: "exclamationmark.triangle.fill",
                            color: AppPalette.caution,
                            title: "General Guidance",
                            description: "The information and recommendations provided by this application are for general informational and educational purposes only. They are not a substitute for the advice of a qualified healthcare professional. Always consult with your doctor or a registered dietitian before making significant changes to your diet or exercise routine."
                        )

                        Divider().padding(.leading, 64)

                        DisclaimerRow(
                            icon: "flame.fill",
                            color: AppPalette.brand,
                            title: "Calorie & BMR Calculations",
                            description: "Our calorie recommendations are estimated using the Mifflin-St Jeor equation to calculate your Basal Metabolic Rate (BMR), combined with standard activity level multipliers to estimate your total daily energy expenditure (TDEE).",
                            sourceText: "Source: Mifflin, M. D., et al. Am J Clin Nutr. 1990.",
                            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/2305711/"
                        )

                        Divider().padding(.leading, 64)

                        DisclaimerRow(
                            icon: "leaf.fill",
                            color: AppPalette.positive,
                            title: "Micronutrient Goals",
                            description: "Daily goals for micronutrients (e.g., calcium, iron, vitamins) are based on the Dietary Reference Intakes (DRIs) established by the Health and Medicine Division of the National Academies of Sciences, Engineering, and Medicine.",
                            sourceText: "Source: USDA Dietary Reference Intakes (DRIs)",
                            sourceURL: "https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator"
                        )

                        Divider().padding(.leading, 64)

                        DisclaimerRow(
                            icon: "sparkles",
                            color: AppPalette.brand,
                            title: "AI & Generated Insights",
                            description: "The AI Chatbot and generated Insights features provide nutritional estimates and suggestions based on algorithms and general data. This information may be inaccurate or incomplete and should be used as a guideline, not as a definitive source of truth. Always verify critical information with a qualified professional."
                        )
                    }
                    .appSurface(.quiet, padding: 0, radius: AppRadius.control)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Disclaimers & Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("settings_disclaimer_screen")
    }
}

private struct DisclaimerRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    var sourceText: String?
    var sourceURL: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(
                    AppPalette.surface,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                
                Text(description)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let sourceText = sourceText, let sourceURL = sourceURL, let url = URL(string: sourceURL) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text(sourceText)
                        }
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.brand)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(AppSpacing.group)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
