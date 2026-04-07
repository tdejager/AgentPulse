import SwiftUI

struct LogView: View {
    @State private var activeCategories: Set<LogCategory> = Set(LogCategory.allCases)
    @State private var autoScroll = true
    @State private var expandedEntries: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logEntries
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(LogCategory.allCases, id: \.self) { cat in
                Button {
                    if activeCategories.contains(cat) {
                        activeCategories.remove(cat)
                    } else {
                        activeCategories.insert(cat)
                    }
                } label: {
                    Text(cat.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(activeCategories.contains(cat) ? categoryColor(cat).opacity(0.2) : Color.clear)
                        )
                        .overlay(Capsule().stroke(categoryColor(cat), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption2)

            Button("Clear") {
                Task { @MainActor in DiagnosticsLog.shared.clear() }
            }
            .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var filteredEntries: [LogEntry] {
        let entries = DiagnosticsLog.shared.entries
        if activeCategories.count == LogCategory.allCases.count {
            return entries
        }
        return entries.filter { activeCategories.contains($0.category) }
    }

    private var logEntries: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: filteredEntries.count) {
                if autoScroll, let last = filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(formatTime(entry.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(entry.category.rawValue)
                    .font(.system(.caption2, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(categoryColor(entry.category).opacity(0.15)))
                    .foregroundStyle(categoryColor(entry.category))

                Text(entry.message)
                    .font(.caption2)
                    .lineLimit(expandedEntries.contains(entry.id) ? nil : 1)

                Spacer()

                if !entry.metadata.isEmpty {
                    Button {
                        if expandedEntries.contains(entry.id) {
                            expandedEntries.remove(entry.id)
                        } else {
                            expandedEntries.insert(entry.id)
                        }
                    } label: {
                        Image(systemName: expandedEntries.contains(entry.id) ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if expandedEntries.contains(entry.id) && !entry.metadata.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entry.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                            Text(value)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func categoryColor(_ cat: LogCategory) -> Color {
        switch cat {
        case .discovery: .blue
        case .state: .green
        case .hook: .purple
        case .notification: .orange
        case .error: .red
        }
    }
}
