import SwiftUI
import FirebaseAuth

struct AITextLogView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var mealDescription = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var estimatedItems: [FoodItem]?
    @State private var showResults = false
    
    private let textLogService = AITextLogService()

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    Text("Describe Your Meal")
                        .appFont(size: 24, weight: .bold)
                        .padding(.top)

                    Text("Describe what you ate, and Maia will estimate the nutrition for you. For example: \"A bowl of oatmeal with blueberries and a coffee\"")
                        .appFont(size: 15)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TextEditor(text: $mealDescription)
                        .padding(10)
                        .background(Color.backgroundSecondary)
                        .cornerRadius(12)
                        .frame(height: 150)
                        .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                    
                    Spacer()

                    Button(action: analyzeText) {
                        Text("Analyze with AI")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading || mealDescription.isEmpty)
                    .padding()
                }
                .navigationTitle("Describe Meal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .sheet(isPresented: $showResults) {
                    if let items = estimatedItems {
                        AITextResultsView(foodItems: .constant(items)) {
                            dismiss()
                        }
                    }
                }
                
                if isLoading {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView("Analyzing your description...")
                }
            }
        }
    }
    
    private func analyzeText() {
        isLoading = true
        errorMessage = nil
        
        Task {
            let result = await textLogService.estimateNutrition(from: mealDescription)
            isLoading = false
            
            switch result {
            case .success(let foodItems):
                self.estimatedItems = foodItems
                self.showResults = true
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
