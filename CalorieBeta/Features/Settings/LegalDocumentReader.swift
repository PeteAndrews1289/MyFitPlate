import MyFitPlateShared
import SwiftUI

private enum LegalDocument: String, Identifiable, Hashable {
    case privacy = "privacy_policy"
    case terms = "terms_of_service"

    var id: Self { self }
    var title: String { self == .privacy ? "Privacy policy" : "Terms of service" }
    var publicURL: URL { self == .privacy ? MyFitPlateLinks.privacyPolicyURL : MyFitPlateLinks.termsOfServiceURL }

    init?(url: URL) {
        switch url {
        case MyFitPlateLinks.privacyPolicyURL: self = .privacy
        case MyFitPlateLinks.termsOfServiceURL: self = .terms
        default: return nil
        }
    }
}

extension View {
    func legalDocumentLinks() -> some View { modifier(LegalDocumentPresentation()) }
}

private struct LegalDocumentPresentation: ViewModifier {
    @State private var document: LegalDocument?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let destination = LegalDocument(url: url) else { return .systemAction }
                document = destination
                return .handled
            })
            .sheet(item: $document) { LegalDocumentReader(document: $0) }
    }
}

private struct LegalDocumentReader: View {
    let document: LegalDocument
    @State private var path: [LegalDocument] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            page(document)
                .navigationDestination(for: LegalDocument.self) { page($0) }
        }
    }

    private func page(_ document: LegalDocument) -> some View {
        LegalDocumentPage(document: document)
            .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
            .environment(\.openURL, OpenURLAction { url in
                guard let destination = LegalDocument(url: url) else { return .systemAction }
                if destination != document { path.append(destination) }
                return .handled
            })
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Link("Open public version", destination: document.publicURL)
                        .environment(\.openURL, OpenURLAction { _ in .systemAction })
                }
            }
    }
}

private struct LegalDocumentPage: View {
    let document: LegalDocument
    @State private var lines: [String]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                if let lines {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("# ") {
                            Text(String(line.dropFirst(2))).appTextRole(.screenTitle)
                        } else if line.hasPrefix("## ") {
                            Text(String(line.dropFirst(3))).appTextRole(.sectionTitle).padding(.top, AppSpacing.row)
                        } else {
                            let text = line.hasPrefix("- ") ? "• " + line.dropFirst(2) : line
                            Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
                                                        baseURL: document.publicURL.deletingLastPathComponent().appendingPathComponent("", isDirectory: true))) ?? AttributedString(text))
                                .appTextRole(.body)
                        }
                    }
                } else {
                    Text("Use the public version below to read this document.").appTextRole(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.screenHorizontal)
            .textSelection(.enabled)
        }
        .background(AppPalette.canvas)
        .accessibilityIdentifier("legal_document_" + document.rawValue)
        .onAppear {
            if let file = Bundle.main.url(forResource: document.rawValue, withExtension: "md"),
               let source = try? String(contentsOf: file, encoding: .utf8) {
                lines = source.split(whereSeparator: \.isNewline).map(String.init)
            }
        }
    }
}
