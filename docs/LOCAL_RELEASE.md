# Local Jotley releases

Build and test on the Mac by default. The private maintainer repository retains its GitHub Actions workflows for cloud runs when needed. Local commands still use Apple for TestFlight and notarization, Cloudflare R2 for installer storage, and the website's Git integration for Vercel production.

Use the existing private production signing configuration for each platform. It must specify the intended version and build number and point to the existing signing entitlements and profiles. For iOS, use the existing App Store export options. Keep private configuration outside Git. Set `JOTLEY_PACKAGES_PATH` only when reusing a directory with the pinned packages already resolved.

## iPhone and iPad

```sh
zsh scripts/release-local.sh ios "$BUILD" "$IOS_SIGNING_CONFIG" "$IOS_OUTPUT" "$IOS_EXPORT_OPTIONS"
python3 scripts/release-local-delivery.py testflight "$IOS_OUTPUT/export/Jotley-iOS.ipa"
```

Use a fresh output directory under `/Volumes/Expand`. Run the simulator and model checks before uploading. The delivery command verifies processing and access for the internal TestFlight group. Use `--resume` after Apple accepts an upload if you only need to check processing and group access.

## Mac

```sh
zsh scripts/release-local.sh mac "$BUILD" "$MAC_SIGNING_CONFIG" "$MAC_OUTPUT"
python3 scripts/release-local-delivery.py mac-stage "$DMG" \
  --app "$MAC_OUTPUT/Jotley.app" --sign-tool "$SPARKLE_SIGN_UPDATE" \
  --r2-endpoint "$JOTLEY_R2_ENDPOINT" --output "$WEBSITE_ASSETS" \
  --description "$RELEASE_NOTES"
```

Set `JOTLEY_MAC_RELEASE_IDENTITY` to your installed Developer ID Application identity. The packaging Python needs `dmgbuild`, `ds_store`, and `mac_alias`. Set `JOTLEY_PACKAGING_PYTHON` to its Python executable if using a virtual environment. The build command verifies the signatures, notarization staples, Gatekeeper assessment, and mounted installer layout.

The delivery command reads `JOTLEY_SPARKLE_EDDSA_PRIVATE_KEY` from Bitwarden Secrets Manager. For an authorized cloud signing run, pass its `--signature` artifact in place of `--sign-tool`. Both paths check the signature against the public key embedded in the signed app. The immutable R2 object is verified over HTTPS before the command prepares `appcast.xml` and `mac-release.json`. Review those files before updating the website's `public/` directory and publishing from the production branch.

The commands use `bws` for credentials. `JOTLEY_ASC_SECRET_PREFIX` can select a different Apple team credential set. It defaults to the existing authorized team credential prefix for Jotley's local releases.
