# AS4CAD

**AS4CAD** is an open source AutoLISP port of the [ArchSurv4QGIS (AS4QGIS)](https://github.com/l453rp0mm35/ArchSurv4QGIS) **Synthesis** workflow, bringing automated archaeological feature drawing directly into AutoCAD and BricsCAD - no QGIS round-trip required to get from a raw total-station/GNSS export to classified, attributed, styled CAD geometry.

It reads the same delimited-text exports and the same 10-character ArchSurv point-ID scheme as AS4QGIS Synthesis, and builds a fully classified drawing: points as styled, attributed block symbols; lines and polygons as true 3D geometry; posthole buffers as generated circles; everything carrying the same attribute set AS4QGIS would produce, stored both as Xdata and as visible/editable block attributes.

> AS4CAD covers the **Synthesis** side of the AS4QGIS suite (point data → classified drawing). It does not currently include a Psyche-equivalent (adding AS4QGIS-style attributes to pre-existing CAD lines/polygons).

---

## What is ArchSurv4QGIS Synthesis?

AS4QGIS Synthesis works on the basis of point data exported as delimited text from a surveying device. It processes 10-character pointID-strings, e.g. `0001A03001`:

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
3. Optionally run `AS4SETLAYER`, `AS4SETSYMBOL`, `AS4SETTEXT`, `AS4SETVECTOR` to configure the drawing to your liking - or just skip this and use the factory defaults.
4. Run `AS4IMPORT`, select your delimited text file (`.csv`/`.txt`/`.asc`, any of tab/semicolon/comma as separator, auto-detected).
5. Review the command-line summary (features imported per shape type, skipped/invalid lines, split shpcontainers, feature layer count).

---

## Commands

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

### `AS4SETLAYER`

Controls where geometry ends up, layer-wise. Asks:

1. **Which field names the per-feature layer** - `IDnum` (plain ID, e.g. `4`), `IDstr` (padded, e.g. `0004`), `IDnumCode`/`IDstrCode` (ID+code), `CodeIDnum`/`CodeIDstr` (code+ID).
2. For each of six point categories (**heights**, **samples**, **finds**, **3D markers**, **section nails**, **fixed points**), one of four placement modes:

| Mode | Effect | Example (heights, feature layer `0193`) |
|---|---|---|
| A | own layer, category-prefixed | `as4_heights_0193` |
| B | own layer, category-suffixed | `0193_heights` |
| C | shares the feature's own layer | `0193` |
| D | one collective layer for the whole category | `as4_heights` |

Defaults: heights = C, samples/finds/3D-markers/section-nails = B, fixed points = D.

Trench boundaries (`92`/`93`) always go to a fixed `as4_trench_<code>` layer regardless of this setting, since they are excavation-wide rather than per-feature.

### `AS4SETSYMBOL`

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

### `AS4SETTEXT`

Label text height and ACI color for all seven labelled symbol types (fixed point, station, sample, find, height, 3D marker, section nail). Height defaults to a smaller size (0.04) to match its deliberately small symbol; all others default to 0.08. Text colors default to matching each symbol's own shape color.

### `AS4SETVECTOR`

Color (ACI, `0` = ByLayer/no override) and lineweight (mm, `0` = ByLayer/no override) for the five line/polygon groups:

| Group | Shape types | Default color | Default lineweight |
|---|---|---|---|
| Standard | `02` `03` `61` `06` | ByLayer | 0.25 mm |
| Sample | `52` `53` | brown (true color) | ByLayer |
| Find | `72` `73` | light blue (true color) | ByLayer |
| Trench | `92` `93` | dark grey | 0.20 mm |
| Section nail | `00` | ByLayer | ByLayer |

Entering `0` clears an override back to ByLayer - new geometry on that layer then simply takes on the layer's own assigned color/lineweight. Turns on lineweight display (`LWDISPLAY`) automatically, since AutoCAD/BricsCAD hide lineweights in Model Space by default and the change would otherwise be invisible.

### `AS4SETDEFAULT`

Resets every AS4SETLAYER/AS4SETSYMBOL/AS4SETTEXT/AS4SETVECTOR setting to its factory default, described above.

### `AS4STATUS`

Prints the AS4CAD version and every current setting to the command line.

---

## Settings & persistence

Every `AS4SET*` command writes its choices to a small settings file next to the current drawing (`as4cad_settings.dat`), loaded automatically the next time AS4CAD runs on a drawing from that same folder - so you only configure a project once, not once per session. Each command also offers to save the same choices as a **global default** (`~/.as4cad_settings.dat` in your home directory), used as the starting point for any project that doesn't have settings of its own yet.

If the drawing has never been saved, or the home directory can't be determined, saving at that level is silently skipped - the rest of the command still runs normally.

---

## What gets created

Every AS4CAD-managed layer starts with the prefix `as4_`, so they sort together and stay clearly separate from your own project layers:

- **`as4_vertices`** - a small marker (block reference) at every measured point that forms part of a line or polygon
- **`as4_station`**, **`as4_section-nails`**, **`as4_fixed-points`** - fixed layers for those symbol types (unless reassigned via `AS4SETLAYER`)
- **`as4_trench_<code>`** - trench boundary lines/polygons, grouped by the code field
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
