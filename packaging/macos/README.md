# Jotley Mac installer

The direct-download release uses a 720 × 520-point Finder window with a 720 × 460-point purple background, room for Finder's title/status chrome, 104-point icons and manually saved icon positions. Jotley sits at `(195, 230)` on the left; the real `/Applications` shortcut sits at `(525, 230)` on the right. A light dotted border and arrow explain the drag-to-install step. Instructions explain ejecting the disk and opening the installed app.

The artwork is original, deterministic UI artwork rendered by `generate-background.py`. The committed PNGs are 1x/2x source exports, and `background.tiff` includes both representations for Retina displays. Regenerating it requires macOS, Pillow and the system SF font; CI uses the committed TIFF and does not download fonts or generate artwork.

## Packaging and verification

`scripts/release-mac.sh` copies the TIFF into `Jotley.app/Contents/Resources/JotleyInstallerBackground.tiff` **before final app signing**. `scripts/package-mac-dmg.py` uses pinned build-only Python tools to create the disk image and its `.DS_Store`, then records a Finder background alias to that signed resource. This leaves no stray `.background` image or directory at the disk root, even when Show Hidden Files is enabled. Packaging does not modify the signed app or set FinderInfo on it.

The package verifier mounts the actual compressed image read-only and checks:

- App and Applications shortcut, window dimensions, icon view, positions, no automatic sorting and embedded background reference.
- Exact background bytes, bundle file hashes/permissions/symlink targets, and the copied app's strict deep code signature.
- Absence of root-level background files/directories. Finder's `.DS_Store` remains necessary layout metadata and is not a user-facing installer item.

The same checks run again after signing, notarizing and stapling the DMG. The release retains Developer ID signing, Apple notarization, the production app identity and the existing signed Sparkle feed. `installer-layout.json` accompanies the CI artifact; no signing credentials are included.

For a layout check against an already prepared and signed app:

```sh
python3 -m venv /tmp/jotley-dmg-tools
/tmp/jotley-dmg-tools/bin/python -m pip install -r packaging/macos/requirements.txt
/tmp/jotley-dmg-tools/bin/python scripts/package-mac-dmg.py \
  --app /path/to/Jotley.app --output /tmp/Jotley-Installer-Check.dmg
```

Use Python 3.12 or newer. Choose an output path that does not exist. The app must already contain the exact committed background resource and be signed after adding it; the package command preserves it. This is a packaging check, not a replacement for the CI signing/notarization workflow. Finder may retain user-selected status-bar or hidden-file preferences; the layout accommodates its chrome without changing global preferences.

## References and inspiration

- [dmgbuild settings](https://dmgbuild.readthedocs.io/en/latest/settings.html): saved window geometry, backgrounds and icon positions.
- [dmgbuild upstream](https://github.com/dmgbuild/dmgbuild): disk image construction without scripting Finder.
- [DMGKit's installer design example](https://dmgkit.app/blog/how-to-custom-design-a-macos-app-installer.html): familiar app-on-left, Applications-on-right installation flow. No external artwork was copied.

The Python packaging dependencies are build tools and are not bundled into the app. Jotley's original artwork and scripts retain the repository's source-available license; existing application dependency notices remain unchanged.
