import AppKit
import SwiftUI

/// Calibration analyses over finished runs. Several inputs can be analyzed at
/// once — one process, one JSON array, one card per input.
struct LabAnalysisView: View {
    @Environment(LabService.self) private var lab
    @Environment(LabAnalysisService.self) private var analysis

    @State private var selection: Set<String> = []

    private var completedRuns: [LabManifest] {
        lab.runs(filter: .finished)
    }

    private var selectedInputs: [URL] {
        completedRuns
            .filter { selection.contains($0.runId) }
            .flatMap { analysis.inputs(for: $0.runId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            intro
            picker
                .labCard()
            if analysis.isRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reading CSVs and computing reports…")
                        .font(IsolynTheme.body(13))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Button("Stop") { analysis.stop() }
                        .buttonStyle(.plain)
                        .font(IsolynTheme.caption(12))
                        .foregroundStyle(IsolynTheme.brass)
                    if let log = analysis.lastLogURL {
                        LabLink(title: "Open log") { NSWorkspace.shared.open(log) }
                    }
                    Spacer()
                }
            }
            results
        }
        .onAppear { lab.refreshLibrary(force: true) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                lab.refreshLibrary()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANALYSES")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.ivoryMuted)
            Text("Pick finished runs and analyze them together. Each input becomes its own report: who won, how often, how the score moved, and whether a better starting hand actually predicted the result.")
                .font(IsolynTheme.body(13))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if completedRuns.isEmpty {
                Text("No finished runs yet. Start one from the Runs tab; analyses only read completed output.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                ForEach(completedRuns, id: \.runId) { run in
                    runRow(run)
                    Divider().overlay(IsolynTheme.ebonyLine)
                }

                HStack(spacing: 14) {
                    Button {
                        let inputs = selectedInputs
                        analysis.run(inputs: inputs)
                    } label: {
                        Text(runButtonTitle)
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 220))
                    .disabled(selection.isEmpty || analysis.isRunning)

                    Button("Select all") { selection = Set(completedRuns.map(\.runId)) }
                        .buttonStyle(.plain)
                        .font(IsolynTheme.caption(12))
                        .foregroundStyle(IsolynTheme.ivoryMuted)

                    Button("Clear") { selection.removeAll() }
                        .buttonStyle(.plain)
                        .font(IsolynTheme.caption(12))
                        .foregroundStyle(IsolynTheme.ivoryMuted)

                    Spacer()
                }

                if selectedInputs.count > analysis.maxInputs {
                    Text("This selection has \(selectedInputs.count) inputs; only the first \(analysis.maxInputs) will be analyzed. Combine large runs into one CSV first.")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let message = analysis.message {
                Text(message)
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
            if let error = analysis.lastError {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .lineLimit(4)
            }
        }
    }

    private var runButtonTitle: String {
        let count = selectedInputs.count
        if count == 0 { return "Run analyses" }
        return "Run \(count) analys\(count == 1 ? "is" : "es")"
    }

    private func runRow(_ run: LabManifest) -> some View {
        let inputs = analysis.inputs(for: run.runId)
        let selected = selection.contains(run.runId)

        return Button {
            if selected { selection.remove(run.runId) } else { selection.insert(run.runId) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.runId)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivory)
                    Text("\(formatted(run.totalGames)) games · \(run.config.mode) · depth \(run.config.depth) / \(run.config.determinizations) samples · \(inputs.count) input\(inputs.count == 1 ? "" : "s")")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    if analysis.isInputPreviewLimited(for: run.runId) {
                        Text("Showing 8 of \(analysis.shardCount(for: run.runId)) shards. Combine this run for a complete analysis.")
                            .font(IsolynTheme.caption(10))
                            .foregroundStyle(IsolynTheme.brass)
                    }
                }
                Spacer()
                Text(inputs.first?.lastPathComponent ?? "no CSV")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var results: some View {
        if !analysis.reports.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text("REPORTS")
                    .font(IsolynTheme.caption(11))
                    .tracking(2)
                    .foregroundStyle(IsolynTheme.ivoryMuted)

                ForEach(analysis.reports) { report in
                    reportCard(report)
                }
            }
        }
    }

    private func reportCard(_ report: LabAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(report.displayName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivory)
                Text(report.mode)
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ebony)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(IsolynTheme.brass))
                Spacer()
                Text("A d\(report.configA.depth)/\(report.configA.determinizations) · B d\(report.configB.depth)/\(report.configB.determinizations)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                LabLink(title: "Copy") { copyReport(report) }
            }

            if !report.isSymmetric {
                Text("Side B is configured differently from side A, so the Elo line compares two configurations rather than measuring self-play consistency.")
                    .font(IsolynTheme.caption(11))
                    .foregroundStyle(IsolynTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("\(formatted(report.games)) games · \(formatted(report.decisions)) decisions · \(report.outcomeSummary)")
                .font(IsolynTheme.body(12))
                .foregroundStyle(IsolynTheme.ivoryMuted)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                GridRow {
                    tableHeader("Player")
                    tableHeader("Games", align: .trailing)
                    tableHeader("Wins", align: .trailing)
                    tableHeader("Win%", align: .trailing)
                    tableHeader("95% CI", align: .trailing)
                    tableHeader("Avg pts", align: .trailing)
                    tableHeader("Avg start", align: .trailing)
                }
                Divider().gridCellColumns(7).overlay(IsolynTheme.ebonyLine)

                ForEach(report.participants) { participant in
                    GridRow {
                        Text(participant.label)
                            .font(IsolynTheme.body(12))
                            .foregroundStyle(IsolynTheme.ivory)
                        number("\(participant.games)")
                        number("\(participant.wins)")
                        number(String(format: "%.1f%%", participant.winRate * 100))
                        number(String(format: "%.0f–%.0f%%", participant.winLow * 100, participant.winHigh * 100))
                        number(String(format: "%.2f", participant.averagePoints))
                        number(String(format: "%.1f", participant.averageInitialPips))
                    }
                }
            }

            if let elo = report.elo {
                Text(eloLine(elo))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            Text(spearmanLine(report.spearman))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        }
        .labCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableHeader(_ title: String, align: HorizontalAlignment = .leading) -> some View {
        Text(title)
            .font(IsolynTheme.caption(10))
            .foregroundStyle(IsolynTheme.ivoryMuted)
            .frame(minWidth: 0, alignment: align == .trailing ? .trailing : .leading)
    }

    private func number(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(IsolynTheme.ivory)
            .frame(minWidth: 0, alignment: .trailing)
    }

    private func eloLine(_ elo: LabEloReport) -> String {
        let value = elo.aVsB.map { String(format: "%+.1f", $0) } ?? "undefined (undefeated/winless)"
        let interval: String
        if let low = elo.low, let high = elo.high {
            interval = String(format: "[%+.1f, %+.1f]", low, high)
        } else {
            interval = "n/a"
        }
        return "Elo(A vs B): \(value)  95% CI \(interval)  n=\(elo.games)  score A=\(String(format: "%.3f", elo.scoreA))"
    }

    private func spearmanLine(_ spearman: LabSpearmanReport) -> String {
        let points = spearman.initialVsPoints.map { String(format: "%+.3f", $0) } ?? "n/a"
        let wins = spearman.initialVsWin.map { String(format: "%+.3f", $0) } ?? "n/a"
        return "Spearman(initial pips, points) = \(points)  ·  (initial pips, win) = \(wins)  ·  n=\(spearman.samples)"
    }

    private func copyReport(_ report: LabAnalysisReport) {
        var lines = [
            "Isolyn calibration report",
            "input: \(report.input ?? "—")",
            "mode: \(report.mode)",
            "games: \(report.games)",
            "decisions: \(report.decisions)",
            "outcomes: \(report.outcomeSummary)",
            "config A: depth=\(report.configA.depth) determinizations=\(report.configA.determinizations)",
            "config B: depth=\(report.configB.depth) determinizations=\(report.configB.determinizations)",
            "",
        ]
        for participant in report.participants {
            lines.append(
                "\(participant.label): \(participant.games) games, \(participant.wins) wins, "
                + String(format: "%.1f%%", participant.winRate * 100)
                + String(format: ", %.2f avg points, %.1f avg start", participant.averagePoints, participant.averageInitialPips)
            )
        }
        if let elo = report.elo {
            lines.append(eloLine(elo))
        }
        lines.append(spearmanLine(report.spearman))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func formatted(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}
