import AppKit
import SwiftUI

/// The offline lab, reachable from the entry screen: start a 5M-game self-play
/// run, watch it, stop it, merge it, and resume it after an interruption.
///
/// The controls are deliberately narrow. One run at a time is enforced in
/// `LabService`, not only by disabling a button, because a disabled button is
/// a courtesy and not a guarantee.
struct LabView: View {
    @Environment(AppState.self) private var appState
    @Environment(LabService.self) private var lab

    private struct Preset: Identifiable {
        let title: String
        let games: Int
        var id: Int { games }
    }

    private let presets: [Preset] = [
        Preset(title: "Smoke 200", games: 200),
        Preset(title: "10K", games: 10_000),
        Preset(title: "1M", games: 1_000_000),
        Preset(title: "5M", games: 5_000_000),
    ]

    var body: some View {
        @Bindable var lab = lab

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                presetRow
                configuration(
                    depth: $lab.draft.depth,
                    samples: $lab.draft.determinizations,
                    parallel: $lab.draft.parallel,
                    mode: $lab.draft.mode
                )
                runControls
                statusCard
                recentRuns
                footnote
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity)
        }
        .onAppear { lab.attachToActiveRun() }
    }

    // MARK: - Sections

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

            Text("Self-play runs that continue where they stopped. Shards finish out of order, so a stopped run resumes from the last complete one.")
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RUN SIZE")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            HStack(spacing: 10) {
                ForEach(presets) { preset in
                    Button {
                        lab.draft.games = preset.games
                    } label: {
                        Text(preset.title)
                            .font(IsolynTheme.body(13))
                            .foregroundStyle(lab.draft.games == preset.games ? IsolynTheme.ebony : IsolynTheme.ivory)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    lab.draft.games == preset.games
                                        ? IsolynTheme.brass
                                        : IsolynTheme.ebonyElevated
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(formatted(lab.draft.games)) games")
                    .font(IsolynTheme.caption(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
    }

    private func configuration(
        depth: Binding<Int>,
        samples: Binding<Int>,
        parallel: Binding<Int>,
        mode: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEARCH")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            HStack(spacing: 26) {
                labelledStepper("Depth", value: depth, range: 2...12)
                labelledStepper("Samples", value: samples, range: 4...128, step: 4)
                labelledStepper("Parallel", value: parallel, range: 1...16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mode")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Picker("", selection: mode) {
                        Text("1v1").tag("1v1")
                        Text("1v1v1").tag("1v1v1")
                        Text("2v2").tag("2v2")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Spacer()
            }
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
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivory)
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    lab.start()
                } label: {
                    Text(lab.isBusy ? "Running…" : "Start \(formatted(lab.draft.games))-game run")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 280))
                .disabled(lab.isBusy)

                if lab.isBusy {
                    Button {
                        lab.stop()
                    } label: {
                        Text("Stop")
                            .font(IsolynTheme.body(14))
                            .foregroundStyle(IsolynTheme.ivory)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().stroke(IsolynTheme.ebonyLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            Text(lab.draft.runID)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 7, height: 7)
                Text(lab.statusTitle)
                    .font(IsolynTheme.title(16))
                    .foregroundStyle(IsolynTheme.ivory)
                Spacer()
                if let manifest = lab.manifest {
                    Text("\(Int(manifest.fraction * 100))%")
                        .font(IsolynTheme.body(13))
                        .monospacedDigit()
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
            }

            if let manifest = lab.manifest {
                ProgressView(value: manifest.fraction)
                    .progressViewStyle(.linear)
                    .tint(IsolynTheme.brass)

                HStack(spacing: 30) {
                    stat("Games", "\(formatted(manifest.doneGames)) / \(formatted(manifest.totalGames))")
                    stat("Shards", "\(manifest.doneShards) / \(manifest.shards.count)")
                    if let rate = manifest.gamesPerSecond() {
                        stat("Rate", "\(Int(rate)) games/s")
                    }
                    if let remaining = manifest.estimatedRemaining() {
                        stat("Remaining", duration(remaining))
                    }
                    if manifest.failedShards > 0 {
                        stat("Failed shards", "\(manifest.failedShards)")
                    }
                }

                HStack(spacing: 16) {
                    Button("Reveal folder") { lab.reveal(runID: manifest.runId) }
                        .buttonStyle(.plain)
                        .font(IsolynTheme.caption(12))
                        .foregroundStyle(IsolynTheme.brass)

                    if manifest.isComplete {
                        Button("Merge to CSV") { lab.merge(runID: manifest.runId) }
                            .buttonStyle(.plain)
                            .font(IsolynTheme.caption(12))
                            .foregroundStyle(IsolynTheme.brass)
                    }
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
                Text("Pick a size and start. A 5M run at depth 8 takes about 32 hours at the measured rate; the app can be closed and the run will still be here.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = lab.message {
                Text(message)
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(IsolynTheme.ebonyElevated)
        )
    }

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT RUNS")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            let runs = lab.recentRuns()
            if runs.isEmpty {
                Text("No runs yet.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                ForEach(runs, id: \.runId) { run in
                    HStack(spacing: 14) {
                        Text(run.runId)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(IsolynTheme.ivory)
                            .lineLimit(1)
                        Spacer()
                        Text("\(run.doneGames)/\(run.totalGames)")
                            .font(IsolynTheme.caption(11))
                            .monospacedDigit()
                            .foregroundStyle(IsolynTheme.ivoryMuted)
                        Text(run.isComplete ? "complete" : "unfinished")
                            .font(IsolynTheme.caption(11))
                            .foregroundStyle(run.isComplete ? IsolynTheme.brass : IsolynTheme.ivoryMuted)

                        if !run.isComplete {
                            Button("Resume") {
                                lab.start(run.runConfig)
                            }
                            .buttonStyle(.plain)
                            .font(IsolynTheme.caption(12))
                            .foregroundStyle(IsolynTheme.ivory)
                            .disabled(lab.isBusy)
                        }
                        Button("Reveal") { lab.reveal(runID: run.runId) }
                            .buttonStyle(.plain)
                            .font(IsolynTheme.caption(12))
                            .foregroundStyle(IsolynTheme.ivoryMuted)
                    }
                    .padding(.vertical, 7)
                    Divider().overlay(IsolynTheme.ebonyLine)
                }
            }
        }
    }

    private var footnote: some View {
        Text("One run at a time. Starting an active configuration again attaches to it rather than spawning another process; the runner's own lock rejects a second one even if the app is bypassed.")
            .font(IsolynTheme.caption(11))
            .foregroundStyle(IsolynTheme.ivoryMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private var indicatorColor: Color {
        switch lab.phase {
        case .running, .launching: return IsolynTheme.brass
        case .finished: return IsolynTheme.brass
        case .failed: return Color(red: 0.72, green: 0.28, blue: 0.24)
        case .stopped, .idle: return IsolynTheme.ebonyLine
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Text(value)
                .font(IsolynTheme.body(13))
                .monospacedDigit()
                .foregroundStyle(IsolynTheme.ivory)
        }
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
}
