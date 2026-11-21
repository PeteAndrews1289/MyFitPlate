import MyFitPlateCore
import SwiftUI

struct PlannedStockReservationsLink: View {
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Label("Planned stock reservations", systemImage: "calendar.badge.clock").frame(minHeight: 44)
        }
        .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("inventory_planned_reservations")
        .sheet(isPresented: $showing) { PlannedStockReservationsView() }
    }
}

struct PlannedStockReservationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = InventoryReservationService()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Saved plans reserve compatible, confirmed ingredient quantities in cooking-date order across future dates. These are planned allocations, not physical deductions or stock locks. Actual cooking rechecks the selected lots.")
                        .foregroundStyle(.secondary)
                    Text("Removing or resizing a saved plan changes this projection. Recording a batch cooked releases its raw reservation; leftover meals do not reserve those ingredients again.")
                        .font(.caption).foregroundStyle(.secondary)
                    if service.isLoading { ProgressView("Refreshing saved plans and physical stock") }
                    if let error = service.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                    Button("Refresh reservations") { Task { await refresh() } }.disabled(service.isLoading)
                }
                if let snapshot = service.snapshot {
                    Section("Scope and freshness") {
                        Text("From \(snapshot.referenceDayID) · all saved future dates")
                        Text("Calculated \(snapshot.generatedAt.formatted())\(service.isFresh ? "" : " · cached, may be stale")")
                            .foregroundStyle(service.isFresh ? .secondary : AppPalette.caution)
                        if snapshot.excludedPastMeals > 0 { Text("\(snapshot.excludedPastMeals) past planned meal entries are excluded. Past meals are not assumed to have been cooked or eaten.").font(.caption) }
                    }
                    Section("Physical stock and planned allocations") {
                        ForEach(snapshot.physicalStock.filter { !$0.isCookedBatch && $0.isArchived != true }) { lot in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(lot.name).fontWeight(.semibold)
                                if lot.quantityUnknown == true || lot.quantityVerified != true {
                                    Text("Physical amount unconfirmed · no automatic reservation").foregroundStyle(AppPalette.caution)
                                } else {
                                    Text("Physical \(lot.quantity.formatted()) \(lot.unit)")
                                    Text("Planned \(snapshot.reserved(in: lot.id).formatted()) \(lot.unit) · Unallocated physical \((snapshot.available(in: lot.id) ?? 0).formatted()) \(lot.unit)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("Usability still depends on preparation, compatible units and your entered label date.").font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityElement(children: .combine).accessibilityIdentifier("inventory_reservation_lot_\(lot.id)")
                        }
                    }
                    Section("Planned cooking and shortages") {
                        ForEach(snapshot.requirements) { requirement in
                            DisclosureGroup {
                                if let note = requirement.note { Text(note).foregroundStyle(.secondary) }
                                ForEach(Array(requirement.ingredients.enumerated()), id: \.offset) { index, ingredient in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ingredient.name)
                                        Text(ingredient.hasKnownAmount ? "Required \(ingredient.quantity.formatted()) \(ingredient.unit)" : "Amount unknown · \(ingredient.originalText)")
                                            .font(.caption)
                                        ForEach(snapshot.allocations.filter { $0.requirementID == requirement.id && $0.ingredientIndex == index }) { allocation in
                                            if let lot = snapshot.physicalStock.first(where: { $0.id == allocation.lotID }) {
                                                Text("Planned from \(lot.name): \(allocation.lotQuantity.formatted()) \(lot.unit)").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                ForEach(snapshot.shortages.filter { $0.requirementID == requirement.id }) { shortage in
                                    Text(shortage.unallocated.map { "Missing \($0.formatted()) \(shortage.unit) \(shortage.name)" } ?? "Review \(shortage.name): amount or stock coverage unknown")
                                        .foregroundStyle(AppPalette.caution)
                                    Text(shortage.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(requirement.name)
                                    Text("\(requirement.dayID) · \(requirement.state == .alreadyCooked ? "Already cooked" : requirement.state == .needsReview ? "Needs review" : "Planned")").font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("inventory_reservation_requirement_\(requirement.id)")
                        }
                        if snapshot.requirements.isEmpty { Text("No mapped future cooking requirements in the saved plans.").foregroundStyle(.secondary) }
                    }
                } else if !service.isLoading { Text("Reservation coverage is unavailable. No stock has been changed or assumed free.").foregroundStyle(.secondary) }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle()).navigationTitle("Planned reservations")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await refresh() }.refreshable { await refresh() }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("inventory_reservations_screen")
    }
    private func refresh() async { await service.refresh(using: DIContainer.shared.nutritionRepository) }
}

struct CookingReservationSummary: View {
    let snapshot: InventoryReservationSnapshot
    let batchID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planned reservations are separate from physical stock. Your own batch's allocation is counted once; other planned batches stay visible.").font(.caption).foregroundStyle(.secondary)
            ForEach(snapshot.physicalStock.filter { snapshot.reserved(in: $0.id) > 0 }) { lot in
                let other = snapshot.reserved(in: lot.id, excluding: "batch-" + batchID)
                let own = snapshot.reserved(in: lot.id) - other
                Text("\(lot.name): this batch \(own.formatted()) \(lot.unit), other plans \(other.formatted()) \(lot.unit)")
                    .font(.caption).accessibilityIdentifier("inventory_cook_reservation_\(lot.id)")
            }
        }
    }
}
