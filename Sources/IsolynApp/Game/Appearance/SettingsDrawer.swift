import SwiftUI
import IsolynEngineBridge

/// Compact side settings drawer for domino appearance customization.
/// Slides in from the right edge; owns its own gesture space; never pans
/// the board or alters camera/hover/game state.
struct SettingsDrawer: View {
    @Binding var isOpen: Bool
    @Bindable var appearanceManager: AppearanceManager
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().overlay(IsolynTheme.ebonyLine)
            DominoAppearanceSection(manager: appearanceManager)
            Divider().overlay(IsolynTheme.ebonyLine)
            presetsSection
            Spacer()
        }
        .padding(20)
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(IsolynTheme.ebonyElevated.opacity(0.98))
                .shadow(color: .black.opacity(0.5), radius: 12, x: -4)
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(IsolynTheme.ebonyLine).frame(width: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("APPEARANCE")
                .font(IsolynTheme.caption(11))
                .tracking(2)
                .foregroundStyle(IsolynTheme.brass)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS").font(IsolynTheme.caption(10)).tracking(1.5)
                .foregroundStyle(IsolynTheme.ivoryMuted)
            ForEach(DominoAppearance.presets, id: \.name) { name, preset in
                Button {
                    appearanceManager.applyPreset(preset)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(preset.bodyColor).frame(width: 14, height: 14)
                        Circle().fill(preset.pipColor).frame(width: 10, height: 10)
                        Text(name).font(IsolynTheme.body(13))
                            .foregroundStyle(IsolynTheme.ivory)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Domino Appearance Section

private struct DominoAppearanceSection: View {
    @Bindable var manager: AppearanceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DOMINO BODY").font(IsolynTheme.caption(10)).tracking(1.5)
                .foregroundStyle(IsolynTheme.ivoryMuted)
            ColorEditorRow(
                hex: Binding(get: { manager.appearance.bodyColorHex },
                             set: { manager.setBodyColor(hex: $0) }),
                onHueChange: { manager.setBodyHue($0) }
            )

            Text("PIP COLOR").font(IsolynTheme.caption(10)).tracking(1.5)
                .foregroundStyle(IsolynTheme.ivoryMuted)
            ColorEditorRow(
                hex: Binding(get: { manager.appearance.pipColorHex },
                             set: { manager.setPipColor(hex: $0) }),
                onHueChange: nil
            )

            Text("EDGE HIGHLIGHT").font(IsolynTheme.caption(10)).tracking(1.5)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            Picker("", selection: Binding(
                get: { manager.appearance.edgeMode },
                set: { manager.setEdgeMode($0) }
            )) {
                ForEach(EdgeHighlightMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if manager.appearance.edgeMode != .none {
                ColorEditorRow(
                    hex: Binding(get: { manager.appearance.edgeColorHex },
                                 set: { manager.setEdgeColor(hex: $0) }),
                    onHueChange: nil
                )
                HStack {
                    Text("Intensity").font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Slider(value: Binding(
                        get: { manager.appearance.edgeIntensity },
                        set: { manager.setEdgeIntensity($0) }
                    ), in: 0...1).controlSize(.mini)
                }
            }

            previewTile
        }
    }

    /// Live preview rendered with the same TileView component as the board.
    private var previewTile: some View {
        HStack(spacing: 8) {
            Text("Preview").font(IsolynTheme.caption(11)).foregroundStyle(IsolynTheme.ivoryMuted)
            AppearanceTilePreview(appearance: manager.appearance)
        }
    }
}

// MARK: - Color Editor Row (HEX field + hue slider)

private struct ColorEditorRow: View {
    @Binding var hex: String
    let onHueChange: ((Double) -> Void)?
    @State private var textInput: String = ""
    @State private var isValid = true

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: hex) ?? .gray).frame(width: 22, height: 22)
                TextField("#RRGGBB", text: $textInput, onCommit: commitHex)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isValid ? Color.clear : Color.red, lineWidth: 1)
                    )
                Spacer()
            }
            if let onHueChange {
                HueSlider(currentHex: hex, onHueChange: onHueChange)
                    .frame(height: 18)
            }
        }
        .onAppear { textInput = hex }
        .onChange(of: hex) { newValue in textInput = newValue }
    }

    private func commitHex() {
        var cleaned = textInput.trimmingCharacters(in: .whitespaces)
        if !cleaned.hasPrefix("#") { cleaned = "#" + cleaned }
        if Color(hex: cleaned) != nil {
            hex = cleaned.uppercased()
            isValid = true
        } else {
            isValid = false
            textInput = hex // revert to last valid
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isValid = true }
        }
    }
}

// MARK: - Hue Slider

private struct HueSlider: View {
    let currentHex: String
    let onHueChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [
                        .red, .orange, .yellow, .green,
                        .cyan, .blue, .purple, .red
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .cornerRadius(4)

                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(radius: 2)
                    .offset(x: thumbOffset(in: geo.size.width))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let fraction = max(0, min(1, g.location.x / geo.size.width))
                    onHueChange(fraction * 360)
                }
            )
        }
    }

    private func thumbOffset(in width: CGFloat) -> CGFloat {
        guard let color = Color(hex: currentHex) else { return 0 }
        return CGFloat(color.hsB.hue / 360) * width - 7
    }
}



// MARK: - Preview Tile

/// Renders a sample domino using the same visual pipeline as the board.
struct AppearanceTilePreview: View {
    let appearance: DominoAppearance

    var body: some View {
        HStack(spacing: 1.5) {
            face(pips: 3)
            Rectangle().fill(IsolynTheme.ebonyLine).frame(width: 1.5)
            face(pips: 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(edgeStroke, lineWidth: edgeWidth)
        )
    }

    @ViewBuilder
    private func face(pips: Int) -> some View {
        let side: CGFloat = 26
        let cell = side / 3
        let pipSize = cell * 0.52
        let layouts: [Int: [(CGFloat, CGFloat)]] = [
            3: [(0, 0), (1, 1), (2, 2)],
            5: [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)],
        ]
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.14)
                .fill(appearance.bodyColor)
            ForEach(Array((layouts[pips] ?? []).enumerated()), id: \.offset) { _, pos in
                Circle().fill(appearance.pipColor)
                    .frame(width: pipSize, height: pipSize)
                    .position(x: cell * (pos.0 + 0.5), y: cell * (pos.1 + 0.5))
            }
        }
        .frame(width: side, height: side)
    }

    private var edgeStroke: Color {
        appearance.edgeMode == .none ? Color.clear : appearance.edgeColor.opacity(appearance.edgeIntensity + 0.15)
    }
    private var edgeWidth: CGFloat {
        appearance.edgeMode == .none ? 0 : 1.5
    }
}
