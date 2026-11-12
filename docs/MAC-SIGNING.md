# Local Mac signing

Local certificate-backed builds use `~/Library/Keychains/login.keychain-db` explicitly. They never search System as a fallback, unlock a keychain, edit its ACL, import/export a private key or change global keychain settings. A missing, invalid, revoked, ambiguous or wrong-class identity stops before Xcode signs anything.

Choose the correct certificate:

- **Apple Development**: local development, with an appropriate development provisioning profile.
- **Developer ID Application**: direct-download Mac distribution through the website, with the matching Developer ID profile for restricted capabilities.
- **Apple Distribution**: Mac App Store distribution. It is not a replacement for Developer ID in a website release.

Use an exact identity name or SHA-1 fingerprint when more than one matching certificate exists. The identity must include its private key in login and have the user's intended codesign authorization. Certificate metadata discovery alone does not prove private-key access is authorized.

Read-only preflight, without building or signing:

```sh
JOTLEY_MAC_SIGNING_IDENTITY='Developer ID Application: Your Team (TEAMID)' \
JOTLEY_MAC_SIGNING_TEAM='TEAMID' \
zsh scripts/build-mac-local.sh --check-signing
```

Remove `--check-signing` only after the signing owner has verified any pending keychain migration. Build products and temporary data default to Expand. Set `JOTLEY_MAC_DERIVED_DATA` to a separate Expand folder if needed. The build uses the resolved certificate fingerprint and passes `--keychain` to codesign through Xcode, then verifies the final app's team and signature.

`scripts/configure-signed-build.py macos` also preflights login before writing a private configuration. Development selects Apple Development; production selects Developer ID Application. Set `--mac-signing-kind app-store` explicitly for a Mac App Store configuration, or `--signing-identity` for an exact certificate. Mac configurations default to Manual signing and include the explicit login keychain flag. iOS retains its Apple Development/Apple Distribution selection and Automatic default; Mac-only options are rejected for iOS. Provisioning and the existing private release pipeline remain separate.

Use `--mac-profile` for an existing manually managed profile. For an existing Xcode-managed development profile, set `--environment development --signing-style Automatic` and omit `--mac-profile`; Xcode selects the matching local profile. Do not pass `-allowProvisioningUpdates` unless profile changes are intended and authorized.

Use `--isolated-local-test` for a development-signed `Jotley Test` build with Sign in with Apple and a separate note library. It keeps the provisioned bundle identifier, disables iCloud sync and Sparkle, and stores notes under `JotleySignedLocalTest`. App preferences and the support login may still share that identifier, so quit the installed Jotley app before opening this test build. Do not use this mode for website distribution.

If a check reports a missing identity, stop and resolve the existing identity's login-keychain availability with the signing owner. Do not retry signing against System or create a new identity as a workaround. Apple's [Developer Technical Support](https://developer.apple.com/forums/thread/793244) confirms that native Sign in with Apple is unavailable to Developer ID apps. The configuration generator therefore rejects that entitlement for website distribution; a browser-based sign-in flow is needed before a public Mac build. The development-signed local test can use the existing native capability.
