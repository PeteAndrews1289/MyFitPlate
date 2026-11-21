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
            .appTextRole(.secondary)
            .foregroundStyle(AppPalette.text)
            .multilineTextAlignment(.center)
            .padding(AppSpacing.group)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            .overlay { RoundedRectangle(cornerRadius: AppRadius.surface).stroke(AppPalette.separator, lineWidth: 1) }
            .frame(maxWidth: 520)
            .padding(.horizontal, AppSpacing.screenHorizontal)
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
                    .task(id: toast.id) {
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        guard !Task.isCancelled, manager.toast?.id == toast.id else { return }
                        withAnimation { manager.toast = nil }
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
