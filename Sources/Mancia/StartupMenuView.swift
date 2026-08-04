import AppKit
import SwiftUI

/// The launch surface: the status menu's commands in a regular window.
struct StartupMenuView: View {
    let provider: LLMProvider
    let onEdit: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void

    @State private var providerStatus: ProviderStatus?
    @State private var accessibilityTrusted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                BrandMark.view(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mancia")
                        .font(.title2.weight(.semibold))
                    Text("Edit text in any app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onEdit) {
                Label("Edit Selection…", systemImage: "text.cursor")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    provider.displayName,
                    detail: providerStatus.map(statusDetail) ?? "Checking…",
                    symbol: providerStatus == .ready ? "checkmark.circle.fill" : "circle.dotted",
                    isReady: providerStatus == .ready)
                statusRow(
                    "Accessibility",
                    detail: accessibilityTrusted ? "Granted" : "Permission needed",
                    symbol: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    isReady: accessibilityTrusted)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Settings…", action: onSettings)
                Button("About Mancia", action: onAbout)
                Spacer()
                Button("Quit Mancia") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
        .frame(width: 420)
        .task {
            accessibilityTrusted = Permissions.isAccessibilityTrusted
            providerStatus = await provider.checkAvailability()
        }
    }

    private func statusRow(
        _ title: String, detail: String, symbol: String, isReady: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(isReady ? .green : .secondary)
                .frame(width: 16)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func statusDetail(_ status: ProviderStatus) -> String {
        switch status {
        case .ready: "Ready"
        case .notFound: "Not found"
        case .error: "Needs attention"
        }
    }
}