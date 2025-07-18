import SwiftUI

enum SpotlightTextPosition {
    case top
    case bottom
}

struct SpotlightTextView: View {
    let content: (title: String, text: String)
    let currentIndex: Int
    let total: Int
    let position: SpotlightTextPosition
    let onNext: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            if position == .bottom {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text(content.title)
                    .font(.title2.bold())
                    .padding(.bottom, 8)
                
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
            .padding(position == .top ? .top : .bottom, 100)
            
            if position == .top {
                Spacer()
            }
        }
        .transition(.move(edge: position == .top ? .top : .bottom).combined(with: .opacity))
        .ignoresSafeArea()
    }
}
