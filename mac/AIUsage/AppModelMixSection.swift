import SwiftUI

/// What the Model mix tab's controls do. Each action names the account, so each card's sliders change only that card's
/// settings. The window passes the model's actions. A snapshot passes none.
struct ModelMixActions {
    /// Moves one model's slider to a value. The other sliders follow, so the total stays 100.
    var setPercent: (_ accountID: String, _ id: String, _ value: Int) -> Void = { _, _, _ in }
    /// Drag and drop: the dragged model takes the place of the target.
    var moveOnto: (_ accountID: String, _ id: String, _ target: String) -> Void = { _, _, _ in }
    /// Move up (-1) or down (+1), the keyboard and VoiceOver alternative to dragging.
    var step: (_ accountID: String, _ id: String, _ delta: Int) -> Void = { _, _, _ in }
    /// Reset to actual: the real mix from the logs comes back.
    var reset: (_ accountID: String) -> Void = { _ in }
    /// The end of a slider drag: the shares are saved once for that account, by model id.
    var commitPercent: (_ accountID: String, _ percent: [String: Int]) -> Void = { _, _ in }
}

/// The colours of the model rows, the bars and the dots. Claude families keep their colours. ChatGPT models are coloured
/// by their family too: `sol`, `luna`, `astra` and `terra`. Any other family is grey.
enum ModelMixColor {
    static func color(for family: String) -> Color {
        switch family {
        case "opus": return Color(modelMixRGB: 0xD97757)
        case "sonnet": return Color(modelMixRGB: 0x5B8DEF)
        case "haiku": return Color(modelMixRGB: 0x2BB3A3)
        case "fable": return Color(modelMixRGB: 0x9B72CF)
        // ChatGPT (Codex) families. These four colours are approved (2026-11-20).
        case "sol": return Color(modelMixRGB: 0x10A37F)
        case "luna": return Color(modelMixRGB: 0x6E7BF2)
        case "astra": return Color(modelMixRGB: 0xE0457B)
        case "terra": return Color(modelMixRGB: 0x8C6D46)
        default: return Color.secondary
        }
    }
}

private extension Color {
    init(modelMixRGB value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The Model mix tab of one account card: the badge (actual or trial) and reset, the main model, the month's estimated
/// cost at API rates, a colour bar, one row per model (drag handle, name and prices, slider, share, cost), a note, and the
/// Today and This month tiles, which show the what-if values while the mix is a trial.
///
/// The slider drag lives in this view's own state. While a slider moves, only this view is drawn again, and nothing is
/// saved until the drag ends.
struct AccountModelMixView: View {
    let account: UsageAccount
    let mix: AccountModelMix
    let actions: ModelMixActions
    /// Set only by the snapshot tests. ImageRenderer cannot draw the native slider or a drop target, so the snapshot
    /// draws a look-alike slider and no drop target. The window always uses the native controls.
    var snapshot: Bool = false
    @Environment(\.uiLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The slider drag in progress, if any.
    @State private var drag: ModelMixDrag?
    /// Ends the drag 0.4 s after the last move, when the end of the drag did not arrive (a keyboard move, or a drag cut short).
    @State private var settle: Task<Void, Never>?

    /// The panel on screen: the drag's while a slider moves, otherwise the account's.
    private var shown: ModelMixPanel { drag?.panel ?? mix.shown }

    /// Saves the drag once and ends it. Called when the slider is let go, or by the fallback timer.
    private func endDrag() {
        settle?.cancel()
        settle = nil
        guard let finished = drag else { return }
        drag = nil
        if let percent = finished.savedPercent { actions.commitPercent(mix.accountID, percent) }
    }

    /// Restarts the fallback timer after each move.
    private func scheduleSettle() {
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { endDrag() }
        }
    }

    var body: some View {
        let shown = self.shown
        VStack(alignment: .leading, spacing: 12) {
            header(shown)
            VStack(alignment: .leading, spacing: 4) {
                if let main = shown.mainModelLabel {
                    Text("\(L10n.text(.modelMixMainModel, language)): \(main)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.text(.modelMixTotal, language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(UsageFormat.moneyText(cents: shown.totalCents))
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                }
            }
            ModelMixBar(rows: shown.rows, reduceMotion: reduceMotion)
            VStack(spacing: 2) {
                ForEach(Array(shown.rows.enumerated()), id: \.element.id) { index, row in
                    ModelMixRowView(
                        row: row,
                        index: index,
                        count: shown.rows.count,
                        accountID: mix.accountID,
                        actions: actions,
                        snapshot: snapshot,
                        onMove: { value in
                            if drag == nil { drag = ModelMixDrag(panel: mix.shown) }
                            drag?.move(row: index, to: value)
                            scheduleSettle()
                        },
                        onDragEnd: { endDrag() }
                    )
                }
            }
            Text(L10n.text(.modelMixNote, language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 10) {
                ForEach(AppUsageInsights.usageTiles(account, mix: mix, shownPercents: shown.percents, language: language), id: \.title) { tile in
                    UsageTileView(tile: tile)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ shown: ModelMixPanel) -> some View {
        HStack(spacing: 8) {
            Text(L10n.text(shown.isActual ? .modelMixActual : .modelMixWhatIf, language))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer(minLength: 8)
            Button(L10n.text(.modelMixReset, language)) {
                settle?.cancel()
                settle = nil
                drag = nil
                actions.reset(mix.accountID)
            }
            .controlSize(.small)
            .disabled(shown.isActual)
        }
    }
}

/// The mix as one bar, one colour per model, in the row order.
struct ModelMixBar: View {
    let rows: [ModelMixRow]
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(rows) { row in
                    Rectangle()
                        .fill(ModelMixColor.color(for: row.family))
                        .frame(width: geometry.size.width * CGFloat(row.percent) / 100)
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .animation(LocalMotion.spring(reduced: reduceMotion), value: rows.map(\.percent))
        .accessibilityHidden(true)
    }
}

/// One model row: the drag handle, a colour dot, the name and prices, the slider, the share and the cost.
private struct ModelMixRowView: View {
    let row: ModelMixRow
    let index: Int
    let count: Int
    let accountID: String
    let actions: ModelMixActions
    let snapshot: Bool
    /// A slider moved to a value (the drag in progress). Nothing is saved here.
    let onMove: (Int) -> Void
    /// The slider was let go, so the drag ends and is saved.
    let onDragEnd: () -> Void
    @State private var isDropTarget = false
    @Environment(\.uiLanguage) private var language

    /// The payload of a drag: the account and the model, so a row can only be dropped on the same account's rows.
    private var payload: String { "\(accountID)|\(row.id)" }

    var body: some View {
        let content = HStack(spacing: 10) {
            handle
            Circle()
                .fill(ModelMixColor.color(for: row.family))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(L10n.modelMixPrices(
                    input: UsageFormat.moneyText(row.inputPrice),
                    output: UsageFormat.moneyText(row.outputPrice),
                    language
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 150, alignment: .leading)
            slider
                .frame(width: 110)
            Text("\(row.percent)%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Text(UsageFormat.moneyText(cents: row.cents))
                .font(.system(size: 13))
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isDropTarget ? 0.10 : 0))
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: L10n.text(.modelMixMoveUp, language)) {
            if index > 0 { actions.step(accountID, row.id, -1) }
        }
        .accessibilityAction(named: L10n.text(.modelMixMoveDown, language)) {
            if index < count - 1 { actions.step(accountID, row.id, 1) }
        }
        .contextMenu {
            Button(L10n.text(.modelMixMoveUp, language)) { actions.step(accountID, row.id, -1) }
                .disabled(index == 0)
            Button(L10n.text(.modelMixMoveDown, language)) { actions.step(accountID, row.id, 1) }
                .disabled(index == count - 1)
        }

        if snapshot {
            content
        } else {
            content.dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first, dragged != payload, dragged.hasPrefix(accountID + "|") else { return false }
                actions.moveOnto(accountID, String(dragged.dropFirst(accountID.count + 1)), row.id)
                return true
            } isTargeted: { isDropTarget = $0 }
        }
    }

    @ViewBuilder
    private var handle: some View {
        let icon = Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary)
            .frame(width: 18, height: 26)
            .contentShape(Rectangle())
            .help(L10n.text(.dragToReorder, language))
            .accessibilityLabel(L10n.text(.dragToReorder, language))
        if snapshot {
            icon
        } else {
            icon.draggable(payload)
        }
    }

    @ViewBuilder
    private var slider: some View {
        if snapshot {
            SliderLook(percent: row.percent, color: ModelMixColor.color(for: row.family))
        } else {
            Slider(
                value: Binding(
                    get: { Double(row.percent) },
                    set: { newValue in
                        let value = Int(newValue.rounded())
                        if value != row.percent { onMove(value) }
                    }
                ),
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                    if !editing { onDragEnd() }
                }
            ) {
                Text(L10n.modelMixShare(row.label, language))
            }
            .labelsHidden()
            .accessibilityValue(L10n.modelMixPercent(row.percent, language))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: actions.setPercent(accountID, row.id, min(row.percent + 1, 100))
                case .decrement: actions.setPercent(accountID, row.id, max(row.percent - 1, 0))
                @unknown default: break
                }
            }
        }
    }
}

/// A look-alike of the slider, drawn with shapes. Used only by the snapshot (see `AccountModelMixView.snapshot`).
private struct SliderLook: View {
    let percent: Int
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let x = geometry.size.width * CGFloat(percent) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: 4)
                Capsule()
                    .fill(color)
                    .frame(width: x, height: 4)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .offset(x: min(max(x - 8, 0), geometry.size.width - 16))
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: 20)
    }
}
