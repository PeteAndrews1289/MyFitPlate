import MyFitPlateCore
import SwiftUI

struct UsefulMealQuestionCard: View {
    let question: UsefulMealQuestion
    let item: FoodItem
    let onAnswer: (MealQuestionAnswer) -> Void
    @State private var selectedAnswer: MealQuestionAnswer?
    @State private var measuredGrams = ""

    private var preview: MealQuestionPreview? {
        selectedAnswer.flatMap { UsefulMealQuestionRules.preview(answer: $0, question: question, item: item) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("One useful question", systemImage: "questionmark.bubble")
                .appTextRole(.control)
            Text("About how much \(question.name.lowercased()) did you have?").appTextRole(.body)
            Text(question.reason).appTextRole(.secondary).foregroundStyle(.secondary)
            ForEach(Array(question.anchors.enumerated()), id: \.offset) { index, anchor in
                ForEach(counts(for: anchor), id: \.self) { count in
                    let grams = anchor.gramsPerUnit * count
                    Button { selectedAnswer = .anchor(index: index, count: count) } label: {
                        HStack {
                            Text(anchor.label(count: count))
                            Spacer()
                            Text("About \(Int(grams.rounded())) g").foregroundStyle(.secondary)
                            if selectedAnswer == .anchor(index: index, count: count) { Image(systemName: "checkmark.circle.fill") }
                        }.appTextRole(.body).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(AppPalette.text)
                    .accessibilityIdentifier("meal_question_\(Int(grams.rounded()))")
                }
            }
            if question.canUseMeasuredGrams {
                TextField("If you weighed it: grams", text: $measuredGrams)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("meal_question_measured")
                    .onChange(of: measuredGrams) { _, value in
                        selectedAnswer = Double(value).map(MealQuestionAnswer.measuredGrams)
                    }
            }
            if let preview {
                Text("\(Int(item.calories.rounded())) → \(Int(preview.food.calories.rounded())) cal · protein \(Int(item.protein.rounded())) → \(Int(preview.food.protein.rounded())) g")
                    .appTextRole(.body).accessibilityIdentifier("meal_question_preview")
                Button("Apply portion") { if let selectedAnswer { onAnswer(selectedAnswer) } }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("meal_question_apply")
            }
            Button("Not sure — keep estimate") { onAnswer(.skip) }
                .buttonStyle(AppActionButtonStyle(.ghost))
                .accessibilityIdentifier("meal_question_skip")
            DisclosureGroup("Portion references") {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ForEach(Array(question.anchors.enumerated()), id: \.offset) { _, anchor in
                        Text("\(anchor.label(count: 1)) ≈ \(anchor.gramsPerUnit.formatted(.number.precision(.fractionLength(0...1)))) g · \(anchor.sourceName)")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    Text("Use a reference only if it matches your food.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }.padding(.top, AppSpacing.compact)
            }.appTextRole(.secondary).tint(AppPalette.text)
            Text(question.uncertainty == .separateCookingAddition
                 ? "This changes only the separately listed ingredient. It does not add oil to another food."
                 : "Optional. Oils, sauces and cooking methods remain separate uncertainty.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
    }

    private func counts(for anchor: MealPortionAnchor) -> [Double] {
        anchor.answerCounts(lowGrams: question.lowGrams, highGrams: question.highGrams)
    }
}
