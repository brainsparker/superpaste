import SwiftUI

struct TrialAccountView: View {
    @ObservedObject private var account = TrialAccountService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trial account").font(.headline)
            if let email = account.email {
                Label(email, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline).textSelection(.enabled)
                Text(account.trialExpired ? "This account's trial has ended." : "Your 7-day trial starts with your first request. Up to 15 responses per day, across your devices.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sign in with a verified email to start your free 7-day trial. Up to 15 responses per day. No card required.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Button(account.email == nil ? "Sign in for free trial" : "Sign in again") {
                    Task { await account.signIn() }
                }
                .buttonStyle(.borderedProminent).disabled(account.isSigningIn)
                if account.isSigningIn { ProgressView().controlSize(.small) }
                if account.hasSession || account.isSigningIn {
                    Button(account.isSigningIn ? "Cancel" : "Sign out") { account.signOut() }
                }
            }
            if let message = account.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
