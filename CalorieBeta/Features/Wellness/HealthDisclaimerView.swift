import SwiftUI

struct HealthDisclaimerView: View {
    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            ScrollView {
                VStack(spacing: 16) {
                    DisclaimerCard(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "General Disclaimer",
                        description: "The information and recommendations provided by this application are for general informational and educational purposes only. They are not a substitute for the advice of a qualified healthcare professional. Always consult with your doctor or a registered dietitian before making significant changes to your diet or exercise routine."
                    )
                    
                    DisclaimerCard(
                        icon: "flame.fill",
                        color: .brandPrimary,
                        title: "Calorie & BMR Calculations",
                        description: "Our calorie recommendations are estimated using the Mifflin-St Jeor equation to calculate your Basal Metabolic Rate (BMR), combined with standard activity level multipliers to estimate your total daily energy expenditure (TDEE).",
                        sourceText: "Source: Mifflin, M. D., et al. Am J Clin Nutr. 1990.",
                        sourceURL: "https://pubmed.ncbi.nlm.nih.gov/2305711/"
                    )
                    
                    DisclaimerCard(
                        icon: "leaf.fill",
                        color: .green,
                        title: "Micronutrient Goals",
                        description: "Daily goals for micronutrients (e.g., calcium, iron, vitamins) are based on the Dietary Reference Intakes (DRIs) established by the Health and Medicine Division of the National Academies of Sciences, Engineering, and Medicine.",
                        sourceText: "Source: USDA Dietary Reference Intakes (DRIs)",
                        sourceURL: "https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator"
                    )
                    
                    DisclaimerCard(
                        icon: "sparkles",
                        color: .purple,
                        title: "AI & Generated Insights",
                        description: "The AI Chatbot and generated Insights features provide nutritional estimates and suggestions based on algorithms and general data. This information may be inaccurate or incomplete and should be used as a guideline, not as a definitive source of truth. Always verify critical information with a qualified professional."
                    )
                }
                .padding(20)
            }
        }
        .navigationTitle("Disclaimers & Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DisclaimerCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    var sourceText: String? = nil
    var sourceURL: String? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                
                Text(description)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                
                if let sourceText = sourceText, let sourceURL = sourceURL, let url = URL(string: sourceURL) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text(sourceText)
                        }
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}
