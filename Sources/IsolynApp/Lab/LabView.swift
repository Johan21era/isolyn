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
            VStack(alignment: .leading, spacing: 22) {
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
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OFFLINE LAB")
                    .font(IsolynTheme.display(28))
                    .tracking(4)
                    .foregroundStyle(IsolynTheme.ivory)
                Spacer()
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.3)) { appState.screen = .entry }
                }
                .buttonStyle(.plain)
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            Text("Let the computer play itself, thousands or millions of times. Runs are saved as they go, so stopping or quitting costs minutes — not the run.")
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

    var body: some View {
        @Bindable var lab = lab

        VStack(alignment: .leading, spacing: 20) {
            nowCard
            startCard(games: $lab.draft.games, advanced: $showAdvanced)
            workloadCard
            recentRuns
            footnote
        }
        .onAppear { lab.attachToActiveRun() }
        .task(id: probeKey) {
            guard !lab.isBusy else { return }
            // Wait out a burst of stepper clicks before paying for a probe.
            try? await Task.sleep(nanoseconds: 800_000_000)
            estimator.measure(lab.draft)
        }
    }

    // MARK: What is happening

    @ViewBuilder
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
                }
            }

            if let manifest = lab.manifest {
                ProgressView(value: manifest.fraction)
                    .progressViewStyle(.linear)
                    .tint(IsolynTheme.brass)

                HStack(spacing: 26) {
                    stat("Played", "\(formatted(manifest.doneGames)) of \(formatted(manifest.totalGames))")
                    stat("Batches", "\(manifest.doneShards) of \(manifest.shards.count)")
                    if let rate = manifest.gamesPerSecond() {
                        stat("Speed", "\(Int(rate)) games/s")
                    }
                    if let remaining = manifest.estimatedRemaining() {
                        stat("Left", duration(remaining))
                    }
                    if manifest.failedShards > 0 {
                        stat("Retries", "\(manifest.failedShards)")
                    }
                    Spacer()
                }

                HStack(spacing: 18) {
                    if lab.isBusy {
                        Button("Stop") { lab.stop() }
                            .buttonStyle(.plain)
                            .font(IsolynTheme.body(13))
                            .foregroundStyle(IsolynTheme.ivory)
                    }
                    actionLink("Show folder") { lab.reveal(runID: manifest.runId) }
                    if manifest.isComplete {
                        actionLink("Combine into one file") { lab.merge(runID: manifest.runId) }
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
                Text("Nothing running. Choose a size below and start — the lab will tell you how long it will take on this Mac before you commit.")
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(IsolynTheme.ebonyElevated))
    }

    // MARK: Start

    private func startCard(games: Binding<Int>, advanced: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("HOW MANY GAMES")
                    .font(IsolynTheme.caption(11))
                    .tracking(2)
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                Spacer()
                Text("One game is one complete round.")
                    .font(IsolynTheme.caption(11))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button {
                        games.wrappedValue = preset.games
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
                                    ? IsolynTheme.ebonyLine
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
                    Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 14) {
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
                        }
                        GridRow {
                            field("Deal seed", caption: "seed") {
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

                if !lab.harnessBuilt {
                    Text("The engine needs building once: ./tools/selfplay/build.sh")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.brass)
                }
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).stroke(IsolynTheme.ebonyLine, lineWidth: 1))
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

    @ViewBuilder
    private var workloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WHAT THIS COSTS ON THIS MAC")
                    .font(IsolynTheme.caption(11))
                    .tracking(2)
                    .foregroundStyle(IsolynTheme.ivoryMuted)
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
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(estimate.level.rawValue)
                            .font(IsolynTheme.title(18))
                            .foregroundStyle(levelColor(estimate.level))
                        Spacer()
                        Text(estimate.durationText)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(IsolynTheme.ivory)
                    }
                    gauge(fraction: estimate.gaugeFraction)
                }

                HStack(spacing: 26) {
                    stat("Batches", "\(estimate.shardCount) × 5,000 games")
                    stat("Disk", "≈ \(estimate.outputText)")
                    stat("Speed", estimate.rateText)
                    Spacer()
                    actionLink("Measure again") { estimator.measure(lab.draft, force: true) }
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(IsolynTheme.ebonyElevated))
    }

    private func gauge(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IsolynTheme.ebonyLine.opacity(0.6))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [IsolynTheme.brass.opacity(0.55), IsolynTheme.brass, Color(red: 0.72, green: 0.28, blue: 0.24)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
    }

    private func levelColor(_ level: LabWorkloadEstimate.Level) -> Color {
        switch level {
        case .light, .moderate: return IsolynTheme.ivory
        case .heavy: return IsolynTheme.brass
        case .extreme: return Color(red: 0.72, green: 0.28, blue: 0.24)
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT RUNS")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            let runs = lab.recentRuns(limit: 6)
            if runs.isEmpty {
                Text("Nothing yet. Your first run will appear here.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                ForEach(runs, id: \.runId) { run in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friendlyTitle(run))
                                .font(IsolynTheme.body(13))
                                .foregroundStyle(IsolynTheme.ivory)
                            Text("\(formatted(run.doneGames)) of \(formatted(run.totalGames)) games · \(run.config.mode) · \(run.config.depth) moves · \(run.config.determinizations) worlds")
                                .font(IsolynTheme.caption(10))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                        }
                        Spacer()
                        Text(run.isComplete ? "finished" : "paused")
                            .font(IsolynTheme.caption(11))
                            .foregroundStyle(run.isComplete ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                        if !run.isComplete {
                            actionLink("Resume") { lab.start(run.runConfig) }
                                .disabled(lab.isBusy)
                        } else {
                            actionLink("Combine") { lab.merge(runID: run.runId) }
                        }
                        actionLink("Show") { lab.reveal(runID: run.runId) }
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(IsolynTheme.ebonyLine)
                }
            }
        }
    }

    private func friendlyTitle(_ run: LabManifest) -> String {
        let size = run.totalGames >= 1_000_000
            ? String(format: "%.1fM", Double(run.totalGames) / 1_000_000)
            : formatted(run.totalGames)
        return "\(size) games · \(run.config.mode) · seed \(run.config.seed)"
    }

    private var footnote: some View {
        Text("One run at a time. Pressing Start twice cannot launch two runs — the app refuses the second, and the runner's own lock refuses it again.")
            .font(IsolynTheme.caption(11))
            .foregroundStyle(IsolynTheme.ivoryMuted)
            .fixedSize(horizontal: false, vertical: true)
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

    private func actionLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(IsolynTheme.caption(12))
                .foregroundStyle(IsolynTheme.brass)
        }
        .buttonStyle(.plain)
    }

    private func formatted(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "\(max(1, totalMinutes))m"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3_600) h ago"
    }
}
