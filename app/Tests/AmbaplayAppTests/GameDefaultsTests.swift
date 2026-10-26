import Foundation
import Testing
@testable import AmbaplayApp

@Suite struct GameDefaultsTests {
    @Test func readsTheLastAssignmentInEitherSpelling() {
        #expect(GameDefaults.isOn(.highResolution, in: "RETINA=1\n"))
        #expect(GameDefaults.isOn(.highResolution, in: "  AMBAPLAY_RETINA=1  \n"))
        #expect(!GameDefaults.isOn(.highResolution, in: "RETINA=1\nRETINA=0\n"))
        #expect(!GameDefaults.isOn(.metalHUD, in: "# MTL_HUD_ENABLED=1\n"))
        #expect(!GameDefaults.isOn(.metalHUD, in: ""))
    }

    @Test func keepsEveryOtherLineAndReplacesOnlyItsOwn() {
        let text = "# mine\nMTL_HUD_ENABLED=1\nRETINA=1\nAMBAPLAY_RETINA=1\nROSETTA_ADVERTISE_AVX=1\n"
        let off = GameDefaults.setting(.highResolution, to: false, in: text)
        #expect(off == "# mine\nMTL_HUD_ENABLED=1\nROSETTA_ADVERTISE_AVX=1\n")
        let on = GameDefaults.setting(.metalHUD, to: true, in: "# mine\nROSETTA_ADVERTISE_AVX=1")
        #expect(on == "# mine\nROSETTA_ADVERTISE_AVX=1\nMTL_HUD_ENABLED=1\n")
    }

    @Test func startsANewFileWithItsHeaderAndEmptiesItWhenAllIsOff() {
        let on = GameDefaults.setting(.metalHUD, to: true, in: "")
        #expect(on == GameDefaults.header + "\nMTL_HUD_ENABLED=1\n")
        #expect(GameDefaults.setting(.metalHUD, to: false, in: "MTL_HUD_ENABLED=1\n") == "")
    }

    @Test func writesAndReadsBackAFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gamedefaults-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "gamefixes/default.conf")
        try GameDefaults.set(.highResolution, to: true, at: url)
        #expect(GameDefaults.isOn(.highResolution, at: url))
        try GameDefaults.set(.highResolution, to: false, at: url)
        #expect(!GameDefaults.isOn(.highResolution, at: url))
    }
}
