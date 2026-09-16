import Testing
@testable import SuperPaste

struct DeviceIDTests {

    @Test func deviceIDIsNonEmpty() {
        let id = DeviceID.current
        #expect(!id.isEmpty)
    }

    @Test func deviceIDIsUUIDFormat() {
        let id = DeviceID.current
        // UUID strings are 36 characters and contain hyphens
        #expect(id.count == 36)
        #expect(id.contains("-"))
    }
}