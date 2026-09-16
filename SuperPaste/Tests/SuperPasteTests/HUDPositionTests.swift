import CoreGraphics
import Testing
@testable import SuperPaste

struct HUDPositionTests {

    @Test func topRightOriginUsesMaxXAndMaxY() {
        let pos = HUDPosition.topRight
        let origin = pos.origin(
            hudSize: CGSize(width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            margin: 16
        )
        #expect(origin.x == 1440 - 300 - 16)
        #expect(origin.y == 900 - 200 - 16)
    }

    @Test func topLeftOriginUsesMinXAndMaxY() {
        let pos = HUDPosition.topLeft
        let origin = pos.origin(
            hudSize: CGSize(width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            margin: 16
        )
        #expect(origin.x == 0 + 16)
        #expect(origin.y == 900 - 200 - 16)
    }

    @Test func bottomRightOriginUsesMaxXAndMinY() {
        let pos = HUDPosition.bottomRight
        let origin = pos.origin(
            hudSize: CGSize(width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            margin: 16
        )
        #expect(origin.x == 1440 - 300 - 16)
        #expect(origin.y == 0 + 16)
    }

    @Test func bottomLeftOriginUsesMinXAndMinY() {
        let pos = HUDPosition.bottomLeft
        let origin = pos.origin(
            hudSize: CGSize(width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            margin: 16
        )
        #expect(origin.x == 0 + 16)
        #expect(origin.y == 0 + 16)
    }

    @Test func defaultMarginIs16() {
        let pos = HUDPosition.topRight
        let defaultOrigin = pos.origin(
            hudSize: CGSize(width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let explicitOrigin = pos.origin(
            hudSize: CGSize(width: 300, height: 200),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            margin: 16
        )
        #expect(defaultOrigin == explicitOrigin)
    }

    @Test func rawValuesAndDisplayNamesAreConsistent() {
        #expect(HUDPosition.topRight.rawValue == "topRight")
        #expect(HUDPosition.topRight.displayName == "Top Right")
        #expect(HUDPosition.topLeft.rawValue == "topLeft")
        #expect(HUDPosition.topLeft.displayName == "Top Left")
        #expect(HUDPosition.bottomRight.rawValue == "bottomRight")
        #expect(HUDPosition.bottomRight.displayName == "Bottom Right")
        #expect(HUDPosition.bottomLeft.rawValue == "bottomLeft")
        #expect(HUDPosition.bottomLeft.displayName == "Bottom Left")
    }

    @Test func allCasesAreFour() {
        #expect(HUDPosition.allCases.count == 4)
    }
}