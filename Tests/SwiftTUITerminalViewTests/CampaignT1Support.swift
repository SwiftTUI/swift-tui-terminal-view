import Foundation
import Testing

/// Preserve an unmarked reproduction while guarding only confirmed assertions.
func t1Known(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_T1_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}
