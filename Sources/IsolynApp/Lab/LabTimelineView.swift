import AppKit
import SwiftUI

/// Every test the lab has ever run, newest first, on one page.
///
/// The ordering principle is that a reader should be able to answer "what did
/// we try, when, and how did it end?" without opening a folder. So each entry
/// carries four things and nothing more: what kind of test it was, its name, the
/// settings in plain words, and the numbers that decide whether it worked.
struct LabTimelineView: View {
    @Environment(LabService.self) private var lab

    @State private var model: LabTimelineModel
    @State private var filter: LabTimelineKind?
    @State private var query = ""

    init(model: LabTimelineModel? = nil) {
        _model = State(initialValue: model ?? LabTimelineModel())
    }

    private var entries: [LabTimelineEntry] { model.entries }
    private var loaded: Bool { model.loaded }

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [LabTimelineEntry]
        var id: Date { day }
    }

    private var visible: [LabTimelineEntry] {
        entries.filter { $0.isKind(filter) && $0.matches(query) }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.date ?? .distantPast) }
        return buckets
            .map { DayGroup(day: $0.key, entries: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            overview

            if !loaded {
                Text("Reading the lab record…")
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .padding(.vertical, 30)
            } else if groups.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        dayHeader(group)
                        ForEach(group.entries) { entry in
                            LabTimelineRow(entry: entry)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .task {
            refresh()
            // The record changes when a run finishes or a headless command
            // writes a bench, so re-read on a slow loop rather than on a
            // notification no other process can send.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                refresh()
            }
        }
    }

    private func refresh() {
        model.load(dataRoot: lab.dataRoot, checkout: LabPaths.checkoutRoot())
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 30) {
                headline("Tests", "\(entries.count)")
                headline("Finished", "\(entries.filter { $0.status == .finished || $0.status == .recorded }.count)")
                headline("Failed", "\(entries.filter { $0.status == .failed }.count)", alarm: entries.contains { $0.status == .failed })
                headline("In flight", "\(entries.filter { $0.status == .running }.count)")
                headline("Dates", spanLabel)
                Spacer(minLength: 0)
            }

            Divider().overlay(IsolynTheme.ebonyLine.opacity(0.6))

            HStack(spacing: 7) {
                chip(title: "All", count: entries.count, kind: nil)
                ForEach(LabTimelineKind.allCases) { kind in
                    let count = entries.filter { $0.kind == kind }.count
                    if count > 0 {
                        chip(title: kind.plural, count: count, kind: kind)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    TextField("Search the log", text: $query)
                        .textFieldStyle(.plain)
                        .font(IsolynTheme.body(12))
                        .frame(width: 150)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(IsolynTheme.ebonyElevated))
            }
        }
        .labCard()
    }

    private func headline(_ title: String, _ value: String, alarm: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(IsolynTheme.caption(9))
                .tracking(1.6)
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Text(value)
                .font(IsolynTheme.display(22))
                .foregroundStyle(alarm ? Color(red: 0.82, green: 0.42, blue: 0.36) : IsolynTheme.ivory)
                .contentTransition(.numericText())
        }
    }

    private func chip(title: String, count: Int, kind: LabTimelineKind?) -> some View {
        let selected = filter == kind
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = kind }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(selected ? IsolynTheme.ebony : IsolynTheme.ivory)
                Text("\(count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(selected ? IsolynTheme.ebony.opacity(0.6) : IsolynTheme.ivoryMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? IsolynTheme.brass : IsolynTheme.ebonyElevated))
            .overlay(
                Capsule().stroke(
                    selected ? Color.clear : IsolynTheme.ebonyLine.opacity(0.5),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var spanLabel: String {
        let dated = entries.compactMap(\.date).sorted()
        guard let earliest = dated.first, let latest = dated.last else { return "—" }
        let calendar = Calendar.current
        if calendar.isDate(earliest, inSameDayAs: latest) {
            return earliest.formatted(.dateTime.day().month(.abbreviated))
        }
        return "\(earliest.formatted(.dateTime.day().month(.abbreviated))) – \(latest.formatted(.dateTime.day().month(.abbreviated)))"
    }

    // MARK: Day header

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack(spacing: 12) {
            Text(dayLabel(group.day))
                .font(IsolynTheme.caption(9))
                .tracking(1.9)
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Rectangle()
                .fill(IsolynTheme.ebonyLine.opacity(0.6))
                .frame(height: 1)
            Text("\(group.entries.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        }
        .padding(.leading, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func dayLabel(_ day: Date) -> String {
        if day == Calendar.current.startOfDay(for: .distantPast) { return "UNDATED" }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        let text = day.formatted(
            sameYear
                ? .dateTime.weekday(.wide).day().month(.wide)
                : .dateTime.weekday(.wide).day().month(.wide).year()
        )
        return text.uppercased()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            PipGlyph(count: 3, color: IsolynTheme.ivoryMuted.opacity(0.6))
                .frame(width: 30, height: 30)
            Text(entries.isEmpty
                 ? "No tests recorded yet. The first run, probe or bench will appear here."
                 : "No test matches this filter.")
                .font(IsolynTheme.body(12))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

// MARK: - One row

/// A dot on the rail and the card beside it. The rail is drawn per row rather
/// than as one long line, so a filtered list never shows a rail running past an
/// entry that is not there.
private struct LabTimelineRow: View {
    let entry: LabTimelineEntry

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rail
            card
        }
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(IsolynTheme.ebonyLine.opacity(0.85))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(IsolynTheme.ebony, lineWidth: 1.5))
                .padding(.top, 18)
        }
        .frame(width: 7)
        .padding(.leading, 7)
        .frame(maxHeight: .infinity)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 11) {
            // The tag is a gutter label, so the title, the sentence and the
            // numbers all start on one edge and the eye can drop straight down.
            tag
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 9) {
                    Text(entry.title)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 10)
                    if let date = entry.date, entry.hasTime {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(IsolynTheme.ivoryMuted)
                    }
                    LabStatusPill(text: entry.status.label, tone: entry.status.tone)
                }

                Text(entry.subtitle)
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    ForEach(entry.facts, id: \.label) { fact in
                        HStack(spacing: 5) {
                            Text(fact.label)
                                .font(IsolynTheme.caption(9))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                            Text(fact.value)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(IsolynTheme.ivory)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? IsolynTheme.ebonyElevated : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hovering ? IsolynTheme.ebonyLine.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .padding(.bottom, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(entry.folder?.path ?? entry.title)
    }

    private var tag: some View {
        Text(entry.kind.tag)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(entry.kind == .cloud ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(IsolynTheme.ebonyElevated))
            .overlay(Capsule().stroke(IsolynTheme.ebonyLine.opacity(0.45), lineWidth: 1))
            .frame(width: 58, alignment: .leading)
    }

    private var dotColor: Color {
        switch entry.status {
        case .failed: return Color(red: 0.72, green: 0.28, blue: 0.24)
        case .running: return IsolynTheme.brass
        case .paused: return IsolynTheme.ebonyLine
        case .finished, .recorded:
            return entry.kind == .cloud ? IsolynTheme.brass : IsolynTheme.ivoryMuted
        }
    }
}
