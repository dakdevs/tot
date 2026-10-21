import Foundation

/// How much window-colored backing fills the overlay's glass. Idle, the glass stays see-through and only
/// the backing is lightened; content is never faded. Hovering fills the glass completely.
public enum OverlayGlass {
  public static let idleTintRange = 0.0...0.6
  public static let defaultIdleTint = 0.15

  public static func backingOpacity(isHovering: Bool, idleTint: Double) -> Double {
    isHovering ? 1 : idleTint.clamped(to: idleTintRange)
  }

  /// Maps the retired "Idle opacity" setting, which faded the whole overlay over `0.2...1`, onto the
  /// idle tint range, so a user who chose a more solid overlay keeps a more solid one.
  public static func idleTint(fromLegacyOpacity opacity: Double) -> Double {
    let fraction = ((opacity - 0.2) / 0.8).clamped(to: 0...1)
    return idleTintRange.lowerBound + fraction * (idleTintRange.upperBound - idleTintRange.lowerBound)
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
