# Jotley Mac deployment checklist

Follow this checklist for every Mac release from [jotley.ai](https://jotley.ai/download). The website download and **Check for Updates** must offer the same build before calling a release complete.

## Before publishing

- [ ] Confirm the version, build number, and intended source revision. The build number must be higher than the newest build in the [live update feed](https://jotley.ai/appcast.xml).
- [ ] Build the Mac distribution app with Developer ID and the production Sparkle feed and public key. Verify the app signature, notarization, and installer contents. See [Mac signing](docs/MAC-SIGNING.md).
- [ ] Finalize and staple the DMG before signing its bytes with Sparkle. Use the existing private release workflow or the matching key from Bitwarden Secrets Manager. Verify the Ed25519 signature against the public key in the previous released app. A missing signature blocks publication.
- [ ] Upload the final DMG under its versioned filename. Download it through jotley.ai and compare the complete file size and SHA-256 with the signed DMG.
- [ ] Prepare the website's `public/mac-release.json` and `public/appcast.xml` in the same change. The latest feed entry must match the manifest's version, build, installer URL, and byte count.
- [ ] Run the production website build and `e2e/mac-download.spec.ts` against the candidate. The checks must cover the download button, manifest, feed, and signature. Follow the website repository's [deployment instructions](https://github.com/protomota/jotley-site/blob/main/AGENTS.md).

## After publishing

- [ ] Confirm the production deployment is ready. Check the live [download page](https://jotley.ai/download) and [update feed](https://jotley.ai/appcast.xml) and rerun the Mac download tests against production.
- [ ] In a test installation of the previous public Mac build, use **Check for Updates**. Confirm it offers the new version, installs it, and relaunches into the expected version and build.
- [ ] Record the tested versions, installer checksum, and deployment in the release notes. If either channel fails, report the release as incomplete and resolve the mismatch.
