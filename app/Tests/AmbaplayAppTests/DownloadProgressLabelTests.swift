import Foundation
import Testing
import AmbaplayUI
@testable import AmbaplayApp

@Suite("Download progress label")
struct DownloadProgressLabelTests {
    @Test func showsAmountAndRoundsTheEstimateUpToMinutes() {
        let label = PinnedDownload.Progress.label(host: "github.com", received: 100_000_000, total: 400_000_000, remaining: 61)
        #expect(label.hasPrefix("Downloading from github.com: 100 MB / 400 MB"))
        #expect(label.hasSuffix("about 2 minutes left"))
    }

    @Test func leavesTheEstimateOutUntilThereIsOne() {
        let label = PinnedDownload.Progress.label(host: "github.com", received: 0, total: 400_000_000, remaining: nil)
        #expect(label == "Downloading from github.com: Zero KB / 400 MB")
    }

    @Test func showsTheSpeed() {
        let label = PinnedDownload.Progress.label(host: "github.com", received: 100_000_000, total: 400_000_000, remaining: nil, speed: 2_400_000)
        let speed = ByteCountFormatter.string(fromByteCount: 2_400_000, countStyle: .file)
        #expect(label == "Downloading from github.com: 100 MB / 400 MB · \(speed)/s")
    }

    @Test func speedCoversTheLastFewSeconds() {
        var rate = DownloadRate()
        #expect(rate.add(0, at: 0) == nil)
        #expect(rate.add(500_000, at: 0.5) == nil)
        #expect(rate.add(1_000_000, at: 1) == 1_000_000)
        // A stall then a burst: only the last five seconds or so count.
        _ = rate.add(1_000_000, at: 10)
        #expect(rate.add(5_000_000, at: 12) == 2_000_000)
        // Started over: no speed until a second has passed again.
        #expect(rate.add(0, at: 13) == nil)
    }
}
