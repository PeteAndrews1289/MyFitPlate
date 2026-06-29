import SwiftUI

public struct ToastData: Identifiable {
    public let id = UUID()
    public let message: String
    public init(message: String) { self.message = message }
}

public class ToastManager: ObservableObject {
    public static let shared = ToastManager()
    @Published public var toast: ToastData?
    public init() {}
    public func showToast(message: String) {
        self.toast = ToastData(message: message)
    }
}

public struct ToastView: View {
    public let message: String
    
    public init(message: String) {
        self.message = message
    }
    
    public var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .shadow(radius: 4)
    }
}

public struct ToastModifier: ViewModifier {
    @ObservedObject public var manager = ToastManager.shared

    public init() {}

    public func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let toast = manager.toast {
                ToastView(message: toast.message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 50)
                    .zIndex(1)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                manager.toast = nil
                            }
                        }
                    }
            }
        }
        .animation(.spring(), value: manager.toast?.id)
    }
}

public extension View {
    func withGlobalToast() -> some View {
        self.modifier(ToastModifier())
    }
}
