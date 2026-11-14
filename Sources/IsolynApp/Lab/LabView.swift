import AppKit
import SwiftUI

/// The offline lab: runs on one tab, calibration analyses on the other.
///
/// The screen is written for someone who has never heard the word "seed". The
/// plain label is the one you read; the technical name is the caption under it,
/// so the same page works for a first-time reader and for an audit.
struct LabView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case runs = "Runs"
        case analyses = "Analyses"
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var tab: Tab = .runs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)

                switch tab {
                case .runs:
                    LabRunsView()
                case .analyses:
                    LabAnalysisView()
                }
            }
            .frame(maxWidth: 740, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKSPACE")
                        .font(IsolynTheme.caption(10))
                        .tracking(2.4)
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Text("Offline Lab")
                        .font(IsolynTheme.display(28))
                        .foregroundStyle(IsolynTheme.ivory)
                }
                Spacer()
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.3)) { appState.screen = .entry }
                }
                .buttonStyle(.plain)
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            Text("Let the computer play itself, thousands or millions of times. Runs save as they go, so stopping or quitting costs minutes — not the run.")
                .font(IsolynTheme.body(13))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Runs tab

struct LabRunsView: View {
    @Environment(LabService.self) private var lab
    @Environment(LabEstimator.self) private var estimator

    @State private var showAdvanced = false
    @State private var search = ""
    @State private var filter: LabRunFilter = .all
    @State private var openRun: LabManifest?

    private struct Preset: Identifiable {
        let title: String
        let games: Int
        var id: Int { games }
    }

    private let presets: [Preset] = [
        Preset(title: "Taste", games: 200),
        Preset(title: "10K", games: 10_000),
        Preset(title: "1M", games: 1_000_000),
        Preset(title: "5M", games: 5_000_000),
    ]

    private var probeKey: String {
        "\(lab.draft.mode)-\(lab.draft.depth)-\(lab.draft.determinizations)-\(lab.draft.parallel)"
    }

    private var visibleRuns: [LabManifest] {
        lab.runs(filter: filter, query: search)
    }

    var body: some View {
        @Bindable var lab = lab

        VStack(alignment: .leading, spacing: 18) {
            nowCard
            startCard(games: $lab.draft.games, advanced: $showAdvanced)
            workloadCard
            library
        }
        .onAppear {
            lab.attachToActiveRun()
            lab.refreshLibrary(force: true)
        }
        .task(id: probeKey) {
            guard !lab.isBusy else { return }
            // Wait out a burst of stepper clicks before paying for a probe.
            try? await Task.sleep(nanoseconds: 800_000_000)
            estimator.measure(lab.draft)
        }
        .task {
            // One cheap directory scan every two seconds, never inside a draw.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                lab.refreshLibrary()
            }
        }
        .sheet(item: $openRun) { run in
            LabRunDetailView(run: run)
        }
    }

    // MARK: What is happening

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(indicatorColor).frame(width: 8, height: 8)
                Text(lab.statusTitle)
                    .font(IsolynTheme.title(17))
                    .foregroundStyle(IsolynTheme.ivory)
                Spacer()
                if let manifest = lab.manifest {
                    Text("\(Int(manifest.fraction * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                        .contentTransition(.numericText())
                }
            }

            if let manifest = lab.manifest {
                ProgressView(value: manifest.fraction)
                    .progressViewStyle(.linear)
                    .tint(IsolynTheme.brass)

                HStack(spacing: 22) {
                    stat("Played", "\(formatted(manifest.doneGames)) of \(formatted(manifest.totalGames))")
                    stat("Batches", "\(manifest.doneShards) of \(manifest.shards.count)")
                    if let rate = manifest.gamesPerSecond() {
                        stat("Speed", "\(Int(rate)) games/s")
                    }
                    if let finish = manifest.estimatedFinish() {
                        stat("Done", finishLabel(finish))
                    }
                    Spacer()
                }

                HStack(spacing: 16) {
                    if lab.isBusy {
                        Button("Pause") { lab.stop() }
                            .buttonStyle(.plain)
                            .font(IsolynTheme.body(13))
                            .foregroundStyle(IsolynTheme.ivory)
                            .keyboardShortcut(".", modifiers: .command)
                    }
                    LabLink(title: "Show folder") { lab.reveal(runID: manifest.runId) }
                    if manifest.isComplete {
                        LabLink(title: "Combine into one file") { lab.merge(runID: manifest.runId) }
                    }
                    Spacer()
                }
            } else if case .failed(let reason) = lab.phase {
                Text(reason)
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivory)
                    .fixedSize(horizontal: false, vertical: true)
                if let tail = lab.logTail {
                    Text(tail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                        .lineLimit(5)
                }
            } else {
                Text("Nothing running. Choose a size below — the lab times a short run first, so you know the cost before you commit.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = lab.message {
                Text(message)
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
        .labCard()
    }

    // MARK: Start

    private func startCard(games: Binding<Int>, advanced: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                LabSectionTitle(text: "How many games")
                Spacer()
                Text("One game is one complete round")
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            games.wrappedValue = preset.games
                        }
                    } label: {
                        Text(preset.title)
                            .font(IsolynTheme.body(13))
                            .foregroundStyle(games.wrappedValue == preset.games ? IsolynTheme.ebony : IsolynTheme.ivory)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    games.wrappedValue == preset.games
                                        ? IsolynTheme.brass
                                        : IsolynTheme.ebonyElevated
                                )
                            )
                            .overlay(
                                Capsule().stroke(
                                    games.wrappedValue == preset.games
                                        ? .clear
                                        : IsolynTheme.ebonyLine.opacity(0.5),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    TextField("Custom", value: games, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 92)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().stroke(
                                presets.contains(where: { $0.games == games.wrappedValue })
                                    ? IsolynTheme.ebonyLine.opacity(0.5)
                                    : IsolynTheme.brass,
                                lineWidth: 1
                            )
                        )
                    Text("games")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                Spacer()
            }

            DisclosureGroup(isExpanded: advanced) {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                        GridRow {
                            field("Look-ahead", caption: "depth") {
                                Stepper(value: Binding(
                                    get: { lab.draft.depth },
                                    set: { lab.draft.depth = $0 }
                                ), in: 2...12) {
                                    Text("\(lab.draft.depth) moves")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(IsolynTheme.ivory)
                                }
                                .fixedSize()
                            }
                            field("Worlds per move", caption: "samples") {
                                Stepper(value: Binding(
                                    get: { lab.draft.determinizations },
                                    set: { lab.draft.determinizations = $0 }
                                ), in: 4...128, step: 4) {
                                    Text("\(lab.draft.determinizations)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(IsolynTheme.ivory)
                                }
                                .fixedSize()
                            }
                            field("Batches at once", caption: "shards") {
                                Stepper(value: Binding(
                                    get: { lab.draft.parallel },
                                    set: { lab.draft.parallel = $0 }
                                ), in: 1...16) {
                                    Text("\(lab.draft.parallel)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(IsolynTheme.ivory)
                                }
                                .fixedSize()
                            }
                        }
                        GridRow {
                            field("Mode", caption: "players") {
                                Picker("", selection: Binding(
                                    get: { lab.draft.mode },
                                    set: { lab.draft.mode = $0 }
                                )) {
                                    Text("1v1").tag("1v1")
                                    Text("1v1v1").tag("1v1v1")
                                    Text("2v2").tag("2v2")
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 150)
                            }
                            field("Deal seed", caption: "same seed, same games") {
                                Stepper(value: Binding(
                                    get: { lab.draft.seed },
                                    set: { lab.draft.seed = $0 }
                                ), in: 1...999_999) {
                                    Text("\(lab.draft.seed)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(IsolynTheme.ivory)
                                }
                                .fixedSize()
                            }
                            field("Run id", caption: "folder name") {
                                Text(lab.draft.runID)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(IsolynTheme.ivoryMuted)
                            }
                        }
                    }

                    Text("Look-ahead: how many moves ahead it plans. Worlds: how many possible hidden hands it considers each move. Batches: how many games run at once. Seed: changes which games are played — the same seed always deals the same games.")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
            } label: {
                Text("Advanced (optional)")
                    .font(IsolynTheme.caption(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            HStack(spacing: 14) {
                Button {
                    lab.start()
                } label: {
                    Text(lab.isBusy ? "Running…" : "Start \(formatted(games.wrappedValue)) games")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 250))
                .disabled(lab.isBusy || !lab.harnessBuilt || games.wrappedValue < 1)
                .keyboardShortcut(.return, modifiers: .command)

                if !lab.harnessBuilt {
                    Text("The engine needs building once: ./tools/selfplay/build.sh")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.brass)
                }
                Spacer()
            }
        }
        .labCard()
    }

    private func field<Content: View>(
        _ title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(IsolynTheme.body(12))
                .foregroundStyle(IsolynTheme.ivory)
            Text(caption)
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            content()
                .padding(.top, 2)
        }
    }

    // MARK: Workload

    private var workloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LabSectionTitle(text: "What this costs on this Mac")
                Spacer()
                if estimator.isMeasuring {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("measuring…")
                            .font(IsolynTheme.caption(11))
                            .foregroundStyle(IsolynTheme.ivoryMuted)
                    }
                }
            }

            if let estimate = estimator.estimate {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(estimate.level.rawValue)
                            .font(IsolynTheme.title(18))
                            .foregroundStyle(levelColor(estimate.level))
                        Text("· \(estimate.durationText)")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundStyle(IsolynTheme.ivory)
                        Spacer()
                        if let finish = finishDate(for: estimate) {
                            Text(finishLabel(finish))
                                .font(IsolynTheme.caption(11))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                        }
                    }
                    gauge(fraction: estimate.gaugeFraction)
                }

                HStack(spacing: 22) {
                    stat("Batches", "\(estimate.shardCount) × 5,000")
                    stat("Disk", "≈ \(estimate.outputText)")
                    stat("Speed", estimate.rateText)
                    Spacer()
                    LabLink(title: "Measure again") { estimator.measure(lab.draft, force: true) }
                }

                Text("Measured by playing \(estimate.probeGames) real games at these exact settings, \(relativeTime(estimate.measuredAt)).")
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else if estimator.isMeasuring {
                Text("Playing a short warm-up at these settings to time this Mac…")
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                Text(estimator.message ?? "Choose a size and the lab will time a short run to estimate the whole job.")
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
        .labCard()
    }

    private func gauge(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IsolynTheme.ebonyLine.opacity(0.35))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                IsolynTheme.brass.opacity(0.45),
                                IsolynTheme.brass.opacity(0.85),
                                Color(red: 0.78, green: 0.38, blue: 0.30),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * fraction))
            }
        }
        .frame(height: 7)
    }

    private func levelColor(_ level: LabWorkloadEstimate.Level) -> Color {
        switch level {
        case .light, .moderate: return IsolynTheme.ivory
        case .heavy: return IsolynTheme.brass
        case .extreme: return Color(red: 0.82, green: 0.40, blue: 0.32)
        }
    }

    private func finishDate(for estimate: LabWorkloadEstimate) -> Date? {
        lab.isBusy ? nil : Date().addingTimeInterval(estimate.duration)
    }

    // MARK: Library

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LabSectionTitle(text: "Runs")
                Text("\(visibleRuns.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                        .font(IsolynTheme.body(12))
                        .frame(width: 120)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(IsolynTheme.ebonyElevated))

                Picker("", selection: $filter) {
                    ForEach(LabRunFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)

                Button {
                    lab.refreshLibrary(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh the run list (⌘R)")
            }

            if visibleRuns.isEmpty {
                VStack(spacing: 8) {
                    PipGlyph(count: 3, color: IsolynTheme.ivoryMuted.opacity(0.6))
                        .frame(width: 30, height: 30)
                    Text(search.isEmpty && filter == .all
                         ? "No runs yet. Your first run will appear here."
                         : "Nothing matches this filter.")
                        .font(IsolynTheme.body(12))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleRuns) { run in
                        LabRunRow(run: run) { openRun = run }
                    }
                }
            }
        }
        .labCard()
    }

    // MARK: Pieces

    private var indicatorColor: Color {
        switch lab.phase {
        case .running, .launching, .finished: return IsolynTheme.brass
        case .failed: return Color(red: 0.72, green: 0.28, blue: 0.24)
        case .stopped, .idle: return IsolynTheme.ebonyLine
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
        }
    }

    private func formatted(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3_600) h ago"
    }

    private func finishLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "~\(time) today" }
        if Calendar.current.isDateInTomorrow(date) { return "~\(time) tomorrow" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - One row

struct LabRunRow: View {
    let run: LabManifest
    let onOpen: () -> Void

    @Environment(LabService.self) private var lab
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivory)
                Text(run.summaryLine)
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            Spacer(minLength: 10)

            ProgressView(value: run.fraction)
                .progressViewStyle(.linear)
                .tint(run.isComplete ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                .frame(width: 110)

            LabStatusPill(text: statusText, tone: statusTone)

            Menu {
                if !run.isComplete {
                    Button("Resume") { lab.start(run.runConfig) }
                        .disabled(lab.isBusy)
                }
                if run.isComplete {
                    Button("Combine into one file") { lab.merge(runID: run.runId) }
                }
                Button("Show in Finder") { lab.reveal(runID: run.runId) }
                Divider()
                Button("Copy run id") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.runId, forType: .string)
                }
                Button("Copy folder path") {
                    let path = LabPaths.runDirectory(dataRoot: lab.dataRoot, runID: run.runId).path
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? IsolynTheme.ebonyElevated : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }

    private var title: String {
        let size = run.totalGames >= 1_000_000
            ? String(format: "%.1fM", Double(run.totalGames) / 1_000_000)
            : NumberFormatter.localizedString(from: NSNumber(value: run.totalGames), number: .decimal)
        return "\(size) games · \(run.config.mode) · seed \(run.config.seed)"
    }

    private var statusText: String {
        if run.isComplete { return "finished" }
        if run.failedShards > 0 { return "needs attention" }
        return "\(run.doneShards)/\(run.shards.count)"
    }

    private var statusTone: LabStatusPill.Tone {
        if run.isComplete { return .finished }
        if run.failedShards > 0 { return .failed }
        return .paused
    }
}

// MARK: - Detail sheet

struct LabRunDetailView: View {
    let run: LabManifest

    @Environment(\.dismiss) private var dismiss
    @Environment(LabService.self) private var lab

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Run details")
                        .font(IsolynTheme.title(18))
                        .foregroundStyle(IsolynTheme.ivory)
                    Text(run.runId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            ProgressView(value: run.fraction)
                .progressViewStyle(.linear)
                .tint(IsolynTheme.brass)

            Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 10) {
                GridRow {
                    detail("Games", "\(run.doneGames) of \(run.totalGames)")
                    detail("Batches", "\(run.doneShards) of \(run.shards.count)")
                    detail("Failed", "\(run.failedShards)")
                }
                GridRow {
                    detail("Search", run.config.mode + " · depth \(run.config.depth)")
                    detail("Samples", "\(run.config.determinizations)")
                    detail("Seed", "\(run.config.seed)")
                }
                GridRow {
                    detail("Started", run.startedDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    detail("Rows", "\(run.rowCount)")
                    detail("Status", run.isComplete ? "finished" : "paused")
                }
            }

            Text(LabPaths.runDirectory(dataRoot: lab.dataRoot, runID: run.runId).path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .textSelection(.enabled)

            HStack(spacing: 14) {
                if !run.isComplete {
                    Button("Resume") { lab.start(run.runConfig) }
                        .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 130))
                        .disabled(lab.isBusy)
                } else {
                    Button("Combine into one file") { lab.merge(runID: run.runId) }
                        .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 180))
                }
                LabLink(title: "Show in Finder") { lab.reveal(runID: run.runId) }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(IsolynTheme.ebony)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
        }
    }
}
