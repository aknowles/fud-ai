# Notes for Claude

## Getting changes onto TestFlight

Xcode Cloud builds the iOS app and delivers it to TestFlight when `feature/purines-dash`
changes. Its workflow and start condition live in App Store Connect, not in this repo;
`ios/ci_scripts/ci_post_clone.sh` only adjusts signing for those builds.

- Do iOS work on top of `feature/purines-dash`, not `main` (that branch has the health
  profile, purines and related work that isn't on `main`).
- When the work is done, push it to `feature/purines-dash` as well as your own branch, so a
  TestFlight build starts. Fast-forward only: never force-push or rewrite that branch. If it
  has moved, rebase your commits onto it first.
- A commit whose message contains `[ci skip]` does not start a build; use it for docs-only changes.
- No macOS or Xcode is available in cloud sessions, so builds and tests can't be run here.
  Say so when reporting, and let the Xcode Cloud build be the check.
