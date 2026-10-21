import Testing
import TotCore

struct OverlayGlassTests {
  @Test func `hovering fills the glass completely whatever the idle tint`() {
    #expect(OverlayGlass.backingOpacity(isHovering: true, idleTint: 0) == 1)
    #expect(OverlayGlass.backingOpacity(isHovering: true, idleTint: 0.6) == 1)
  }

  @Test func `idle glass stays see-through, even when a stored tint is out of range`() {
    #expect(OverlayGlass.backingOpacity(isHovering: false, idleTint: 0.15) == 0.15)
    #expect(OverlayGlass.backingOpacity(isHovering: false, idleTint: 0.95) == 0.6)
    #expect(OverlayGlass.backingOpacity(isHovering: false, idleTint: -1) == 0)
  }

  @Test func `the retired idle opacity maps onto the idle tint range`() {
    // Old slider ran 0.2...1; its ends become the new range's ends and its old 0.6 default the midpoint.
    #expect(OverlayGlass.idleTint(fromLegacyOpacity: 0.2) == 0)
    #expect(OverlayGlass.idleTint(fromLegacyOpacity: 1) == 0.6)
    #expect(abs(OverlayGlass.idleTint(fromLegacyOpacity: 0.6) - 0.3) < 1e-9)
    #expect(OverlayGlass.idleTint(fromLegacyOpacity: 0) == 0)
  }
}
