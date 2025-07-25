import SwiftUI

struct HealthDisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                generalDisclaimerSection
                calorieSourceSection
                micronutrientSourceSection
                aiAndInsightsDisclaimerSection
            }
            .padding()
        }
        .navigationTitle("Disclaimers & Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var generalDisclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General Disclaimer")
                .appFont(size: 22, weight: .bold)
            Text("The information and recommendations provided by this application are for general informational and educational purposes only. They are not a substitute for the advice of a qualified healthcare professional. Always consult with your doctor or a registered dietitian before making significant changes to your diet or exercise routine.")
                .appFont(size: 15)
        }
    }

    private var calorieSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calorie & BMR Calculations")
                .appFont(size: 17, weight: .semibold)
            Text("Our calorie recommendations are estimated using the Mifflin-St Jeor equation to calculate your Basal Metabolic Rate (BMR), combined with standard activity level multipliers to estimate your total daily energy expenditure (TDEE).")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/") {
                Link("Source: Mifflin, M. D., et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.", destination: url)
                    .appFont(size: 12)
            }
        }
    }
    
    private var micronutrientSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Micronutrient Goals")
                .appFont(size: 17, weight: .semibold)
            Text("Daily goals for micronutrients (e.g., calcium, iron, vitamins) are based on the Dietary Reference Intakes (DRIs) established by the Health and Medicine Division of the National Academies of Sciences, Engineering, and Medicine.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if let url = URL(string: "https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator") {
                Link("Source: USDA Dietary Reference Intakes (DRIs)", destination: url)
                    .appFont(size: 12)
            }
        }
    }

    private var aiAndInsightsDisclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI & Generated Insights")
                .appFont(size: 17, weight: .semibold)
            Text("The AI Chatbot and generated Insights features provide nutritional estimates and suggestions based on algorithms and general data. This information may be inaccurate or incomplete and should be used as a guideline, not as a definitive source of truth. Always verify critical information with a qualified professional.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
    }
}
