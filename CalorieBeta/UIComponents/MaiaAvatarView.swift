import SwiftUI

struct MaiaAvatarView: View {
    @ObservedObject var ttsManager: TTSManager

    var body: some View {
        ZStack {
            Image("maia_avatar")
                .resizable()
                .scaledToFit()
            
            Image(ttsManager.mouthShape)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .offset(y: 15)
                .animation(.easeInOut(duration: 0.1), value: ttsManager.mouthShape)
        }
        .frame(width: 100, height: 100)
        .scaleEffect(ttsManager.isSpeaking ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: ttsManager.isSpeaking)
    }
}
