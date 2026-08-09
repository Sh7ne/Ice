# Releasing Ice

Pushing a version tag runs `.github/workflows/release.yml` on GitHub's
Apple-silicon macOS 26 runner. The workflow builds the Release configuration,
runs the XPC smoke test, signs every executable with Developer ID, notarizes the
app with Apple, staples the ticket, and publishes `Ice.zip` plus its SHA-256
checksum to GitHub Releases.

## Apple requirements

A public macOS release requires a paid Apple Developer Program membership and
a `Developer ID Application` certificate. The `Apple Development` certificate
used by local builds is not valid for public notarized distribution.

Create a protected GitHub environment named `release`, then add these secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64-encoded `.p12` containing the Developer ID certificate and private key |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used when exporting the `.p12` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | Base64-encoded App Store Connect `.p8` private key |

The workflow is configured for Apple Team `AMHB5QVH4B`. If the release
certificate belongs to another team, update `APPLE_TEAM_ID` in the workflow and
the target development teams in the Xcode project.

On macOS, encode the two binary secret values without writing them into shell
history:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

Paste each clipboard value into its matching GitHub environment secret. Keep
the original certificate, private key, and passwords outside the repository.

## Publish a release

Merge the workflow into the commit you intend to tag. GitHub only exposes the
manual `workflow_dispatch` button after the workflow exists on the default
branch.

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project,
then commit and push the change. The tag must be exactly `v` followed by the
app's marketing version:

```sh
git tag -a v0.11.13-sh7ne.2 -m "Ice 0.11.13-sh7ne.2"
git push origin v0.11.13-sh7ne.2
```

The tag push publishes the release automatically. The workflow can also be
started manually from GitHub Actions with an existing tag, which is useful for
retrying a failed build.

GitHub Releases do not currently restore in-app updates. Ice's previous Sparkle
feed belonged to the upstream project and remains disabled until this fork has
its own signed appcast and Sparkle Ed25519 key.
