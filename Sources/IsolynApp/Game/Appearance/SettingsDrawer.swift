import SwiftUI
import IsolynEngineBridge

/// Compact side settings drawer for domino appearance and inspection.
/// Slides in from the right edge; owns its own gesture space; never pans
/// the board or advances game state.
struct SettingsDrawer: View {
    @Binding var isOpen: Bool
    @Bindable var appearanceManager: AppearanceManager
    @Bindable var inspectionSettings: InspectionSettings
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider().overlay(IsolynTheme.ebonyLine)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InspectionSection(settings: inspectionSettings)
                    Divider().overlay(IsolynTheme.ebonyLine)
                    DominoAppearanceSection(manager: appearanceManager)
                    Divider().overlay(IsolynTheme.ebonyLine)
                    presetsSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
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
            Text("SETTINGS")
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

// MARK: - Inspection Section

private struct InspectionSection: View {
    @Bindable var settings: InspectionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INSPECTION")
                .font(IsolynTheme.caption(10))
                .tracking(1.5)
                .foregroundStyle(IsolynTheme.ivoryMuted)

            Toggle("Reveal on hover", isOn: Binding(
                get: { settings.autoHoverEnabled },
                set: { settings.setAutoHoverEnabled($0) }
            ))
            .toggleStyle(.switch)
            .font(IsolynTheme.body(12))
            .tint(IsolynTheme.brass)

            Text("Off by default. Inspect a domino's number family with the chosen mouse button.")
                .font(IsolynTheme.caption(10))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Mouse button")
                    .font(IsolynTheme.caption(11))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                Spacer()
                Picker("Mouse button", selection: Binding(
                    get: { settings.mouseButton },
                    set: { settings.setMouseButton($0) }
                )) {
                    ForEach(InspectionMouseButton.allCases) { button in
                        Text(button.rawValue).tag(button)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)
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

            Picker("Edge highlight", selection: Binding(
                get: { manager.appearance.edgeMode },
                set: { manager.setEdgeMode($0) }
            )) {
                ForEach(EdgeHighlightMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

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
            IsolynDominoTile(leftPips: 3, rightPips: 5, height: 20, appearance: manager.appearance)
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
        .onChange(of: hex) { _, newValue in textInput = newValue }
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
        // FIX-21 (N-1): pure hex->HSB lookup; the old Color-cache path
        // always returned hue 0, pinning the thumb to the left edge.
        let hue = Color.hsb(fromHex: currentHex).hue
        return CGFloat(hue / 360) * width - 7
    }
}



// MARK: - Preview Tile

