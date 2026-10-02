import LibraKit
import SwiftUI

/// Edits a frame: pick the origin and axis directions from the model, turn by quarter turns, or type the origin.
struct FrameEditor: View {
    let target: FrameTarget
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel
    @DisplayUnitsSetting private var units

    /// The Libra frame is shown in file coordinates; every other frame relative to the Libra frame.
    private var reference: Frame {
        target == .libra ? .file : document.libraFrame
    }

    private var referenceName: String {
        target == .libra ? "STEP file" : "Libra frame"
    }

    var body: some View {
        if let frame = document.frame(for: target) {
            LabeledContent("Origin") {
                Button(model.tool == .pickOrigin(target) ? "Picking…" : "Pick…") {
                    model.tool = model.tool == .pickOrigin(target) ? .select : .pickOrigin(target)
                }
                .help("Click a hole or shaft edge (its center), a cylinder (its axis), a face (its center) or a corner")
            }
            // Distinct ID type from the axis rows below, so Form doesn't confuse the two lists
            ForEach(FrameAxis.allCases, id: \.name) { axis in
                NumberField(title: "Origin \(axis.name)", value: originBinding(frame, axis), unit: units.length.symbol)
            }
            ForEach(FrameAxis.allCases, id: \.self) { axis in
                LabeledContent {
                    HStack(spacing: 4) {
                        Text(direction(frame.axis(axis))).monospacedDigit().foregroundStyle(.secondary)
                        Button(model.tool == .pickDirection(target, axis) ? "Picking…" : "Aim…") {
                            model.tool = model.tool == .pickDirection(target, axis) ? .select : .pickDirection(target, axis)
                        }
                        .help("Click a cylinder (axis), face (normal) or edge (direction) to point \(axis.name) along it")
                        Button {
                            update(frame.rotatedQuarterTurn(about: axis))
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Turn 90° counterclockwise about \(axis.name) (\(axis.name) key)")
                        Button {
                            update(frame.rotatedQuarterTurn(about: axis, clockwise: true))
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Turn 90° clockwise about \(axis.name) (⇧\(axis.name))")
                        Button {
                            update(frame.flipped(axis))
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .help("Reverse \(axis.name) (turns half way about \(axis.next.name))")
                    }
                } label: {
                    Text("\(axis.name) axis").foregroundStyle(axisColor(axis))
                }
            }
            HStack {
                Menu("Reset") {
                    Button("Match STEP File Frame") { update(.file) }
                    if target != .libra {
                        Button("Match Libra Frame") { update(document.libraFrame) }
                    }
                    if case .body(let id) = target, let body = document.body(id) {
                        let summary = MassSummary(parts: document.parts(body.partIDs))
                        Button("Origin at Center of Mass") { update(frame.moved(to: summary.properties.centerOfMass)) }
                            .disabled(summary.properties.mass <= 0)
                    }
                }
                .fixedSize()
                Spacer()
            }
            Text("Origin and axes are in the \(referenceName)'s coordinates. With the viewer focused, X, Y and Z turn this frame (⇧ reverses).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        return "(\(local.x.formatted(.number.precision(.fractionLength(3)))), \(local.y.formatted(.number.precision(.fractionLength(3)))), \(local.z.formatted(.number.precision(.fractionLength(3)))))"
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
                    .frame(minWidth: 40, alignment: .leading)
            }
        }
    }
}
