import LibraKit
import SwiftUI

/// Rows for editing a frame inside an inspector section: origin fields, and per axis its direction with
/// controls to aim it at a feature, turn it a quarter, or reverse it.
struct FrameEditor: View {
    let target: FrameTarget
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel
    @DisplayUnitsSetting private var units

    /// The Libra frame is shown in file coordinates; every other frame relative to the Libra frame.
    private var reference: Frame {
        target == .libra ? .file : document.libraFrame
    }

    private var isPickingOrigin: Bool {
        model.tool == .pickOrigin(target)
    }

    var body: some View {
        if let frame = document.frame(for: target) {
            // Distinct ID type from the axis rows below, so Form doesn't confuse the two lists
            ForEach(FrameAxis.allCases, id: \.name) { axis in
                NumberField(title: "Origin \(axis.name)", value: originBinding(frame, axis), unit: units.length.symbol)
            }
            ForEach(FrameAxis.allCases, id: \.self) { axis in
                LabeledContent {
                    HStack(spacing: 10) {
                        Text(direction(frame.axis(axis)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        axisControls(frame, axis)
                    }
                } label: {
                    Label {
                        Text("\(axis.name) Axis")
                    } icon: {
                        Circle()
                            .fill(axisColor(axis))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            HStack {
                Button(isPickingOrigin ? "Cancel Picking" : "Pick Origin…") {
                    model.tool = isPickingOrigin ? .select : .pickOrigin(target)
                }
                .help("Click a hole or shaft edge (its center), a cylinder (its axis), a face (its center) or a corner")
                Spacer()
                Menu("Reset") {
                    Button("Match STEP File Frame") { update(.file) }
                    if target != .libra {
                        Button("Match Libra Frame") { update(document.libraFrame) }
                    }
                    if case .group(let id) = target, let group = document.group(id) {
                        let summary = MassSummary(parts: document.parts(group.partIDs))
                        Button("Origin at Center of Mass") { update(frame.moved(to: summary.properties.centerOfMass)) }
                            .disabled(summary.properties.mass <= 0)
                    }
                }
                .menuStyle(.button)
            }
        }
    }

    private func axisControls(_ frame: Frame, _ axis: FrameAxis) -> some View {
        ControlGroup {
            Button {
                model.tool = model.tool == .pickDirection(target, axis) ? .select : .pickDirection(target, axis)
            } label: {
                Label("Aim \(axis.name) at a Feature", systemImage: "scope")
            }
            .help("Aim \(axis.name) along a shaft's axis, a face's normal or an edge, picked in the viewer")
            Button {
                update(frame.rotatedQuarterTurn(about: axis))
            } label: {
                Label("Rotate Counterclockwise", systemImage: "arrow.counterclockwise")
            }
            .help("Rotate 90° counterclockwise about \(axis.name) (\(axis.name) key in the viewer)")
            Button {
                update(frame.rotatedQuarterTurn(about: axis, clockwise: true))
            } label: {
                Label("Rotate Clockwise", systemImage: "arrow.clockwise")
            }
            .help("Rotate 90° clockwise about \(axis.name) (⇧\(axis.name) in the viewer)")
            Button {
                update(frame.flipped(axis))
            } label: {
                Label("Reverse", systemImage: "arrow.up.arrow.down")
            }
            .help("Reverse \(axis.name) (a half turn about \(axis.next.name))")
        }
        .labelStyle(.iconOnly)
    }

    private func update(_ frame: Frame) {
        document.setFrame(frame, for: target)
    }

    private func originBinding(_ frame: Frame, _ axis: FrameAxis) -> Binding<Double> {
        Binding {
            units.length.fromSI(reference.localPoint(frame.origin)[axis.rawValue])
        } set: { value in
            var local = reference.localPoint(frame.origin)
            local[axis.rawValue] = units.length.toSI(value)
            update(frame.moved(to: reference.filePoint(local)))
        }
    }

    /// "+Y" for axis-aligned directions, otherwise the vector.
    private func direction(_ fileDirection: SIMD3<Double>) -> String {
        let local = reference.localDirection(fileDirection)
        for axis in FrameAxis.allCases where abs(abs(local[axis.rawValue]) - 1) < 1e-9 {
            return (local[axis.rawValue] > 0 ? "+" : "−") + axis.name
        }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        return "(\(local.x.formatted(format)), \(local.y.formatted(format)), \(local.z.formatted(format)))"
    }

    private func axisColor(_ axis: FrameAxis) -> Color {
        let color = [MarkerMesh.Style.xColor, MarkerMesh.Style.yColor, MarkerMesh.Style.zColor][axis.rawValue]
        return Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z))
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.precision(.significantDigits(1...10)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: Layout.numberFieldWidth)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Layout.unitLabelWidth, alignment: .leading)
            }
        }
    }
}
