import AppKit
import SwiftUI

struct SupportProjectView: View {
    let appVersionText: String

    private let coffeeURLString = "https://paypal.me/adriangarciagdev"
    private let githubURLString = "https://github.com/adriangarciagdev/CloudStatus"

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)

                VStack(spacing: 3) {
                    Text(NSLocalizedString("support.appName", comment: "Support window app name"))
                        .font(.system(size: 22, weight: .semibold))

                    Text(String.localizedStringWithFormat(NSLocalizedString("settings.version", comment: "Settings app version label"), appVersionText))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(NSLocalizedString("support.tagline", comment: "Support window tagline"))
                .font(.system(size: 14, weight: .medium))

            VStack(spacing: 3) {
                Text(NSLocalizedString("support.developedBy", comment: "Developed by label"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(NSLocalizedString("support.developerName", comment: "Support window developer name"))
                    .font(.system(size: 14, weight: .semibold))
            }

            Divider()

            Text(NSLocalizedString("support.message", comment: "Support project message"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(NSLocalizedString("support.coffee", comment: "Support with coffee button")) {
                    openConfiguredURL(coffeeURLString)
                }
                .disabled(coffeeURLString.isEmpty)

                Button(NSLocalizedString("support.github", comment: "GitHub button")) {
                    openConfiguredURL(githubURLString)
                }
                .disabled(githubURLString.isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 22)
        .frame(width: 380, height: 440)
    }

    private func openConfiguredURL(_ urlString: String) {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }
}
