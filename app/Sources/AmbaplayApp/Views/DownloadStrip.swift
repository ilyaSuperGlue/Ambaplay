import AmbaplayUI
import SwiftUI

/// The running download's bar, with its amount, speed, time left and a Pause button beside it.
struct DownloadStrip: View {
    private let meter = DownloadMeter.shared

    var body: some View {
        if let fraction = meter.fraction {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = meter.title {
                            Text(title).font(BP.sans(13, .semibold)).lineLimit(1)
                        }
                        Text(details)
                            .font(BP.sans(12))
                            .monospacedDigit()
                            .foregroundStyle(BP.fg2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button(meter.paused ? String(localized: "Resume") : String(localized: "Pause")) { meter.togglePause() }
                        .buttonStyle(.pillSecondary)
                }
                GradientProgress(fraction: fraction)
            }
        }
    }

    private var details: String {
        let amount = DownloadRate.amount(received: meter.received, total: meter.total, speed: meter.paused ? nil : meter.speed)
        if meter.paused { return amount + " · " + String(localized: "Paused") }
        guard let left = meter.remaining.flatMap(PinnedDownload.Progress.duration) else { return amount }
        return amount + " · " + String(localized: "about \(left) left")
    }
}
