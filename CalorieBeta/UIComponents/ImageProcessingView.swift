import SwiftUI

enum ImageProcessingKind {
    case mealPhoto
    case menuPhoto
    case nutritionLabel
    case receiptPhoto

    var eyebrow: String {
        switch self {
        case .mealPhoto:
            return "Meal Photo"
        case .menuPhoto:
            return "Menu Photo"
        case .nutritionLabel:
            return "Nutrition Label"
        case .receiptPhoto:
            return "Grocery Receipt"
        }
    }

    var title: String {
        switch self {
        case .mealPhoto:
            return "Building a food draft"
        case .menuPhoto:
            return "Reading the menu"
        case .nutritionLabel:
            return "Reading label details"
        case .receiptPhoto:
            return "Building a pantry draft"
        }
    }

    var icon: String {
        switch self {
        case .mealPhoto:
            return "camera.metering.center.weighted"
        case .menuPhoto:
            return "menucard"
        case .nutritionLabel:
            return "doc.text.viewfinder"
        case .receiptPhoto:
            return "doc.text.magnifyingglass"
        }
    }

    var stages: [String] {
        switch self {
        case .mealPhoto:
            return [
                "Finding visible foods",
                "Estimating portions",
                "Preparing your review"
            ]
        case .menuPhoto:
            return [
                "Finding menu items",
                "Reading names and details",
                "Preparing choices"
            ]
        case .nutritionLabel:
            return [
                "Finding serving details",
                "Reading nutrients",
                "Checking the result"
            ]
        case .receiptPhoto:
            return [
                "Finding purchased items",
                "Reading quantities",
                "Preparing your pantry review"
            ]
        }
    }

    var reviewMessage: String {
        switch self {
        case .mealPhoto:
            return "Nothing is logged automatically. You will confirm every food and portion next."
        case .menuPhoto:
            return "You will choose which menu items to keep before anything is added."
        case .nutritionLabel:
            return "The scanned values stay editable so you can compare them with the package."
        case .receiptPhoto:
            return "Nothing reaches your pantry until you review every detected item."
        }
    }
}

struct ImageProcessingView: View {
    let kind: ImageProcessingKind
    var onCancel: (() -> Void)?

    @State private var stageIndex = 0

    init(kind: ImageProcessingKind = .mealPhoto, onCancel: (() -> Void)? = nil) {
        self.kind = kind
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: kind.icon)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.brandText)
                        .frame(width: 44, height: 44)
                        .background(AppPalette.brand.opacity(0.12), in: RoundedRectangle(
                            cornerRadius: AppRadius.control,
                            style: .continuous
                        ))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.eyebrow.uppercased())
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.brandText)

                        Text(kind.title)
                            .appTextRole(.sectionTitle)
                            .foregroundStyle(AppPalette.text)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ProgressView()
                        .tint(AppPalette.brand)
                        .accessibilityHidden(true)

                    Text(kind.stages[stageIndex])
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .contentTransition(.opacity)
                        .animation(AppMotion.visibility, value: stageIndex)
                }
                .padding(AppSpacing.row)
                .background(AppPalette.control, in: RoundedRectangle(
                    cornerRadius: AppRadius.control,
                    style: .continuous
                ))

                Label(kind.reviewMessage, systemImage: "checkmark.shield")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let onCancel {
                    Button("Stop waiting", role: .cancel, action: onCancel)
                        .buttonStyle(AppActionButtonStyle(.ghost))
                        .accessibilityHint("Returns without using this analysis")
                }
            }
            .padding(AppSpacing.section)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(
                cornerRadius: AppRadius.surface,
                style: .continuous
            ))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
            .padding(AppSpacing.screenHorizontal)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(kind.title). \(kind.stages[stageIndex])")
            .task(id: kind.eyebrow) {
                stageIndex = 0
                for index in kind.stages.indices.dropFirst() {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard !Task.isCancelled else { return }
                    stageIndex = index
                }
            }
        }
    }
}
