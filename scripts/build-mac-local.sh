#!/bin/zsh
# Permission testing needs a certificate-backed identity that survives rebuilds.
# Ad-hoc/unsigned compile checks can still use the documented xcodebuild command.
set -euo pipefail
if (( $# > 1 )) || [[ -n "${1:-}" && "$1" != --check-signing ]]; then
  print -u2 'Usage: scripts/build-mac-local.sh [--check-signing]'
  exit 1
fi
task_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_identity="${JOTLEY_MAC_SIGNING_IDENTITY:?Set JOTLEY_MAC_SIGNING_IDENTITY to an installed Apple signing certificate name or SHA-1.}"
task_team="${JOTLEY_MAC_SIGNING_TEAM:?Set JOTLEY_MAC_SIGNING_TEAM to the certificate's Apple team ID.}"
task_configuration="${JOTLEY_MAC_CONFIGURATION:-Release}"
task_derived_data="${JOTLEY_MAC_DERIVED_DATA:-/Volumes/Expand/Codex Media/jotley-local-signed-build}"
task_keychain="$HOME/Library/Keychains/login.keychain-db"
if [[ "$task_identity" == '-' || "$task_configuration" != (Debug|Release) ]]; then
  print -u2 'Use an Apple certificate and Debug or Release; ad-hoc signing cannot preserve privacy grants across changed builds.'
  exit 1
fi
task_identity="$(python3 "$task_repo_root/scripts/signing_identity.py" "$task_identity")"
if [[ "${1:-}" == --check-signing ]]; then
  print "Signing preflight passed using login keychain: $task_identity"
  exit 0
fi
if [[ ! -d /Volumes/Expand ]]; then
  print -u2 'Expand is not mounted. Mount it before building; generated files must stay on Expand.'
  exit 1
fi
export TMPDIR="/Volumes/Expand/Codex Media/jotley-local-signed-build-tmp"
mkdir -p "$TMPDIR"
xcodebuild -project "$task_repo_root/Jotley.xcodeproj" -scheme Jotley \
  -configuration "$task_configuration" -destination 'platform=macOS' \
  -derivedDataPath "$task_derived_data" CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="$task_identity" \
  OTHER_CODE_SIGN_FLAGS="--keychain \"$task_keychain\"" \
  DEVELOPMENT_TEAM="$task_team" build
task_app="$task_derived_data/Build/Products/$task_configuration/Jotley.app"
codesign --verify --strict "$task_app"
task_signature="$(codesign -dv --verbose=4 "$task_app" 2>&1)"
if [[ "$task_signature" != *"TeamIdentifier=$task_team"* || "$task_signature" == *'Signature=adhoc'* ]]; then
  print -u2 'The app does not have the requested stable Apple signing identity. Do not use it for permission testing.'
  exit 1
fi
print "Signed local app: $task_app"
codesign -dr - "$task_app"
