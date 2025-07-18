import SwiftUI

struct SpotlightTextView: View {
    let content: (title: String, text: String)
    let currentIndex: Int
    let total: Int
    let onNext: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(alignment: .leading, spacing: 16) {
                Text(content.title)
                    .font(.title2.bold())
                
                Text(content.text)
                    .font(.body)
                
                HStack {
                    Text("\(currentIndex + 1) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                    
                    Button(currentIndex == total - 1 ? "Done" : "Next", action: onNext)
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                }
            }
            .padding()
            .background(colorScheme == .dark ? Color(.secondarySystemBackground) : .white)
            .cornerRadius(12)
            .shadow(radius: 10)
            .padding(.horizontal)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .ignoresSafeArea()
    }
}