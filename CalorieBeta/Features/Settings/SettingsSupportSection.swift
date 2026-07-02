import SwiftUI

struct SettingsSupportSection: View {
    @Binding var showingHealthDisclaimer: Bool
    @Binding var showingResetTourConfirmation: Bool
    @Binding var showingSignOutAlert: Bool
    @Binding var showingDeleteAccountAlert: Bool
    let isDeletingAccount: Bool

    var body: some View {
        VStack(spacing: 24) {
            SettingsSectionCard(title: "Help & support") {
                Button {
                    showingHealthDisclaimer = true
                } label: {
                    SettingsLabel(icon: "cross.case.fill", title: "Health disclaimers", subtitle: "Review medical, nutrition, and AI estimate guidance.", color: .orange)
                }
                .padding(16)

                Divider().padding(.leading, 50)

                Link(destination: URL(string: "https://PeteAndrews1289.github.io/MyFitPlate/privacy_policy.html")!) {
                    SettingsLabel(icon: "lock.shield.fill", title: "Privacy & data", subtitle: "See how health, nutrition, and AI data are handled.", color: .blue)
                }
                .padding(16)

                Divider().padding(.leading, 50)

                Link(destination: URL(string: "https://PeteAndrews1289.github.io/MyFitPlate/terms_of_service.html")!) {
                    SettingsLabel(icon: "doc.text.fill", title: "Terms of service", subtitle: "Read our terms, conditions, and usage policies.", color: .purple)
                }
                .padding(16)

                Divider().padding(.leading, 50)

                Button {
                    showingResetTourConfirmation = true
                } label: {
                    SettingsLabel(icon: "questionmark.circle.fill", title: "Reset feature tooltips", subtitle: "Replay the guided app tips.", color: .blue)
                }
                .padding(16)
            }
            
            SettingsSectionCard(title: "Account access") {
                Button(role: .destructive) { showingSignOutAlert = true } label: {
                    Text("Sign out")
                        .appFont(size: 17, weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
                
                Divider()
                
                if isDeletingAccount {
                    HStack {
                        Text("Deleting account")
                            .appFont(size: 17, weight: .semibold)
                        Spacer()
                        ProgressView()
                    }
                    .padding(16)
                } else {
                    Button(role: .destructive) { showingDeleteAccountAlert = true } label: {
                        Text("Delete account")
                            .appFont(size: 17, weight: .semibold)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(16)
                }
            }
        }
    }
}
