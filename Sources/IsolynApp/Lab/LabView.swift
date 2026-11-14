import AppKit
import SwiftUI

/// The offline lab: runs on one tab, calibration analyses on the other.
///
/// The screen is intentionally split between plain-language labels and
/// monospaced technical detail (run ids, shard counts, search configuration), so
/// the same page can be read at a glance or audited line by line.
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
            VStack(alignment: .leading, spacing: 24) {
                header
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)

                switch tab {
                case .runs:
                    LabRunsView()
                case .analyses:
                    LabAnalysisView()
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OFFLINE LAB")
                    .font(IsolynTheme.display(30))
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

            Text("Self-play at volume. Runs are split into shards, so stopping or crashing costs minutes, and the same command — or the same button — picks up where it left off.")
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Runs tab

struct LabRunsView: View {
    @Environment(LabService.self) private var lab
    @State private var showAdvanced = false

    private struct Preset: Identifiable {
        let title: String
        let games: Int
        var id: Int { games }
    }

    private let presets: [Preset] = [
        Preset(title: "Smoke", games: 200),
        Preset(title: "10K", games: 10_000),
        Preset(title: "1M", games: 1_000_000),
        Preset(title: "5M", games: 5_000_000),
    ]

    var body: some View {
        @Bindable var lab = lab

        VStack(alignment: .leading, spacing: 24) {
            statusCard
            startCard(draft: $lab.draft, advanced: $showAdvanced)
            recentRuns
            footnote
        }
        .onAppear { lab.attachToActiveRun() }
    }

    // MARK: Current run

    @ViewBuilder
    private var statusCard: some View {
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

                HStack(spacing: 28) {
                    stat("Games", "\(formatted(manifest.doneGames)) / \(formatted(manifest.totalGames))")
                    stat("Shards", "\(manifest.doneShards) / \(manifest.shards.count)")
                    if let rate = manifest.gamesPerSecond() {
                        stat("Rate", "\(Int(rate)) games/s")
                    }
                    if let remaining = manifest.estimatedRemaining() {
                        stat("Remaining", duration(remaining))
                    }
                    if manifest.failedShards > 0 {
                        stat("Failed", "\(manifest.failedShards)")
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
                    actionLink("Reveal folder") { lab.reveal(runID: manifest.runId) }
                    if manifest.isComplete {
                        actionLink("Merge to CSV") { lab.merge(runID: manifest.runId) }
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
                        .lineLimit(6)
                }
            } else {
                Text("Nothing running. A 5M run at depth 8 takes roughly 60 hours at the measured rate; it survives closing this app.")
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(IsolynTheme.ebonyElevated))
    }

    // MARK: Start

    private func startCard(draft: Binding<LabRunConfig>, advanced: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("START A RUN")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            HStack(spacing: 10) {
                ForEach(presets) { preset in
                    Button {
                        lab.draft.games = preset.games
                    } label: {
                        VStack(spacing: 2) {
                            Text(preset.title)
                                .font(IsolynTheme.body(13))
                            Text(estimate(preset.games))
                                .font(IsolynTheme.caption(10))
                                .opacity(0.75)
                        }
                        .foregroundStyle(draft.wrappedValue.games == preset.games ? IsolynTheme.ebony : IsolynTheme.ivory)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                draft.wrappedValue.games == preset.games
                                    ? IsolynTheme.brass
                                    : IsolynTheme.ebonyElevated
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("\(formatted(preset.games)) games")
                }
                Spacer()
                Text("\(formatted(draft.wrappedValue.games)) games")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            DisclosureGroup(isExpanded: advanced) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 26) {
                        labelledStepper("Depth", value: draft.depth, range: 2...12)
                            .help("How many moves ahead each search looks. Deeper is stronger and slower.")
                        labelledStepper("Samples", value: draft.determinizations, range: 4...128, step: 4)
                            .help("Hidden worlds sampled per move. More samples are steadier and slower.")
                        labelledStepper("Parallel", value: draft.parallel, range: 1...16)
                            .help("Shard processes running at once. One worker each is fastest on this machine.")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mode")
                                .font(IsolynTheme.caption(11))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                            Picker("", selection: draft.mode) {
                                Text("1v1").tag("1v1")
                                Text("1v1v1").tag("1v1v1")
                                Text("2v2").tag("2v2")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        Spacer()
                    }

                    HStack(spacing: 20) {
                        labelledStepper("Seed", value: draft.seed, range: 1...999_999)
                            .help("Same seed and configuration reproduce the same deals.")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Run id")
                                .font(IsolynTheme.caption(11))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                            Text(draft.wrappedValue.runID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(IsolynTheme.ivory)
                        }
                        Spacer()
                    }
                }
                .padding(.top, 12)
            } label: {
                Text("Advanced")
                    .font(IsolynTheme.caption(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            HStack(spacing: 14) {
                Button {
                    lab.start()
                } label: {
                    Text(lab.isBusy ? "Running…" : "Start \(formatted(draft.wrappedValue.games))-game run")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 280))
                .disabled(lab.isBusy || !lab.harnessBuilt)

                if !lab.harnessBuilt {
                    Text("Build the harness first: ./tools/selfplay/build.sh")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.brass)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).stroke(IsolynTheme.ebonyLine, lineWidth: 1))
    }

    // MARK: Recent

    @ViewBuilder
    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT RUNS")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            let runs = lab.recentRuns(limit: 8)
            if runs.isEmpty {
                Text("No runs yet.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                ForEach(runs, id: \.runId) { run in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.runId)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(IsolynTheme.ivory)
                            Text("\(formatted(run.doneGames))/\(formatted(run.totalGames)) · \(run.config.mode) · d\(run.config.depth)/\(run.config.determinizations)")
                                .font(IsolynTheme.caption(10))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                        }
                        .frame(width: 330, alignment: .leading)

                        ProgressView(value: run.fraction)
                            .progressViewStyle(.linear)
                            .tint(run.isComplete ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                            .frame(width: 150)

                        Text(run.isComplete ? "complete" : "\(run.doneShards)/\(run.shards.count)")
                            .font(IsolynTheme.caption(11))
                            .foregroundStyle(run.isComplete ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                            .frame(width: 80, alignment: .leading)

                        Spacer()

                        if !run.isComplete {
                            actionLink("Resume") { lab.start(run.runConfig) }
                                .disabled(lab.isBusy)
                        }
                        if run.isComplete {
                            actionLink("Merge") { lab.merge(runID: run.runId) }
                        }
                        actionLink("Reveal") { lab.reveal(runID: run.runId) }
                    }
                    .padding(.vertical, 7)
                    Divider().overlay(IsolynTheme.ebonyLine)
                }
            }
        }
    }

    private var footnote: some View {
        Text("One run at a time. The Start button is guarded twice — in the app, and again by the runner's lock — so repeated presses cannot launch a second process.")
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

    private func labelledStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(IsolynTheme.caption(11))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivory)
            }
            .fixedSize()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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

    /// Measured on this machine: ~23 games/s at depth 8 / 64 samples with eight
    /// single-worker shards.
    private func estimate(_ games: Int) -> String {
        let seconds = Double(games) / 23.0
        if seconds < 90 { return "\(Int(seconds))s" }
        let minutes = seconds / 60
        if minutes < 90 { return "\(Int(minutes))m" }
        let hours = minutes / 60
        if hours < 36 { return "\(Int(hours))h" }
        return String(format: "%.1f days", hours / 24)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "\(max(1, totalMinutes))m"
    }
}
