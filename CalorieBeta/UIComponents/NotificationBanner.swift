import SwiftUI

struct NotificationBanner: View {
    @Binding var banner: BannerData?
    
    var body: some View {
        VStack {
            if let bannerData = banner {
                VStack {
                    HStack {
                        Image(systemName: bannerData.iconName)
                            .font(.title2)
                            .foregroundColor(bannerData.iconColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bannerData.title)
                                .appFont(size: 17, weight: .semibold)
                            Text(bannerData.message)
                                .appFont(size: 15)
                        }
                        Spacer()
                    }
                    .foregroundStyle(AppPalette.text)
                    .padding(AppSpacing.group)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.surface))
                    .overlay { RoundedRectangle(cornerRadius: AppRadius.surface).stroke(AppPalette.separator, lineWidth: 1) }
                }
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: bannerData) {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    guard !Task.isCancelled, banner == bannerData else { return }
                    withAnimation { banner = nil }
                }
                .onTapGesture {
                     withAnimation {
                         self.banner = nil
                     }
                }
            }
            Spacer()
        }
        .animation(.easeInOut, value: banner)
    }
}
