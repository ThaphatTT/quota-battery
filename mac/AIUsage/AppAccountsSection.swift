import SwiftUI

/// What the Accounts section shows: the rows in display order, the sort, the last notice, and whether a refresh runs.
struct AccountsPanelState: Equatable {
    var rows: [AccountListRow]
    var sort: AccountSort
    var notice: AccountNotice?
    var isRefreshing: Bool
    /// The direct mode switches. Only the ChatGPT and agy rows show the control.
    var directMode: DirectModeSettings = .off
    /// False until the first usage.json read has finished: the rows are a skeleton until then.
    var isLoaded: Bool = true
}

/// What the section's controls do. The window passes the model's actions. A snapshot passes none.
struct AccountActions {
    /// Rescan: runs the collector, which finds new logins and writes known-accounts.json.
    var rescan: () -> Void = {}
    /// Add account for "claude" or "codex": opens Terminal with that provider's login command.
    var add: (String) -> Void = { _ in }
    /// Sets a nickname. An empty name removes it.
    var rename: (_ id: String, _ name: String) -> Void = { _, _ in }
    var setEnabled: (_ id: String, _ enabled: Bool) -> Void = { _, _ in }
    /// Drag and drop: the first account takes the place of the second.
    var move: (_ id: String, _ onto: String) -> Void = { _, _ in }
    var setSort: (AccountSort) -> Void = { _ in }
    /// Turns direct mode on (after the consent screen) or off, for ChatGPT or agy. A Claude row never calls it.
    var setDirectMode: (_ provider: String, _ enabled: Bool) -> Void = { _, _ in }
}

/// What the last "Add account" did: Terminal was opened, or it refused to open.
enum AccountNotice: Equatable {
    case terminalOpened(provider: String)
    case terminalFailed

    func text(_ language: UILanguage) -> String {
        switch self {
        case .terminalOpened(let provider):
            return L10n.text(provider == "codex" ? .accountOpenedCodex : .accountOpenedClaude, language)
        case .terminalFailed:
            return L10n.text(.accountTerminalFailed, language)
        }
    }
}

/// The Accounts section of the app window, below the account cards. It lists every account the collector found, shown
/// or hidden. Drag the handle to reorder (manual sort only), tap a name to rename it, and use the switch to show or hide
/// it. Rescan and Add account are at the top, and the sort control is under the list.
struct AppAccountsSection: View {
    let state: AccountsPanelState
    let actions: AccountActions
    /// Set only by the snapshot tests. ImageRenderer cannot draw the native switch, the segmented control or a drop
    /// target (it draws a "not allowed" placeholder), so the snapshot draws look-alikes in their place. The window
    /// always uses the native controls.
    /// True while the Accounts tab is the one on screen. The first showing plays the first-open motion, and only then.
    var isShowing: Bool = true
    var snapshot: Bool = false
    @Environment(\.uiLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The rows have been shown (a snapshot starts shown).
    @State private var revealed = false
    /// How the rows enter. Nil until decided: `slide` on the section's first showing in the app session, `none` after.
    @State private var intro: IntroStyle?

    private var motion: MotionLevel { MotionLevel.resolve(reduceMotion: reduceMotion, snapshot: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !state.isLoaded {
                SkeletonLoadingView(label: L10n.text(.loading, language), motion: motion) {
                    VStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { _ in
                            SkeletonAccountRow()
                        }
                    }
                }
            } else if state.rows.isEmpty {
                Text(L10n.text(.noAccounts, language))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                        AccountRowView(
                            row: row,
                            canReorder: state.sort == .manual,
                            actions: actions,
                            snapshot: snapshot
                        )
                        .modifier(FirstOpenReveal(shown: revealed || snapshot, style: intro ?? .none, index: index))
                    }
                }
            }
            sortControl
            if let notice = state.notice {
                Text(notice.text(language))
                    .font(.system(size: 11))
                    .foregroundStyle(notice == .terminalFailed ? LocalPalette.warning : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .environment(\.motionLevel, motion)
        .onAppear { decideIntro() }
        .onChange(of: state.isLoaded) { _, _ in decideIntro() }
        .onChange(of: isShowing) { _, _ in decideIntro() }
    }

    /// Shows the rows once the first read has finished and the tab is on screen. Only the first showing in the app session
    /// plays the motion.
    private func decideIntro() {
        guard state.isLoaded, isShowing, intro == nil else { return }
        if snapshot {
            intro = IntroStyle.none
        } else {
            intro = IntroStyle.resolve(isFirst: FirstOpenTracker.shared.claim("settings.accounts"), reduceMotion: reduceMotion, snapshot: false)
        }
        revealed = true
    }

    private var header: some View {
        HStack(spacing: 8) {
            typedText(L10n.text(.accountsTitle, language), key: "settings.accounts.title", motion: motion)
                .font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 8)
            Button(action: actions.rescan) {
                Label(L10n.text(.rescan, language), systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .disabled(state.isRefreshing)
            addMenu
        }
    }

    /// Claude and Codex each open Terminal with their own login command. agy stays disabled: it has one account only.
    private var addMenu: some View {
        Menu {
            Button(L10n.text(.addClaudeAccount, language)) { actions.add("claude") }
            Button(L10n.text(.addCodexAccount, language)) { actions.add("codex") }
            Divider()
            Button(L10n.text(.agyOneAccount, language)) {}
                .disabled(true)
        } label: {
            Label(L10n.text(.addAccount, language), systemImage: "plus")
                .font(.system(size: 12))
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }

    @ViewBuilder
    private var sortControl: some View {
        if snapshot {
            SegmentedLook(
                selection: state.sort,
                options: [
                    (.manual, L10n.text(.sortManual, language)),
                    (.lowest, L10n.text(.sortLowest, language)),
                    (.provider, L10n.text(.sortProvider, language)),
                ]
            )
        } else {
            Picker(L10n.text(.sortLabel, language), selection: Binding(get: { state.sort }, set: actions.setSort)) {
                Text(L10n.text(.sortManual, language)).tag(AccountSort.manual)
                Text(L10n.text(.sortLowest, language)).tag(AccountSort.lowest)
                Text(L10n.text(.sortProvider, language)).tag(AccountSort.provider)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// One account in the section: the drag handle, the brand icon, the name (tap to rename) with the New tag, the source
/// and the plan, and the show and hide switch. A hidden account is dimmed. The direct mode control is in the Direct mode pane.
private struct AccountRowView: View {
    let row: AccountListRow
    let canReorder: Bool
    let actions: AccountActions
    let snapshot: Bool
    @Environment(\.uiLanguage) private var language
    @State private var editing = false
    @State private var draft = ""
    @State private var isDropTarget = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let content = HStack(spacing: 10) {
            handle
            LocalBrandIcon(
                letter: ProviderStyle.iconLetter(for: row.provider),
                color: LocalPalette.brand(for: row.provider),
                size: 24
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    nameControl
                    if row.isNew {
                        NewTag()
                    }
                }
                HStack(spacing: 6) {
                    Text(row.source)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let plan = row.plan {
                        PlanTag(text: plan)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switchControl
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isDropTarget ? 0.10 : 0))
        )
        .opacity(row.enabled ? 1 : 0.55)

        if snapshot {
            content
        } else {
            content.dropDestination(for: String.self) { items, _ in
                guard canReorder, let dragged = items.first, dragged != row.id else { return false }
                actions.move(dragged, row.id)
                return true
            } isTargeted: { isDropTarget = $0 }
        }
    }

    @ViewBuilder
    private var switchControl: some View {
        if snapshot {
            SwitchLook(isOn: row.enabled)
        } else {
            Toggle(isOn: Binding(get: { row.enabled }, set: { actions.setEnabled(row.id, $0) })) {
                Text(L10n.text(.showAccount, language))
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    /// Dragging works in manual order only. In the other sorts the handle is dimmed, and the sort control says why.
    @ViewBuilder
    private var handle: some View {
        let icon = Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary)
            .frame(width: 18, height: 26)
            .contentShape(Rectangle())
            .help(L10n.text(.dragToReorder, language))
            .accessibilityLabel(L10n.text(.dragToReorder, language))
        if canReorder {
            icon.draggable(row.id)
        } else {
            icon.opacity(0.3)
        }
    }

    @ViewBuilder
    private var nameControl: some View {
        if editing {
            TextField(L10n.text(.renameAccount, language), text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: 200)
                .focused($fieldFocused)
                .onAppear { fieldFocused = true }
                .onSubmit { commit() }
                .onExitCommand { editing = false }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused {
                        commit()
                    }
                }
        } else {
            Button {
                draft = row.nickname ?? row.name
                editing = true
            } label: {
                Text(row.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(L10n.text(.renameHint, language))
        }
    }

    /// Ends the edit and sends the new name once. Escape ends it without sending.
    private func commit() {
        guard editing else { return }
        editing = false
        actions.rename(row.id, draft)
    }
}

/// The green "ใหม่ / New" tag on an account that was found just now.
private struct NewTag: View {
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Text(L10n.text(.newTag, language))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(LocalPalette.healthy)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LocalPalette.healthy.opacity(0.16)))
            .overlay(Capsule().stroke(LocalPalette.healthy.opacity(0.45), lineWidth: 0.5))
    }
}

/// A look-alike of the native switch, drawn with shapes. Used only by the snapshot (see `AppAccountsSection.snapshot`).
struct SwitchLook: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? LocalPalette.healthy : Color.primary.opacity(0.18))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .frame(width: 18, height: 18)
                .padding(2)
        }
        .frame(width: 38, height: 22)
    }
}

/// A look-alike of the segmented control, drawn with shapes. Used only by the snapshots (see `AppAccountsSection.snapshot`
/// and `AppAccountCardView.snapshot`).
struct SegmentedLook<Value: Hashable>: View {
    let selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.1)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(option.0 == selection ? Color.primary.opacity(0.16) : Color.clear)
                    )
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }
}
