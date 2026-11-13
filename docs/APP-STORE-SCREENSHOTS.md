# Jotley App Store screenshots

The capture script runs the native app with an isolated library and localized sample notes. It exports opaque PNGs into App Store Connect locale folders. Capture iPhone 17 Pro, iPhone 17 Pro Max, 13-inch iPad Pro, and Mac. The mobile exports are 1206 × 2622, 1320 × 2868, and 2064 × 2752. The native Mac window uses the app's 1080 × 720 point default. The script saves that 3:2 window in `mac-3x2` and centers it on Apple's required 16:10 canvas at 1440 × 900 in `store`.

Boot the dedicated simulators in Xcode. Check their UDIDs with `xcrun simctl list devices booted`. Run from the repository root with Xcode and ImageMagick installed and Expand mounted.

```sh
output="/Volumes/Expand/Codex Media/jotley-store-$(date +%Y%m%d-%H%M)"
python3 scripts/capture-app-store.py iphone "$output/iphone" --udid IPHONE_PRO_UDID
python3 scripts/capture-app-store.py iphone-large "$output/iphone-large" --udid IPHONE_PRO_MAX_UDID
python3 scripts/capture-app-store.py ipad "$output/ipad" --udid IPAD_PRO_UDID
python3 scripts/capture-app-store.py mac "$output/mac"
```

Repeat `--locale` to capture a subset. Use `--xctestrun` to reuse a compatible build-for-testing output. On Mac, run subsets sequentially if XCTest loses the app connection during repeated relaunches. The Mac screenshot fixture displays the title without keyboard focus so it cannot be captured with selected text. The capture results and logs sit alongside the exported files.

In [Jotley’s App Store Connect distribution page](https://appstoreconnect.apple.com/apps/6746770199/distribution), choose the editable platform version and the language, then open the media manager. Upload the ordered PNGs for that language into the matching display slot. An account with access to version localizations and screenshots can automate this with Apple’s [asset upload API](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect).
