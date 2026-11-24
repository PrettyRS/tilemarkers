# Tile Markers

Mark ground tiles in RuneScape.

## Use

- Set marker defaults and manage presets in settings. Right-click the world map button for bulk actions.
- Manage up to 10 styles from the presets panel or **Customize Tile**.
- Hold the tilemarking keybind (default **Ctrl+Shift**) and right-click a marked tile to choose **Apply tile style** above **Cancel**. Unmarked tiles keep **Mark tile**. Edit preset tiles in preset edit mode.

## Preset hub

The plugin offers an optional preset hub for browsing and importing community-submitted tile marker presets from the [RuneScape Wiki](https://runescape.wiki/w/Guide:Tilemarkers). To access it, grant the plugin `httpAccess` permission and open the preset hub from the presets panel.

## Releases

Set `version` in `plugin.json` and open a `release/<version>` PR against `main` (for example, `release/1.4.0`). The version check accepts an optional `v` prefix on the branch. Merging publishes the unprefixed tag at the merge commit, with the PR body as release notes.

Pushing a version tag or publishing a GitHub release also builds and uploads `TileMarkers-<tag>.zip`. The packaged manifest uses the tag version and PrettyUI's mod.io ID; the development manifest is unchanged. To build locally:

```sh
python3 .github/scripts/release.py package v1.4.0 TileMarkers-v1.4.0.zip
```