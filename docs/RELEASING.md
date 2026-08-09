# Releasing Ice

Pushing a version tag runs `.github/workflows/release.yml` on GitHub's
Apple-silicon macOS 26 runner. The workflow builds and tests an arm64 Release
app, packages it in a DMG, and publishes the DMG plus its SHA-256 checksum to
GitHub Releases. No Apple certificate or GitHub secret is required.

The automated build is ad-hoc signed so its app and XPC service retain valid
code signatures, but it is not signed with Developer ID or notarized by Apple.
macOS may require users to approve the app explicitly in System Settings >
Privacy & Security after installing or updating. Privacy permissions may also
need to be granted again after an update. The DMG includes the GPL-3.0 license
and a link to the corresponding tagged source code.

## Publish a release

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project,
then commit and push the change. The tag must be exactly `v` followed by the
app's marketing version:

```sh
git tag -a v0.11.13-sh7ne.2 -m "Ice 0.11.13-sh7ne.2"
git push origin v0.11.13-sh7ne.2
```

The tag push publishes the release automatically. The workflow can also be
started manually from GitHub Actions to retry a tag that already contains the
current release scripts.

For warning-free public distribution, replace the ad-hoc signing stage with a
Developer ID Application certificate and Apple notarization credentials.
Apple Development certificates are suitable for local development but not for
public notarized releases.

GitHub Releases do not currently restore in-app updates. Ice's previous Sparkle
feed belonged to the upstream project and remains disabled until this fork has
its own signed appcast and Sparkle Ed25519 key.
