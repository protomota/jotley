#!/bin/zsh
# Permission testing needs a certificate-backed identity that survives rebuilds.
# Ad-hoc/unsigned compile checks can still use the documented xcodebuild command.
set -euo pipefail
task_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_identity="${JOTLEY_MAC_SIGNING_IDENTITY:?Set JOTLEY_MAC_SIGNING_IDENTITY to an installed Apple signing certificate name or SHA-1.}"
task_team="${JOTLEY_MAC_SIGNING_TEAM:?Set JOTLEY_MAC_SIGNING_TEAM to the certificate's Apple team ID.}"
task_configuration="${JOTLEY_MAC_CONFIGURATION:-Release}"
task_derived_data="${JOTLEY_MAC_DERIVED_DATA:-$HOME/Library/Developer/JotleyLocalBuild}"
if [[ "$task_identity" == '-' || "$task_configuration" != (Debug|Release) ]]; then
  print -u2 'Use an Apple certificate and Debug or Release; ad-hoc signing cannot preserve privacy grants across changed builds.'
  exit 1
fi
xcodebuild -project "$task_repo_root/Jotley.xcodeproj" -scheme Jotley \
  -configuration "$task_configuration" -destination 'platform=macOS' \
  -derivedDataPath "$task_derived_data" CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="$task_identity" \
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
