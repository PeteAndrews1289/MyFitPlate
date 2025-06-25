

import SwiftUI

struct BannerView: View {
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
                                .font(.headline)
                            Text(bannerData.message)
                                .font(.subheadline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                }
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.banner = nil
                        }
                    }
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

struct BannerData: Equatable {
    var title: String
    var message: String
    var iconName: String = "checkmark.circle.fill"
    var iconColor: Color = .green
}
