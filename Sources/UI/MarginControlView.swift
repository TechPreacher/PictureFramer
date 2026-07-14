import SwiftUI

/// Slider + stepper + text field for the background margin, in source-image
/// pixels, applied equally on all four sides.
struct MarginControlView: View {
    @Binding var marginPixels: Double

    private static let range: ClosedRange<Double> = 0...500

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Background margin")
                    .font(.subheadline)
                Spacer()
                TextField(
                    "Margin",
                    value: $marginPixels,
                    format: .number.precision(.fractionLength(0))
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .textFieldStyle(.roundedBorder)
                .onChange(of: marginPixels) { _, newValue in
                    marginPixels = min(max(newValue, Self.range.lowerBound), Self.range.upperBound)
                }
                Text("px")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Slider(value: $marginPixels, in: Self.range, step: 1) {
                    Text("Background margin")
                }
                Stepper("", value: $marginPixels, in: Self.range, step: 1)
                    .labelsHidden()
            }
        }
        .accessibilityElement(children: .contain)
    }
}
