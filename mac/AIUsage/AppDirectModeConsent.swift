import SwiftUI

/// The consent screen for direct mode, shown in a sheet from a ChatGPT or agy row. It says what the mode reads, where it
/// sends it and that no copy is kept, and it warns that the channel is unofficial. "Turn on" stays disabled until the box
/// is ticked. Cancel changes nothing, and nothing is remembered. Turning the mode off is not here: the row does that.
struct DirectModeConsentView: View {
    /// Called with the provider once "Turn on" is pressed after the box is ticked.
    let onTurnOn: (String) -> Void
    /// Set only by the snapshot tests. ImageRenderer cannot draw the native checkbox, so a look-alike is drawn instead.
    let snapshot: Bool
    @State private var consent: DirectModeConsent
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    init(
        provider: String,
        startsConsented: Bool = false,
        snapshot: Bool = false,
        onTurnOn: @escaping (String) -> Void
    ) {
        var state = DirectModeConsent(provider: provider)
        state.consented = startsConsented
        _consent = State(initialValue: state)
        self.snapshot = snapshot
        self.onTurnOn = onTurnOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.directConsentTitle(service: ProviderStyle.fallbackLabel(for: consent.provider), language))
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                fact(L10n.text(.directConsentReads, language), L10n.text(.directConsentReadsValue, language))
                fact(L10n.text(.directConsentSends, language), L10n.text(.directConsentSendsValue, language))
                fact(L10n.text(.directConsentCopy, language), L10n.text(.directConsentCopyValue, language))
            }
            warning
            checkbox
            HStack(spacing: 8) {
                Spacer(minLength: 8)
                Button(L10n.text(.directConsentCancel, language)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.text(.directConsentTurnOn, language)) {
                    if let provider = consent.confirm() {
                        onTurnOn(provider)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!consent.canTurnOn)
            }
        }
        .padding(20)
        .frame(width: 440, alignment: .leading)
    }

    /// One line of the screen: a short label, then the fact.
    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The yellow warning. It uses the low-limit yellow of the widgets, darker in light mode so it reads on white.
    private var warning: some View {
        let yellow = Color(hex: colorScheme == .dark ? ProviderStyle.lowHex : ProviderStyle.lowLightHex)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(yellow)
            Text(L10n.text(.directConsentWarning, language))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(yellow.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(yellow.opacity(0.55), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private var checkbox: some View {
        let label = Text(L10n.text(.directConsentCheckbox, language))
            .font(.system(size: 13))
        if snapshot {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CheckLook(isOn: consent.consented)
                label
            }
        } else {
            Toggle(isOn: $consent.consented) {
                label
            }
            .toggleStyle(.checkbox)
        }
    }
}

/// A look-alike of the native checkbox, drawn with shapes. Used only by the snapshot (see `DirectModeConsentView.snapshot`).
private struct CheckLook: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isOn ? LocalPalette.accent : Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isOn ? LocalPalette.accent : Color.primary.opacity(0.35), lineWidth: 1)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 15, height: 15)
            .padding(.top, 1)
    }
}
