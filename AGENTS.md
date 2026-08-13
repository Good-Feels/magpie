# Repository Notes

- Remove stale code, docs, and planning notes once they are superseded or implemented so the repository does not accumulate confusing dead material.
- Never replace or install over `/Applications/Magpie.app` during development or release work. The installed production copy is updated only through Magpie's published Sparkle update.
- A production release means bumping the version/build, creating the signed and notarized release artifacts, publishing the GitHub release, and updating the signed Sparkle appcast according to `RELEASE.md`. Merely launching a signed app from `dist/` is not a release.
