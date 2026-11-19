import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let result: UsageLoadResult
    /// The language the widget draws in: the app's choice, with `system` resolved on this Mac.
    let language: UILanguage
}

/// Sample data for the gallery placeholder. It is the contract example, bundled as a resource.
enum SampleUsage {
    static func result() -> UsageLoadResult {
        guard let url = Bundle.main.url(forResource: "usage.sample", withExtension: "json") else {
            return .missing
        }
        return UsageLoader.load(from: url)
    }
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), result: SampleUsage.result(), language: currentLanguage())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(
            context.isPreview
                ? UsageEntry(date: Date(), result: SampleUsage.result(), language: currentLanguage())
                : currentEntry()
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = currentEntry()
        // The collector runs every 300 s, so ask WidgetKit for a new timeline every 5 minutes.
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(300))))
    }

    private func currentEntry() -> UsageEntry {
        UsageEntry(
            date: Date(),
            result: UsageLoader.load(from: UsageLoader.defaultFileURL()),
            language: currentLanguage()
        )
    }

    /// The app's choice from settings.json, resolved with the device language. A missing file means "system".
    private func currentLanguage() -> UILanguage {
        UILanguage.current(for: AppSettingsStore.load(from: AppSettingsStore.defaultFileURL()))
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageScreenView(size: UsageSize(family), result: entry.result, now: entry.date)
            .environment(\.uiLanguage, entry.language)
            .invalidatableContent()
            .containerBackground(.background, for: .widget)
    }
}

extension UsageSize {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        default: self = .large
        }
    }
}

struct AIUsageWidget: Widget {
    let kind = "local.aiusage.usage"

    /// The gallery text follows the system language, because the gallery is shown before any choice is read.
    private static let gallery = UILanguage.current(for: .system)

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.text(.widgetName, Self.gallery))
        .description(L10n.text(.widgetDescription, Self.gallery))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AIUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUsageWidget()
    }
}
