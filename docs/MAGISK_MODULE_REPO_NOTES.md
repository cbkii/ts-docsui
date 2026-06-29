# Magisk module repository notes

Observed in this repository:

- The real module payload is under `module/`.
- Release packaging zips the contents of `module/` into the ZIP root.
- `module/module.prop` is the source of truth for `id`, `version`, and `versionCode`.
- `versionCode=080` is intentionally preserved in `module.prop` as requested. Release `update.json` emits the numeric equivalent (`80`) because JSON numbers cannot be written with a leading zero.

Engineering policy:

- Do not add `install.sh` to the module ZIP.
- Keep install logic in `customize.sh`, not in `META-INF/com/google/android/update-binary`.
- Keep boot work bounded. `post-fs-data.sh` must stay minimal because that Magisk stage blocks boot.
- Prefer manual diagnostics through Magisk Action or `tools/ts18-saf-deepdiag.sh` rather than automatic boot diagnostics.
- Do not add firmware, MCU, CAN, LCD, BOOT/display or partition flashing files to this repository.
