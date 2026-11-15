import SwiftUI

/// The first external path, intentionally with one fixed size. The owner
/// confirms the private upload once; after that the only decisions are
/// "collect" and "open the result".
struct LabCloudView: View {
    @Environment(LabCloudService.self) private var cloud
    @State private var confirmUpload = false

    var body: some View {
        @Bindable var cloud = cloud

        VStack(alignment: .leading, spacing: 18) {
            intro
            sourceCard
            runCard
            statusCard
        }
        .onAppear { cloud.refresh() }
        .alert("Upload the private snapshot?", isPresented: $confirmUpload) {
            Button("Upload and run") { cloud.start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This copies the allowlisted engine, harness and Python source to Kaggle as a private dataset, then starts one private CPU-only notebook. It uses only the Kaggle CLI's normal token file — the app never reads that token.")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabSectionTitle(text: "Kaggle calibration run")
            Text("The first cloud run is fixed at 10,000 games in one session. It is the acceptance test for the external path, not a training run and not a five-million-game corpus.")
                .font(IsolynTheme.body(13))
                .foregroundStyle(IsolynTheme.ivory)
                .fixedSize(horizontal: false, vertical: true)
            Text("One click plans the shards, prepares a private source snapshot and uploads it. The local C++ engine remains the only rules authority; Kaggle only builds and runs the same harness.")
                .font(IsolynTheme.body(12))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labCard()
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabSectionTitle(text: "Staged source")
                Spacer()
                Text(cloud.sourceReady ? "ready" : "not ready")
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(cloud.sourceReady ? IsolynTheme.ivoryMuted : IsolynTheme.brass)
            }
            Text(cloud.sourceSummary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivory)
                .textSelection(.enabled)
            Text("The app never runs git against your Desktop checkout. run.sh stages the allowlisted source and records the commit, file hashes and a code digest here; the cloud driver refuses a changed or dirty bundle.")
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let source = cloud.source,
               (!source.clean || (source.sourceCommit ?? "").isEmpty),
               !cloud.isBusy {
                Text("Commit the checkout and run ./run.sh to make the bundle clean. The app cannot plan an upload from a dirty tree.")
                    .font(IsolynTheme.caption(11))
                    .foregroundStyle(IsolynTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .labCard()
    }

    private var runCard: some View {
        @Bindable var cloud = cloud

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                LabSectionTitle(text: "First run")
                Spacer()
                Text("one session")
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }

            HStack(spacing: 26) {
                fixedStat("Games", cloud.games.formatted())
                fixedStat("Shards", "4 × 2,500")
                fixedStat("Mode", "1v1")
                fixedStat("Search", "depth 8 · 64 worlds")
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Kaggle owner")
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivory)
                TextField("your-kaggle-username", text: $cloud.owner)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 210)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().stroke(IsolynTheme.ebonyLine.opacity(0.7), lineWidth: 1)
                    )
                Text("Needed for the private dataset and notebook names.")
                    .font(IsolynTheme.caption(10))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                Spacer()
            }

            HStack(spacing: 14) {
                primaryAction
                Spacer()
            }

            Text(cloud.resultSummary)
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labCard()
    }

    @ViewBuilder
    private var primaryAction: some View {
        if cloud.assembled {
            Text("Collected and verified")
                .font(IsolynTheme.body(13))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        } else if !cloud.hasPushed {
            Button {
                confirmUpload = true
            } label: {
                Text(cloud.isBusy ? "Working…" : "Start 10,000-game Kaggle run")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 280))
            .disabled(cloud.isBusy || cloud.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else if cloud.remoteComplete {
            Button {
                cloud.collect()
            } label: {
                Text(cloud.phase == .collecting ? "Collecting…" : "Collect verified results")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 280))
            .disabled(!cloud.canCollect)
        } else {
            Button {
                cloud.checkStatus()
            } label: {
                Text(cloud.phase == .checkingStatus ? "Checking Kaggle…" : "Check Kaggle status")
            }
            .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 280))
            .disabled(cloud.isBusy)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(cloud.statusTitle)
                    .font(IsolynTheme.title(16))
                    .foregroundStyle(IsolynTheme.ivory)
                if cloud.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let plan = cloud.plan {
                    Text("\(plan.shards.count) shards · \(plan.sessions.count) session")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
            }

            Text(cloud.planSummary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted)

            if let remoteStatus = cloud.remoteStatus {
                Text("Kaggle: \(remoteStatus)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(remoteStatus == "complete" ? IsolynTheme.ivory : IsolynTheme.brass)
            }

            if let message = cloud.message {
                Text(message)
                    .font(IsolynTheme.body(12))
                    .foregroundStyle(IsolynTheme.ivory)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tail = cloud.logTail {
                Text(tail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                LabLink(title: "Show cloud folder") { cloud.reveal() }
                LabLink(title: "Open latest log") { cloud.openLog() }
                Spacer()
            }

            Text("Kaggle remains private, CPU-only and internet-disabled. The app does not claim a live result until the receipt and CSV pass local verification; collection is refused while the notebook is still running.")
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labCard()
    }

    private var statusColor: Color {
        switch cloud.phase {
        case .finished: return IsolynTheme.ivory
        case .failed: return Color(red: 0.82, green: 0.40, blue: 0.32)
        case .waiting, .planning, .preparing, .uploading, .checkingStatus, .collecting: return IsolynTheme.brass
        case .idle, .stopped: return IsolynTheme.ivoryMuted
        }
    }

    private func fixedStat(_ title: String, _ value: String) -> some View {
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
