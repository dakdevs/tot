import Foundation
import Sparkle
import Testing

/// Release versions are `YYYYMMDD.N` (scripts/release-version.ts). Sparkle decides whether to offer an
/// update by comparing CFBundleVersion, so these pin that its comparator orders them as intended.
@Suite struct ReleaseVersionOrderingTests {
  private let comparator = SUStandardVersionComparator.default

  @Test(arguments: [
    ("20261021.9", "20261021.10"),
    ("20261021.10", "20261022.1"),
    ("20261231.42", "20270101.1"),
    ("0", "20261021.1"),
  ])
  func newerReleaseIsOffered(older: String, newer: String) {
    #expect(comparator.compareVersion(older, toVersion: newer) == .orderedAscending)
    #expect(comparator.compareVersion(newer, toVersion: older) == .orderedDescending)
  }

  @Test func sameReleaseIsNotOffered() {
    #expect(comparator.compareVersion("20261021.10", toVersion: "20261021.10") == .orderedSame)
  }
}
