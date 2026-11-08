# Tile Markers

Mark ground tiles in RuneScape.

## Use

- Set marker defaults and manage presets in settings. Right-click the world map button for bulk actions.
- Manage up to 10 styles from the presets panel or **Customize Tile**.
- Hold the tilemarking keybind (default **Ctrl+Shift**) and right-click a marked tile to choose **Apply tile style** above **Cancel**. Unmarked tiles keep **Mark tile**. Edit preset tiles in preset edit mode.

## Preset hub

Open the full-width **Preset hub** button in the presets panel to browse community submissions from the [RuneScape Wiki](https://runescape.wiki/w/Special:Bucket?bucket=tilemarkerpreset).

- Search titles, authors, or source pages; filter by author. Filters and pagination work locally.
- A borderless list uses alternating background rows for each preset's name and author, without source-page paths. Each page contains up to 25 entries; scroll within the list or use the arrows beside the centered page indicator. Wheel scrolling moves one entry at a time, while filters and pagination stay fixed.
- **Import** saves and enables a preset using the existing preset importer without resetting your scroll position. Only that submission changes to **Added** for the rest of the hub visit, including after a catalogue refresh. Entries from different authors or source pages remain independently importable even when their names and encoded markers are identical.
- Enable the plugin's optional **HTTP access** permission to browse wiki presets. Without it, the full-width hub button is disabled; hover it for a tooltip explaining that `httpAccess` must be enabled. Hovering does not enable the button or make a request. Local tile markers, saved presets, and token imports work without the permission.
- No wiki request runs until the hub is opened. Successful results are cached for the plugin session; closing and reopening the hub reuses them.
- **Refresh** explicitly reloads the catalogue. It stays disabled while a request is running or until five minutes of client runtime have passed since the last attempt, including failed attempts. It re-enables automatically without making a request or resetting your scroll position. There is no background polling.
- Failed refreshes retain cached results. Status messages, request/permission errors, and import feedback are centered above the search bar. At the 5,000-result API limit, the hub warns that more submissions may exist.
