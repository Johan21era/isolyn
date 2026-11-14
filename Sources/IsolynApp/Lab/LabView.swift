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
    @State private var sort: LabRunSort = .newest
    @State private var openRun: LabManifest?
    @State private var deleteCandidate: LabManifest?

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
        lab.runs(filter: filter, query: search, sort: sort)
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
        .alert(
            "Delete this run?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            presenting: deleteCandidate
        ) { run in
            Button("Delete run", role: .destructive) {
                lab.delete(runID: run.runId)
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: { run in
            Text("This permanently removes \(run.runId), including its shard CSVs and logs. This cannot be undone.")
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
                    stat("Played", "\(formatted(manifest.playedGames)) of \(formatted(manifest.totalGames))")
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
                        Button(lab.isMerging ? "Stop merge" : "Pause") { lab.stop() }
                            .buttonStyle(.plain)
                            .font(IsolynTheme.body(13))
                            .foregroundStyle(IsolynTheme.ivory)
                            .keyboardShortcut(".", modifiers: .command)
                    }
                    LabLink(title: "Show folder") { lab.reveal(runID: manifest.runId) }
                    LabLink(title: "Open log") { lab.openLog(runID: manifest.runId) }
                    if manifest.isComplete {
                        if lab.isMerging, lab.mergingRunID == manifest.runId {
                            Text("Combining…")
                                .font(IsolynTheme.caption(12))
                                .foregroundStyle(IsolynTheme.brass)
                        } else {
                            LabLink(title: "Combine into one file") { lab.merge(runID: manifest.runId) }
                        }
                    }
                    Spacer()
                }

                if !manifest.failedShardReasons.isEmpty {
                    Text(manifest.failedShardReasons.prefix(2).map { "Shard \($0.index): \($0.reason)" }.joined(separator: " · "))
                        .font(IsolynTheme.caption(10))
                        .foregroundStyle(IsolynTheme.brass)
                        .lineLimit(2)
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

                Menu {
                    ForEach(LabRunSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            Text(option == sort ? "✓ \(option.rawValue)" : option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("Sort runs")

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
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        column("Started", 74, .leading)
                        column("Games", 58, .trailing)
                        column("Mode", 40, .leading)
                        column("Depth", 38, .trailing)
                        column("Worlds", 46, .trailing)
                        column("Seed", 46, .trailing)
                        column("Progress", 84, .leading)
                        column("Status", 92, .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                    Divider().overlay(IsolynTheme.ebonyLine.opacity(0.6))

                    ForEach(visibleRuns) { run in
                        LabRunRow(run: run, onOpen: { openRun = run }, onDelete: { deleteCandidate = run })
                    }
                }

                Text("Depth = moves it plans ahead · Worlds = possibilities it weighs per move · Seed = which games get dealt")
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .padding(.top, 4)
            }
        }
        .labCard()
    }

    private func column(_ title: String, _ width: CGFloat, _ align: Alignment) -> some View {
        Text(title)
            .font(IsolynTheme.caption(9))
            .tracking(0.6)
            .foregroundStyle(IsolynTheme.ivoryMuted)
            .frame(width: width, alignment: align)
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
    let onDelete: () -> Void

    @Environment(LabService.self) private var lab
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(startedText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .frame(width: 74, alignment: .leading)

            Text(gamesText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
                .frame(width: 58, alignment: .trailing)

            Text(run.config.mode)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
                .frame(width: 40, alignment: .leading)

            Text("\(run.config.depth)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
                .frame(width: 38, alignment: .trailing)

            Text("\(run.config.determinizations)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
                .frame(width: 46, alignment: .trailing)

            Text("\(run.config.seed)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .frame(width: 46, alignment: .trailing)

            ProgressView(value: run.fraction)
                .progressViewStyle(.linear)
                .tint(run.isComplete ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                .frame(width: 84)

            LabStatusPill(text: statusText, tone: statusTone)
                .frame(width: 92, alignment: .leading)

            Spacer(minLength: 0)

            Menu {
                if !run.isComplete {
                    Button("Resume") { lab.start(run.runConfig) }
                        .disabled(lab.isBusy)
                }
                if run.isComplete {
                    Button("Combine into one file") { lab.merge(runID: run.runId) }
                }
                Button("Open runner log") { lab.openLog(runID: run.runId) }
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
                Divider()
                Button("Delete run…", role: .destructive, action: onDelete)
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

    /// "14 Nov", or "14 Nov 2025" once the year differs from today's, so a list
    /// opened months later still reads correctly.
    private var startedText: String {
        guard let date = run.startedDate else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.component(.year, from: date) != calendar.component(.year, from: Date()) {
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var gamesText: String {
        switch run.totalGames {
        case 1_000_000...:
            return String(format: "%.1fM", Double(run.totalGames) / 1_000_000)
        case 1_000...:
            return "\(run.totalGames / 1_000)K"
        default:
            return "\(run.totalGames)"
        }
    }

    private var statusText: String {
        if lab.isMerging, lab.mergingRunID == run.runId { return "combining" }
        if run.isComplete { return "finished" }
        if run.failedShards > 0 { return "failed" }
        if lab.isBusy, lab.manifest?.runId == run.runId { return "running" }
        return "paused"
    }

    private var statusTone: LabStatusPill.Tone {
        if lab.isMerging, lab.mergingRunID == run.runId { return .active }
        if run.isComplete { return .finished }
        if run.failedShards > 0 { return .failed }
        if lab.isBusy, lab.manifest?.runId == run.runId { return .active }
        return .paused
    }
}

// MARK: - Detail sheet

struct LabRunDetailView: View {
    let run: LabManifest

    @Environment(\.dismiss) private var dismiss
    @Environment(LabService.self) private var lab
    @State private var confirmDelete = false

    /// The sheet is opened with a snapshot, but a running shard publishes new
    /// progress while the sheet is open. Prefer the live manifest when it is
    /// the same run.
    private var current: LabManifest {
        lab.manifest?.runId == run.runId ? (lab.manifest ?? run) : run
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Run details")
                        .font(IsolynTheme.title(18))
                        .foregroundStyle(IsolynTheme.ivory)
                    Text(current.runId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Text("\(current.totalGames.formatted()) games of \(current.config.mode), planning \(current.config.depth) moves ahead, weighing \(current.config.determinizations) possible hands per move, dealt from seed \(current.config.seed)")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            ProgressView(value: current.fraction)
                .progressViewStyle(.linear)
                .tint(IsolynTheme.brass)

            Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 10) {
                GridRow {
                    detail("Played", "\(current.playedGames) of \(current.totalGames)")
                    detail("Finished batches", "\(current.doneShards) of \(current.shards.count)")
                    detail("Failed", "\(current.failedShards)")
                }
                GridRow {
                    detail("Search", current.config.mode + " · depth \(current.config.depth)")
                    detail("Samples", "\(current.config.determinizations)")
                    detail("Seed", "\(current.config.seed)")
                }
                GridRow {
                    detail("Started", current.startedDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    detail("Rows", "\(current.rowCount)")
                    detail("Status", current.isComplete ? "finished" : (lab.isBusy && lab.manifest?.runId == current.runId ? "running" : "paused"))
                }
            }

            if !current.failedShardReasons.isEmpty {
                let failures = Array(current.failedShardReasons.prefix(4))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(failures.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text("Shard \(failures[index].index): \(failures[index].reason)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(IsolynTheme.brass)
                                .textSelection(.enabled)
                            LabLink(title: "Open") {
                                lab.openShardLog(runID: current.runId, index: failures[index].index)
                            }
                        }
                    }
                }
            }

            Text(LabPaths.runDirectory(dataRoot: lab.dataRoot, runID: current.runId).path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .textSelection(.enabled)

            HStack(spacing: 14) {
                if !current.isComplete {
                    Button("Resume") { lab.start(current.runConfig) }
                        .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 130))
                        .disabled(lab.isBusy)
                } else {
                    Button(lab.isMerging && lab.mergingRunID == current.runId ? "Combining…" : "Combine into one file") {
                        lab.merge(runID: current.runId)
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 180))
                    .disabled(lab.isBusy)
                }
                LabLink(title: "Open log") { lab.openLog(runID: current.runId) }
                LabLink(title: "Show in Finder") { lab.reveal(runID: current.runId) }
                Spacer()
                Button("Delete…", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.plain)
                    .font(IsolynTheme.caption(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .disabled(lab.isBusy)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(IsolynTheme.ebony)
        .alert("Delete this run?", isPresented: $confirmDelete) {
            Button("Delete run", role: .destructive) {
                lab.delete(runID: current.runId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(current.runId), including its shard CSVs and logs. This cannot be undone.")
        }
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
