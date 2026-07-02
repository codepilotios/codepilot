import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class MacPeerConnectionTests: XCTestCase {
    func testAcceptsSignalsOnlyForActiveLeaseAndIncreasingSequence() throws {
        let peer = MacPeerConnection()
        peer.start(leaseID: "lease-1")

        try peer.acceptRemoteSignal(MacPeerSignal(
            leaseID: "lease-1",
            sequence: 1,
            kind: .offer,
            payload: Data("sdp".utf8)
        ))

        XCTAssertThrowsError(try peer.acceptRemoteSignal(MacPeerSignal(
            leaseID: "lease-2",
            sequence: 2,
            kind: .answer,
            payload: Data()
        )))
        XCTAssertThrowsError(try peer.acceptRemoteSignal(MacPeerSignal(
            leaseID: "lease-1",
            sequence: 1,
            kind: .ice,
            payload: Data()
        )))
    }

    func testDisconnectClearsPendingSignalsAndState() throws {
        let peer = MacPeerConnection()
        peer.start(leaseID: "lease-1")
        peer.markConnected()
        try peer.enqueueLocalSignal(kind: .answer, payload: Data("answer".utf8))

        XCTAssertEqual(peer.drainLocalSignals().count, 1)
        try peer.enqueueLocalSignal(kind: .ice, payload: Data("ice".utf8))
        peer.disconnect()

        XCTAssertEqual(peer.state, .disconnected(leaseID: "lease-1"))
        XCTAssertTrue(peer.drainLocalSignals().isEmpty)
        XCTAssertThrowsError(try peer.enqueueLocalSignal(kind: .ice, payload: Data()))
    }
}
