import Testing

@testable import AmbaplayApp

@Suite("Update everything")
struct UpdateEverythingTests {

    @Test("An older patch in Steam and outdated engines are all planned, in that order")
    func everythingOutdated() {
        let plan = SystemStatus.updatePlan(
            steam: .outdated(deployed: "3.0.0", bundled: "3.0.1"), hasRunner: true,
            winecx: .outdated, winehq: .outdated)
        #expect(plan == [.steamPatch, .winecx, .winehq])
    }

    @Test("Engines the user never set up, or that are current, are left alone")
    func onlyOutdatedEngines() {
        let plan = SystemStatus.updatePlan(
            steam: .installed(version: "3.0.1"), hasRunner: true, winecx: .outdated, winehq: .missing)
        #expect(plan == [.winecx])
        #expect(SystemStatus.updatePlan(
            steam: .installed(version: "3.0.1"), hasRunner: true, winecx: .current, winehq: .missing).isEmpty)
    }

    @Test("Steam is not patched without a compatibility tool, or when the recorded version is unknown")
    func steamPatchNeedsRunnerAndVersion() {
        #expect(SystemStatus.updatePlan(
            steam: .outdated(deployed: "3.0.0", bundled: "3.0.1"), hasRunner: false,
            winecx: .current, winehq: .missing).isEmpty)
        #expect(SystemStatus.updatePlan(
            steam: .outdated(deployed: "", bundled: "3.0.1"), hasRunner: true,
            winecx: .current, winehq: .missing).isEmpty)
        #expect(SystemStatus.updatePlan(
            steam: .notInstalled, hasRunner: true, winecx: .current, winehq: .missing).isEmpty)
    }
}
