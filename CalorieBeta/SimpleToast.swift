
import SwiftUI

// This is the view for the toast message itself
struct SimpleToast: View {
    let message: String
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color.black.opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(15)
            .shadow(radius: 10)
    }
}

// This is a View Modifier that will present the toast over your content
struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    
    func body(content: Content) -> some View {
        ZStack {
            content // Your main view content
            
            // The toast view, shown only when isShowing is true
            if isShowing {
                VStack {
                    Spacer()
                    SimpleToast(message: message)
                        .padding(.bottom, 50) // Position it above the tab bar
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .onAppear {
                    // Automatically hide the toast after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isShowing = false
                        }
                    }
                }
            }
        }
    }
}

// An extension to make the modifier easy to use
extension View {
    func simpleToast(isShowing: Binding<Bool>, message: String) -> some View {
        self.modifier(ToastModifier(isShowing: isShowing, message: message))
    }
}
