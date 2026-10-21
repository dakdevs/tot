import Foundation

/// Where to send the user for a thread. T3 Code's desktop app registers `t3code://` only for auth
/// returns, so a specific thread can be opened only through the web route
/// `/<environmentId>/<threadId>` on the local server.
public enum T3Locations {
  public static let desktopBundleID = "com.t3tools.t3code"

  public static func threadURL(userdata: URL, threadID: String) -> URL? {
    struct Runtime: Decodable { var origin: String }
    guard
      let runtime = (try? Data(contentsOf: userdata.appending(path: "server-runtime.json")))
        .flatMap({ try? JSONDecoder().decode(Runtime.self, from: $0) }),
      let environment = try? String(
        contentsOf: userdata.appending(path: "environment-id"), encoding: .utf8
      ).trimmingCharacters(in: .whitespacesAndNewlines),
      !environment.isEmpty
    else { return nil }
    let segment = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    guard let thread = threadID.addingPercentEncoding(withAllowedCharacters: segment) else {
      return nil
    }
    return URL(string: "\(runtime.origin)/\(environment)/\(thread)")
  }
}
