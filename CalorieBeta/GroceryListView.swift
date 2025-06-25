import SwiftUI
import FirebaseAuth

struct GroceryListView: View {
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) var dismiss
    
    @State private var groceryList: [GroceryListItem] = []
    @State private var isLoading = true
    @State private var showingBarcodeScanner = false
    @State private var isFetchingItemName = false
    @State private var fetchError: (isShowing: Bool, message: String) = (false, "")
    
    private let foodAPIService = FatSecretFoodAPIService()

    private var groupedList: [String: [GroceryListItem]] {
        Dictionary(grouping: groceryList, by: { $0.category })
    }
    
    private var sortedCategories: [String] {
        groupedList.keys.sorted {
            if $0 == "Pantry" { return false }
            if $1 == "Pantry" { return true }
            if $0 == "Misc" { return false }
            if $1 == "Misc" { return true }
            return $0 < $1
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("Loading Grocery List...")
                    Spacer()
                } else if !groceryList.isEmpty {
                    List {
                        ForEach(sortedCategories, id: \.self) { category in
                            Section(header: Text(category)) {
                                ForEach($groceryList.filter { $item in
                                    $item.wrappedValue.category == category
                                }) { $item in
                                    GroceryItemRow(item: $item, onToggle: saveList)
                                }
                                .onDelete { indexSet in
                                    deleteItems(in: category, at: indexSet)
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                } else {
                    VStack {
                        Spacer()
                        Text("No grocery list found.")
                            .foregroundColor(.gray)
                        Text("Use the 'Meal Plan Generator' or the barcode scanner to add items.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Grocery List")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Clear List", role: .destructive, action: clearList)
                        Button(action: { showingBarcodeScanner = true }) {
                            Image(systemName: "barcode.viewfinder")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView { barcode in
                    showingBarcodeScanner = false
                    isFetchingItemName = true
                    
                    foodAPIService.fetchFoodByBarcode(barcode: barcode) { result in
                        DispatchQueue.main.async {
                            isFetchingItemName = false
                            switch result {
                            case .success(let foodItem):
                                let newItem = GroceryListItem(name: foodItem.name, quantity: 1, unit: "item", category: "Misc")
                                groceryList.append(newItem)
                                saveList()
                            case .failure(let error):
                                fetchError = (true, "Could not find an item for that barcode. \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            .alert("Barcode Error", isPresented: $fetchError.isShowing) {
                Button("OK") {}
            } message: {
                Text(fetchError.message)
            }
            .onAppear {
                Task {
                    await loadList()
                }
            }
            
            if isFetchingItemName {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                VStack {
                    ProgressView("Finding Item...")
                    Text("Looking up barcode...")
                        .font(.caption)
                        .padding(.top)
                }
                .padding(30)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(Color.primary)
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
    }
    
    private func deleteItems(in category: String, at offsets: IndexSet) {
        let itemsForCategory = groceryList.filter { $0.category == category }
        let idsToRemove = offsets.map { itemsForCategory[$0].id }
        groceryList.removeAll { idsToRemove.contains($0.id) }
        saveList()
    }
    
    private func loadList() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        self.groceryList = await mealPlannerService.fetchGroceryList(for: userID)
        self.isLoading = false
    }
    
    private func saveList() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        mealPlannerService.saveGroceryList(groceryList, for: userID)
    }

    private func clearList() {
        groceryList = []
        saveList()
    }
}

struct GroceryItemRow: View {
    @Binding var item: GroceryListItem
    var onToggle: () -> Void
    
    private var quantityText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        
        if item.quantity == floor(item.quantity) {
             formatter.maximumFractionDigits = 0
        }

        let formattedQuantity = formatter.string(from: NSNumber(value: item.quantity)) ?? ""
        
        if item.unit.lowercased() == "item" || item.unit.lowercased() == "to taste" || item.quantity == 0 {
            return ""
        }
        
        return "\(formattedQuantity) \(item.unit)"
    }
    
    var body: some View {
        Button(action: {
            item.isCompleted.toggle()
            onToggle()
        }) {
            HStack {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .green : .primary)
                Text(item.name)
                    .strikethrough(item.isCompleted, color: .primary)
                    .foregroundColor(item.isCompleted ? .secondary : .primary)
                Spacer()
                Text(quantityText)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
