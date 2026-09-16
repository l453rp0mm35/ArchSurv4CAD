# AS4CAD

**AS4CAD** is an open source AutoLISP port of the [ArchSurv4QGIS (AS4QGIS)](https://github.com/l453rp0mm35/ArchSurv4QGIS) **Synthesis** workflow, bringing automated archaeological feature drawing directly into AutoCAD and BricsCAD - no QGIS round-trip required to get from a raw total-station/GNSS export to classified, attributed, styled CAD geometry.

It reads the same delimited-text exports and the same 10-character ArchSurv point-ID scheme as AS4QGIS Synthesis, and builds a fully classified drawing: points as styled, attributed block symbols; lines and polygons as true 3D geometry; posthole buffers as generated circles; everything carrying the same attribute set AS4QGIS would produce, stored both as Xdata and as visible/editable block attributes.

> AS4CAD covers the **Synthesis** side of the AS4QGIS suite (point data → classified drawing). `AS4TAGFROMLAYER` additionally covers the same ground as AS4QGIS's **Psyche** - adding the same attribute structure to pre-existing line/polygon geometry - though it derives the ID/code from the object's layer name rather than a point measurement.

Free, source-available tooling matters in archaeology as much as in any other publicly funded science: excavation budgets rarely include commercial GIS/CAD-automation licenses, students and volunteer diggers need to be able to run the same workflow their supervisor uses without a paywall in the way, and results built on an openly inspectable pipeline are easier for anyone else to verify, adapt, or build on. AS4QGIS and AS4CAD are released under the MIT license specifically so that any excavation, institution or individual researcher can use, modify and redistribute them freely.

---

## What is ArchSurv?

ArchSurv works on the basis of point data exported as delimited text from a surveying device. It processes 10-character pointID-strings, e.g. `0001A03001`:

- feature `0001`
- line container / point property `A`
- shape type `03`
- sequence number `001`

Depending on the entered shape type, Synthesis (and AS4CAD) classifies each measurement into one of four output categories: **polygons**, **polylines**, **pointdata**, **vertices**.

### Shape type spectrum

| Category | Codes |
|---|---|
| feature | `01` heights, `02` polyline, `03` polygon, `33` closed polyline (rendered as a line, not a polygon) |
| sample | `51` sample point, `52` sample polyline, `53` sample polygon |
| posthole | `06` / `61` buffered point measurement |
| finds | `71` find point, `72` find polyline, `73` find polygon |
| 3D markers | `81` 3D marker point (e.g. photogrammetry target) |
| trench | `91` fixed point, `92` trench polyline, `93` trench polygon |
| section nails | `00` section nail point |

### ArchSurv-Code guide

A point_ID follows the scheme `XXXXYZZ001`, entered into the point ID field of the surveying device:

| Segment | Length | Meaning |
|---|---|---|
| `XXXX` | 4 digits | feature number (up to 9999 features) |
| `Y` | 1 letter | line container (separates multiple lines/polygons of the same feature) or point property |
| `ZZ` | 2 digits | shape type |
| `001` | 3 digits | sequence number, starting at 1 for every new line |

### Point properties

Sample, posthole and find point measurements can carry an additional property in the 5th character of the string.

- **sample** (`51`): `A` = undeclared, `B` = brick-sample, `C` = c14-sample, `D` = dendro-sample, `E`-`J` = soil sample variants, `K`-`Z` = excav.specif.meth.1-16
- **posthole** (`61`/`06`): `A` = 1 cm diameter ... `Z` = 26 cm diameter
- **finds** (`71`): `A` = undeclared, `B` = metal, `C` = coin, `D` = stone object, `E` = silex, `F` = iron, `G` = glass, `H` = homo, `I` = animal bones, `J`-`O` = further material categories, `P`-`Y` = excav.specif.cat.1-10, `Z` = misc

AS4CAD resolves this table automatically and stores the result in the `f_ma/s_me` (Xdata) / `F_MA_S_ME` (block attribute) field, exactly as AS4QGIS does.

### Example codes

| point_ID | Meaning |
|---|---|
| `0037A03005` | 5th point of a polygon around feature 37 |
| `0037A02027` | 27th point of a polyline within feature 37 |
| `0037B02003` | 3rd point of a *second* polyline within feature 37 |
| `0123C51056` | 56th sample of the excavation, a C14 sample from feature 123 |
| `0061D61003` | 3rd posthole measurement of feature 61, 4 cm diameter |
| `0467E71537` | 537th find, from feature 467, material "silex" |
| `0404A81008` | 8th 3D marker of feature 404 |
| `0000A91027` | Fixed point 27 (pseudo-feature `0000`/`9999` recommended for fixed points, trench boundaries, unstratified finds) |
| `0738A33002` | 2nd point of a closed polyline (rendered as a line, not filed as a polygon) |

### Best practices for field data collection

- Different lines can never share the same ArchSurv string.
- Closed lines (`03`) should describe the *largest* extent of a feature; upper, receding edges should be measured as open polylines (`02`) instead.
- Find/sample lines (`72`/`73`/`52`/`53`) should be supplemented with a point measurement (`71`/`51`) within the same line.
- Plughole measurements (`61`) use a single central point; group them by diameter letter for survey efficiency.
- Excavation boundaries (`92`/`93`) are ideally measured under feature `0000` or `9999`, with the trench name in the code field.
- Use `33` for a closed line that should render as a polyline rather than a polygon.
- **AS4CAD-specific:** section nail measurements (`00`) sharing the same feature+container are connected into a polyline automatically, in addition to receiving their own point symbol.

---

## Installation

AS4CAD is a single file, `AS4CAD.lsp`. No installer, no dependencies beyond a LISP-capable CAD application.

### AutoCAD

1. Type `APPLOAD` on the command line.
2. Click the folder icon next to **Startup Suite**, then the **+** button, and select `AS4CAD.lsp`.
3. Close the dialogs. AS4CAD now loads automatically every time AutoCAD starts, in every drawing.

If you only want it for the current session, use `APPLOAD` → **Load** instead of adding it to the Startup Suite.

If AutoCAD's security settings block the file with an "untrusted location" warning, add the folder containing `AS4CAD.lsp` to **Options → System → Security Options → Trusted Locations** (only add folders you control).

### BricsCAD

1. Type `APPLOAD` on the command line - BricsCAD uses the same command name.
2. Click **Add application file**, select `AS4CAD.lsp`.
3. Tick the **Autoload** checkbox in its row.
4. Close the dialog. The choice is stored in `appload.dfs` and applied on every future startup.

Alternatively, place `(load "path/to/AS4CAD.lsp")` in an `on_start.lsp` (once per session) or `on_doc_load.lsp` (once per drawing) file, located in a folder that is on BricsCAD's support file search path (`SRCHPATH`).

### Compatibility

AS4CAD uses only standard AutoLISP and core Visual LISP functions - no ActiveX/COM (`vlax-`/`vla-`), no Express Tools, no DCL dialogs - and creates geometry through plain DXF group codes only. It should run on AutoCAD 2004 and newer (true color and lineweight support), and on any reasonably current BricsCAD version, on Windows and macOS alike. It has not been tested across the full version range; if you rely on a specific older version, verify there first.

---

## Quick start

1. Load `AS4CAD.lsp` (see above).
2. Save your drawing at least once, so project-level settings have somewhere to live (see [Settings & persistence](#settings--persistence)).
3. Optionally run `AS4SETTINGS` to configure the drawing to your liking - or just skip this and use the factory defaults.
4. Run `AS4IMPORT`, select your delimited text file (`.csv`/`.txt`/`.asc`, any of tab/semicolon/comma as separator, auto-detected).
5. Review the command-line summary (features imported per shape type, skipped/invalid lines, split shpcontainers, feature layer count).
6. Use `AS4ZOOM`/`AS4SELECT` any time afterward to jump straight to a feature by its ID or code.
7. Optionally, run `AS4XPORT` at any point to export the data back out for QGIS or any other GIS tool.

---

## Commands

Run `AS4INFO` at any time for a command-line reference of every command below: it lists them all with a letter, then prints a short usage/effect description for whichever letter you type.

### `AS4IMPORT`

Reads an ArchSurv delimited text file and builds the classified drawing.

- **Delimiter auto-detection:** tries tab, then semicolon, then comma; repeated delimiter runs (used by some devices purely for column alignment) are collapsed so they don't shift columns; every field is trimmed.
- **Columns:** `point_ID, x, y, z, code`. A 4-column line (no `code`) is accepted and treated as if `code` were `"-"`.
- **point_ID classification:**
  - A valid 10-character ArchSurv code is parsed and classified per the shape type table above.
  - A point_ID that is *not* a valid ArchSurv code, but consists only of digits plus at least one of `.` `-` `_`, is treated as a **station point** (e.g. a total-station backsight/orientation coordinate) and gets its own symbol automatically.
  - Anything else (wrong length, unrecognized shape type code, too few columns) is skipped and reported, both immediately on the command line and in a summary at the end.
- **Posthole geometry (`61`/`06`):** generates a 32-vertex circular polygon centered on the measured point; diameter from the container letter (`A` = 1 cm ... `Z` = 26 cm). These 32 vertices are synthetic and are not added to the vertices layer.
- **Duplicate shpcontainers:** if the same feature+container+shape-type combination occurs twice in the file (e.g. two people measuring into the same container on a long day), AS4CAD detects the sequence-number reset and splits the points into separate, independent lines/polygons rather than merging them into one geometry that jumps between the two unrelated point sets. Both measurements are always kept in full.
- Ends with `ZOOM Extents` and a full command-line summary.

### `AS4UPDATE`

Re-imports a file without duplicating geometry: removes every object previously imported from *that same file* (matched via the `originfile` attribute), then runs `AS4IMPORT` again. Use this when re-running a corrected/updated export instead of `AS4IMPORT`.

### `AS4SETTINGS`

The only entry point for configuring AS4CAD - a menu with six steps. Type the first letter shown to jump to that step, as many times as needed, in any order, until `X`/eXit:

```
AS4CAD settings [Layerstructure/Vector/Symbol/Text/Export/Default/eXit] <eXit>:
```

#### Layerstructure

Controls where geometry ends up, layer-wise. Asks:

1. **Which field names the per-feature layer** - `IDnum` (plain ID, e.g. `4`), `IDstr` (padded, e.g. `0004`), `IDnumCode`/`IDstrCode` (ID+code), `CodeIDnum`/`CodeIDstr` (code+ID). This choice also decides which "flavour" of plain ID (unpadded number, or padded string) gets used below in modes A/B/E - always without the code, even if this field itself includes one.
2. For each of six point categories (**heights**, **samples**, **finds**, **3D markers**, **section nails**, **fixed points**), one of four placement modes (samples and finds get a fifth):

| Mode | Effect | Example (heights, feature `193`, `IDnum` selected) |
|---|---|---|
| A | own layer, category-prefixed | `as4_heights_193` |
| B | own layer, category-suffixed | `193_heights` |
| C | shares the feature's own layer | `193` (or whatever field #1 produced) |
| D | one collective layer for the whole category | `as4_heights` |
| E *(samples/finds only)* | one layer per individual measurement | `as4_find-37_193` (running number `37`) |

Defaults: heights = C, samples/finds/3D-markers/section-nails = B, fixed points = D.

Trench boundaries (`92`/`93`) always go to a fixed `as4_trench_<code>` layer regardless of this setting, since they are excavation-wide rather than per-feature.

#### Symbol

Vertex marker radius, point symbol scale, and - for the five customizable symbol types (**fixed point**, **station**, **sample**, **find**, **3D marker**) - shape, center marker and colors:

- **Shape:** A = Circle, B = Triangle, C = Square, D = Hexagon
- **Center marker:** A = Crosshair, B = X, C = Dot, D = Circle
- **Colors:** ACI number (1-255) for the outer shape and, separately, for the center marker

Height points and section nails are not covered here - their designs (apex-at-coordinate inverted triangle; crossing-point-at-coordinate X with a vertical shaft) are purpose-built and don't fit the generic "shape + centered marker" model.

**Factory defaults:**

| Type | Shape | Marker | Shape color | Marker color |
|---|---|---|---|---|
| Fixed point | Circle | Crosshair | red | dark grey |
| Station | Circle | Crosshair | yellow | dark grey |
| Sample | Circle | X | brown (true color) | white |
| Find | Circle | X | light blue (true color) | white |
| 3D marker | Circle | X | magenta | white |

#### Text

Label text height and ACI color for all seven labelled symbol types (fixed point, station, sample, find, height, 3D marker, section nail). Height defaults to a smaller size (0.04) to match its deliberately small symbol; all others default to 0.08. Text colors default to matching each symbol's own shape color.

#### Vector

Color (ACI, `0` = ByLayer/no override) and lineweight (mm, `0` = ByLayer/no override) for the five line/polygon groups:

| Group | Shape types | Default color | Default lineweight |
|---|---|---|---|
| Standard | `02` `03` `61` `06` | ByLayer | 0.25 mm |
| Sample | `52` `53` | brown (true color) | ByLayer |
| Find | `72` `73` | light blue (true color) | ByLayer |
| Trench | `92` `93` | dark grey | 0.20 mm |
| Section nail | `00` | ByLayer | ByLayer |

Entering `0` clears an override back to ByLayer - new geometry on that layer then simply takes on the layer's own assigned color/lineweight. Turns on lineweight display (`LWDISPLAY`) automatically, since AutoCAD/BricsCAD hide lineweights in Model Space by default and the change would otherwise be invisible.

#### Export

Default output format for `AS4XPORT`'s Csv step (`Raw`/`Schema`) and default EPSG code for its GeoJson step, so neither has to be typed on every export - still overridable per run.

#### Default

Resets every Layerstructure/Symbol/Text/Vector/Export setting to its factory default, described above.

### `AS4STATUS`

Prints the AS4CAD version and every current setting to the command line.

### `AS4XPORT`

The only entry point for exporting - a menu with two steps:

```
AS4CAD export [Csv/GeoJson/eXit] <eXit>:
```

#### Csv

Writes point symbols back out as a CSV file - the reverse direction, for bringing AS4CAD-generated points back into QGIS (or any other tool that reads a delimited text file) via "Add Delimited Text Layer".

- **Format:** `Raw` (`point_ID,x,y,z,code`, no header, directly re-importable by `AS4IMPORT`) or `Schema` (the full 21-column AS4QGIS `pointdata` set, with header). Default comes from `AS4SETTINGS`' Export step.
- **Selection:** pick objects first to export only those; press Enter with nothing selected to export every point symbol in the drawing instead.
- **Reads actual block attribute values**, not a fresh recomputation from point_ID - so any manual correction made in the Properties palette after import is reflected in the export.
- Line/polygon vertex markers (`as4_vertices`) and the survey-grid blocks (`AS4_GridCross`) are always excluded - only true point-data symbols (fixed/station/sample/find/height/3D-marker/section-nail) are written out.
- `maxH`/`minH` are aggregated across whatever was exported in that run - if you export a partial selection, the range reflects the selection, not necessarily the whole feature.

#### GeoJson

Exports point symbols **and** lines/polygons together in a single GeoJSON file - geometry and the full AS4QGIS attribute set in one, ready to open directly in QGIS.

- **Auto-tags untagged lines first** (the same logic as `AS4TAGFROMLAYER`, run automatically) so lines/polygons drawn or traced without going through `AS4IMPORT` are included rather than silently dropped.
- **Points** carry the full 17-field `pointdata` schema; **lines/polygons** carry the leaner 11-field schema AS4QGIS itself produces for those geometry types (no `shptype_n`, `geom_ID`, or point-only fields).
- Polygons are closed rings (first point duplicated at the end, as GeoJSON requires).
- **Mirror polygons to polylines:** asked before the EPSG prompt, defaulting to `No`. Matches AS4QGIS's own "mirror polygons to polylines" option - when set to `Yes`, every polygon feature (shape types `03`/`53`/`61`/`06`/`73`/`93`) is written twice: once as its normal `Polygon` geometry, and once more as an additional `LineString` feature with the same attributes, useful when a GIS workflow needs the boundary as a line (e.g. for separate symbolization) alongside the filled area. Shape type `33` is not affected - it is already exported as a `LineString` in this system, not a `Polygon`, so mirroring it would just duplicate what it already is.
- **EPSG:** asks each run, defaulting to whatever `AS4SETTINGS`' Export step has stored; embedded as a `crs` member (`urn:ogc:def:crs:EPSG::<code>`).
- **QGIS loads a mixed-geometry GeoJSON as separate Point/LineString/Polygon layers automatically** - if you have AS4QGIS's own `.qml` style files, they can be applied directly to the matching layer (their rule filters key on `shptype`, which matches this export's field names exactly).
- **qgis2threejs tip:** 3D rendering of non-planar polygons (varying Z per vertex, e.g. a real wall outline) can fail to show elevation correctly when the source is GeoJSON, even though the same geometry renders fine from a Shapefile. This appears to be a GeoJSON-driver/triangulation interaction, not a data problem - if you hit it, use QGIS's "Export → Save Features As" to convert the polygon layer to a Shapefile first.

### `AS4TAGFROMLAYER`

Bulk-tags untagged `POLYLINE` entities (lines drawn manually, or traced over a photogrammetry mesh/orthophoto) with AS4QGIS attributes, parsed from their **layer name** instead of a point_ID - e.g. a layer named `193_VF` or `VF_193` is parsed as ID `193`, code `VF`, matching whichever `AS4SETTINGS` Layerstructure field convention is in use.

- Closed polylines become shape type `03` (polygon); open ones become `02` (polyline).
- Container letters auto-increment per ID within the batch to avoid `geom_ID` collisions.
- `originfile` is set to `"manual"`, which protects these objects from `AS4UPDATE`'s file-based cleanup.
- Shows a dry-run summary (including any layer names it couldn't parse) before asking for confirmation.
- Layers already prefixed `as4_` are excluded from candidates, since those are AS4CAD's own managed layers.

### `AS4ZOOM` / `AS4SELECT`

Locate objects by feature ID or code, instead of hunting through layers - matched directly against every object's own block attribute/Xdata, so it works regardless of the current `AS4SETTINGS` Layerstructure configuration and finds point symbols *and* lines/polygons alike.

- Enter a plain integer (e.g. `40`) to match by **ID**, or any other text (e.g. `VF`) to match by **code** (case-insensitive) - or a comma-separated mix of several (e.g. `4,12,VF,FUND`), matching anything satisfying *any* of them.
- `AS4ZOOM` zooms to the combined bounding box of everything found. `AS4SELECT` does the same and also selects the found objects.
- The confirmation line reports a breakdown, e.g. `(3 point symbol(s), 1 line/polygon(s))`.
- The search itself is filtered to INSERT/POLYLINE entities before any attribute is read, and AS4CAD's own non-data blocks (`AS4_Vertex`, `AS4_GridCross`) are skipped before their attribute chain is ever walked - so a large `AS4NET` reference grid doesn't slow these commands down.

### `AS4NET`

The only entry point for the reference survey grid - a menu with two steps:

```
AS4CAD survey grid [Grid/Label/eXit] <eXit>:
```

- **Grid**: pick two corners of the area to cover, then a spacing in metres (e.g. `10` for a 10×10 m grid) and a Z elevation. Places a small cross at every grid intersection that falls on a round coordinate (a multiple of the spacing) within that window, on a dedicated `as4_survey-grid` layer.
- **Label**: select any points (grid crosses, or anything else with a usable insertion point - symbols, circles, plain AutoCAD points) and writes their coordinates next to them as two separate texts on `as4_txt_survey-grid` - `X=...` horizontal, `Y=...` rotated 90° - matching the conventional layout of printed survey grid coordinate labels.

---

## Settings & persistence

Every step of `AS4SETTINGS` writes its choices to a small settings file next to the current drawing (`as4cad_settings.dat`), loaded automatically the next time AS4CAD runs on a drawing from that same folder - so you only configure a project once, not once per session. Each step also offers to save the same choices as a **global default** (`~/.as4cad_settings.dat` in your home directory), used as the starting point for any project that doesn't have settings of its own yet.

If the drawing has never been saved, or the home directory can't be determined, saving at that level is silently skipped - the rest of the command still runs normally.

Every AS4CAD prompt is deliberately kept in English regardless of your AutoCAD/BricsCAD interface language, using the `_.`-prefixed, language-independent form of every underlying command. Yes/No prompts accept either the full word or the English abbreviation (`Y`/`N`) - not `J`/`Ja`/`Nein`, so an answer is never ambiguous between the two languages.

---

## What gets created

Every AS4CAD-managed layer starts with the prefix `as4_`, so they sort together and stay clearly separate from your own project layers:

- **`as4_vertices`** - a small marker (block reference) at every measured point that forms part of a line or polygon
- **`as4_station`**, **`as4_section-nails`**, **`as4_fixed-points`** - fixed layers for those symbol types (unless reassigned via `AS4SETTINGS`' Layerstructure step)
- **`as4_trench_<code>`** - trench boundary lines/polygons, grouped by the code field
- **`as4_survey-grid`** / **`as4_txt_survey-grid`** - reference grid crosses (`AS4NET`'s Grid step) and their coordinate labels (its Label step)
- **`as4_txt_*`** - one label layer per symbol type (`as4_txt_heights`, `as4_txt_samples`, `as4_txt_finds`, `as4_txt_3d-markers`, `as4_txt_section-nails`, `as4_txt_fixed-points`, `as4_txt_station`) plus `as4_txt_ID`, a single "ID" label placed once per feature layer

Point symbols carry a visible **`LABEL`** attribute (running number, or a short prefixed label for fixed/sample/find/3D-marker/section-nail points) plus a set of invisible attributes (`ID`, `IDSTRING`, `CODE`, `SHPTYPE`, `SHPTYPE_N`, `POINT_PROP`, `CONTIN_NR`, `ID_CODE`, `CODE_ID`, `ORIGINFILE`, and `F_MA_S_ME` for samples/finds) - all visible and editable in the standard Properties palette under **Attributes**.

Lines and polygons use true 3D `POLYLINE` entities (not `LWPOLYLINE`, which can't carry a different elevation per vertex) and carry the same attribute set as Xdata under the APPID `AS4QGIS` (`ID`, `IDstring`, `code`, `shptype`, `shptype_n`, `geom_ID`, `ID_code`, `code_ID`, `maxH`, `minH`, `originfile`) - block attributes only exist on block references, so this is Xdata-only for line/polygon geometry.

---

## About this project

AS4CAD reimplements the ArchSurv4QGIS Synthesis logic from scratch in AutoLISP - not a conversion of the original PyQGIS code, but a new implementation of the same point-ID scheme, shape-type spectrum, and attribute set, kept compatible with ArchSurv4QGIS output by design.

The code was written by Claude Sonnet 5 (Anthropic) through iterative, requirement-by-requirement dialogue with the author, an archaeologist and the domain expert behind every design decision in this tool - classification logic, symbol geometry, attribute handling, layer conventions. Disclosed here in the interest of methodological transparency, as archaeological tools generally should be.

---

## License

MIT - see `LICENSE`.
