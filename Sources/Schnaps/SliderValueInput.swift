import SwiftUI

/// A continuous track avoids macOS drawing a tick for every permitted value.
/// Both controls share the same bounds and optional rounding.
struct SliderValueInput: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  var step: Double? = nil
  var unit: String? = nil

  private var boundedValue: Binding<Double> {
    Binding(get: { value }, set: { newValue in
      guard newValue.isFinite else { return }
      let rounded = step.map { (newValue / $0).rounded() * $0 } ?? newValue
      value = min(range.upperBound, max(range.lowerBound, rounded))
    })
  }

  var body: some View {
    HStack(spacing: 8) {
      Slider(value: boundedValue, in: range)
        .accessibilityLabel(title)
      TextField(title, value: boundedValue,
        format: .number.grouping(.never).precision(.fractionLength(0...2)))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 56)
        .accessibilityLabel(title)
      if let unit { Text(unit).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: 260)
    .accessibilityElement(children: .contain)
  }
}
