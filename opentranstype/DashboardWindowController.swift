import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController {
    private let historyStore: TranslationHistoryStore
    private let model: TranslatorModel
    private var window: NSWindow?
    private var resizeObserver: NSObjectProtocol?

    init(historyStore: TranslationHistoryStore, model: TranslatorModel) {
        self.historyStore = historyStore
        self.model = model
    }

    func show() {
        if window == nil {
            let contentView = DashboardView(historyStore: historyStore, model: model)
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 18
            hostingView.layer?.masksToBounds = true

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.title = "OpenTransType"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 520)
            window.center()
            WindowChrome.placeTrafficLightsInsidePanel(window)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    WindowChrome.placeTrafficLightsInsidePanel(window)
                }
            }
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case stats
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stats:
            return "数据统计"
        case .history:
            return "历史记录"
        }
    }

    var iconName: String {
        switch self {
        case .stats:
            return "chart.bar.xaxis"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore
    @ObservedObject var model: TranslatorModel

    @State private var selection: DashboardSection? = .stats

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selection ?? .stats {
            case .stats:
                StatsDashboardView(historyStore: historyStore, model: model)
            case .history:
                HistoryDashboardView(historyStore: historyStore)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .liquidGlassPanel(cornerRadius: 18)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.tint)
                Text("OpenTransType")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.iconName)
                    .tag(section)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 8) {
                Text("目标语言")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.selectedLanguage.name)
                    .font(.callout.weight(.medium))
                Text("历史记录仅保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 210)
    }
}

private struct StatsDashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore
    @ObservedObject var model: TranslatorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("数据统计")
                        .font(.largeTitle.weight(.semibold))
                    Text("查看本机翻译使用情况和当前状态。")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    StatCard(title: "翻译次数", value: "\(historyStore.stats.recordCount)", iconName: "number")
                    StatCard(title: "原文字数", value: "\(historyStore.stats.sourceCharacterCount)", iconName: "character.cursor.ibeam")
                    StatCard(title: "译文字数", value: "\(historyStore.stats.translatedCharacterCount)", iconName: "textformat")
                    StatCard(title: "平均长度", value: "\(historyStore.stats.averageSourceLength)", iconName: "divide")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("当前设置")
                        .font(.title3.weight(.semibold))

                    HStack {
                        Label("默认目标语言", systemImage: "globe")
                        Spacer()
                        Text(model.selectedLanguage.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("监听状态", systemImage: model.isEnabled ? "ear" : "pause.circle")
                        Spacer()
                        Text(model.statusText)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("最近目标语言", systemImage: "clock")
                        Spacer()
                        Text(historyStore.stats.latestTargetLanguage)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HistoryDashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("历史记录")
                        .font(.largeTitle.weight(.semibold))
                    Text("最近的翻译会保存在本机，最多保留 300 条。")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("清空") {
                    historyStore.clear()
                }
                .disabled(historyStore.records.isEmpty)
            }

            if historyStore.records.isEmpty {
                ContentUnavailableView(
                    "还没有历史记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("完成一次翻译后会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(historyStore.records) { record in
                    HistoryRecordRow(record: record)
                        .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
        .padding(28)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let iconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.tint)

            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))

            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .padding(18)
        .liquidGlassPanel(cornerRadius: 10)
    }
}

private struct HistoryRecordRow: View {
    let record: TranslationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.dateFormatter.string(from: record.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.targetLanguageName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(record.sourceText)
                .font(.body.weight(.medium))
                .lineLimit(2)

            Text(record.translatedText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
