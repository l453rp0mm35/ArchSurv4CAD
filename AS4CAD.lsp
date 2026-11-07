;;; ============================================================================
;;; AS4CAD.lsp
;;; ArchSurv4QGIS - CAD port of the Synthesis workflow (AutoLISP / FLISP)
;;; Version 1.3.7
;;;
;;; Reads a delimited text file exported from a survey device, parses the
;;; 10-character ArchSurv point_ID scheme (see AS4QGIS documentation), and
;;; builds classified geometry (points, symbols, polylines, polygons,
;;; posthole circles, vertices, labels) with attribute data attached both
;;; as Xdata (APPID "AS4QGIS", full attribute set) and as a visible block
;;; attribute "LABEL" on every point symbol (short running-number label,
;;; editable via the standard Properties palette).
;;;
;;; Commands:
;;;   AS4IMPORT         - read an ArchSurv text file and build the drawing
;;;   AS4SETTINGS       - the only entry point for configuration; a menu
;;;                       with six steps, jumped to by typing the letter
;;;                       shown:
;;;                       Layerstructure - which field names the per-
;;;                       feature layer, then A/B/C/D prompts deciding,
;;;                       per point category, whether that category's
;;;                       symbols get a prefixed layer, a suffixed layer,
;;;                       share the feature's own layer, or go into one
;;;                       collective layer for that type
;;;                       Vector - color and lineweight for the five
;;;                       line/polygon shape-type groups (feature
;;;                       02/03/61/06, sample 52/53, find 72/73, trench
;;;                       92/93, section 00)
;;;                       Symbol - vertex marker radius, point symbol
;;;                       scale, plus A/B/C/D shape, center marker and
;;;                       color prompts for the five customizable point
;;;                       symbols (fixed/station/sample/find/3D-marker)
;;;                       Text - label text height and ACI color for
;;;                       each of the seven labelled symbol types
;;;                       Export - default output format for AS4XPORT's
;;;                       Csv step (Raw/Schema) and default EPSG code
;;;                       for its GeoJson step
;;;                       Default - resets all settings to factory
;;;                       defaults
;;;   AS4STATUS         - print current settings
;;;   AS4INFO           - lists every AS4CAD command with a letter, then
;;;                       prints a short description (usage + effect) for
;;;                       whichever letter is entered
;;;   AS4TABLE          - links an external table (e.g. a CSV from the
;;;                       excavation database) to the drawing's layers
;;;                       via an ID read out of the layer names (template
;;;                       such as ID_ID_*_*). The file is re-read on
;;;                       every use. Steps: Link / Report / Columns /
;;;                       Filter (several criteria, then select, zoom or
;;;                       isolate) / RGB-via-column (colors the layers
;;;                       from a table column holding color values) /
;;;                       Name (rename layers from the table, with log;
;;;                       reVert) / Info (click an object or type a key) /
;;;                       Back (unisolate, restore colors and visibility) /
;;;                       Unlink
;;;   AS4TAGFROMLAYER   - bulk-tags untagged lines/polygons with AS4QGIS
;;;                       attributes, parsed from their layer name rather
;;;                       than a point_ID (e.g. lines traced over a
;;;                       photogrammetry mesh, organized by layer)
;;;   AS4XPORT          - the only entry point for exporting: a menu with
;;;                       two steps:
;;;                       Csv - writes point symbols out as a CSV file,
;;;                       reading their actual block attribute values
;;;                       (respects manual corrections made after
;;;                       import). Exports only a prior selection if one
;;;                       is made, or every point symbol in the drawing
;;;                       otherwise; line/polygon vertex markers are
;;;                       always excluded. For reopening in QGIS via
;;;                       "Add Delimited Text Layer" (X/Y/Z fields)
;;;                       GeoJson - writes a combined GeoJSON file (point
;;;                       symbols and lines/polygons together, geometry
;;;                       and attributes in one), ready to open directly
;;;                       in QGIS
;;;   AS4ZOOM           - zooms to every object matching a search term.
;;;                       A term containing "*" or "?" is matched as a
;;;                       layer name pattern (wcmatch/Layer Panel style
;;;                       wildcards, any entity type on a matching
;;;                       layer); anything else is a feature ID or code
;;;                       (e.g. "40" or "VF"; auto-detected - plain
;;;                       integers are IDs, anything else is matched as
;;;                       a code, case-insensitive) via block attribute/
;;;                       Xdata, regardless of which layer it is on.
;;;                       Alternatively click an object (zooms to its ID,
;;;                       or code, or - if it has neither - its layer)
;;;                       or press Enter (current layer)
;;;   AS4SELECTXDATA    - like AS4ZOOM's ID/code search, but also
;;;                       selects the found objects; accepts one or
;;;                       several comma-separated IDs/codes at once
;;;                       (e.g. "40" or "4,12,VF,FUND"); alternatively
;;;                       click an object (selects everything with its
;;;                       ID, or its code if it has no ID) or press Enter
;;;                       (all AS4 objects on the current layer)
;;;   AS4SELECTLAYER    - like AS4ZOOM's layer-pattern search, but also
;;;                       selects the found objects; any entity type on
;;;                       a layer matching the pattern(s) (comma-
;;;                       separated for several), not just AS4CAD data
;;;                       objects; alternatively click an object
;;;                       (selects its layer) or press Enter (current layer)
;;;   AS4NET            - the only entry point for the reference survey
;;;                       grid: a menu with two steps:
;;;                       Grid - draws a reference survey grid (small
;;;                       crosses at round coordinates, e.g. every 10 m)
;;;                       over a picked window, on its own
;;;                       as4_survey-grid layer
;;;                       Label - labels selected points with their X/Y
;;;                       coordinates on an as4_txt_survey-grid layer
;;;
;;; All settings (reached via AS4SETTINGS) are automatically saved next to
;;; the current drawing (as4cad_settings.dat in the DWG's folder) and loaded the next time
;;; this script runs in a drawing from that same folder - so they only
;;; need to be set once per project, not once per session. Each command
;;; also offers to save the same choices as a global default
;;; (~/.as4cad_settings.dat), applied as the starting point for any
;;; project that has no settings file of its own yet. If the drawing has
;;; never been saved, or the home directory can't be determined, saving
;;; at that level is skipped.
;;;
;;; point_ID classification:
;;;   - A standard ArchSurv point_ID is exactly 10 characters:
;;;     XXXX (feature, 4 digits) + Y (container/property letter) +
;;;     ZZ (shape type, 2 digits) + 001 (sequence number, 3 digits).
;;;   - point_IDs that are NOT a valid ArchSurv code but consist only of
;;;     digits plus at least one of '.', '-', '_' are treated as free
;;;     station points (e.g. total-station backsight/orientation
;;;     coordinates) and get the station symbol automatically.
;;;   - Shape type '61'/'06' (posthole) generates a 32-vertex circular
;;;     polygon instead of a plain point; the container letter sets the
;;;     diameter (A = 1 cm ... Z = 26 cm), matching the AS4QGIS algorithm.
;;;     These 32 generated vertices are NOT added to the vertices layer,
;;;     since they are synthetic, not measured points.
;;;   - Shape type '00' (section nail) is treated as a line-forming type:
;;;     points sharing the same feature+container form a polyline, and
;;;     each point additionally receives a section-nail symbol.
;;;   - All other shape types follow the standard AS4QGIS Synthesis output
;;;     classification (point / polyline / polygon).
;;;
;;; Layer conventions:
;;;   - Every AS4CAD-managed layer (as opposed to the per-feature layers
;;;     named after the field chosen in AS4SETLAYER) starts with the
;;;     prefix "as4_": the label/text layers (as4_txt_heights,
;;;     as4_txt_samples, as4_txt_finds, as4_txt_section-nails,
;;;     as4_txt_3d-markers, as4_txt_fixed-points, as4_txt_station,
;;;     as4_txt_ID), plus as4_vertices, as4_station, as4_section-nails,
;;;     as4_fixed-points, as4_trench_<code>, and any per-category "A"-mode
;;;     symbol layer from AS4SETLAYER (as4_<category>_<feature>).
;;;   - as4_vertices, as4_station, as4_section-nails, as4_fixed-points and
;;;     as4_trench_<code> hold auxiliary/marker geometry rather than
;;;     per-feature data, so they are fixed names, independent of the
;;;     AS4SETLAYER field choice. Trench boundary lines/polygons (shape
;;;     types 92/93) always go to as4_trench_<code>, where <code> is that
;;;     row's "code" column value.
;;;   - The one-per-feature "ID" label (layer as4_txt_ID) always shows the
;;;     plain feature ID number, regardless of which field is currently
;;;     used to name the per-feature layer itself.
;;;   - Point symbols for height, sample, find, photogrammetry (3D marker),
;;;     section-nail and fixed-point measurements do NOT get an additional
;;;     as4_txt_ID label, since they already carry their own label.
;;;
;;; Geometry notes:
;;;   - Z varies per vertex, so lines/polygons use true 3D POLYLINE entities
;;;     (old-style POLYLINE/VERTEX/SEQEND) rather than LWPOLYLINE, which
;;;     cannot carry a different elevation per vertex.
;;;   - Point symbols are block references built once per AS4IMPORT run
;;;     (defined - or redefined - at the start, so a script update always
;;;     applies, even if a block with the same name already exists in the
;;;     drawing from an earlier run).
;;;   - Symbol colors are set explicitly per part (not ByBlock/ByLayer),
;;;     because each symbol type must always show the same fixed color
;;;     regardless of which layer it ends up on.
;;;   - Every point symbol carries a visible block attribute (tag LABEL)
;;;     showing its running number (or, for fixed/sample/find/3D-marker/
;;;     section-nail points, a short prefixed label) - built with the
;;;     standard INSERT + ATTRIB + SEQEND sequence. It also carries a set
;;;     of further invisible attributes (ID, IDSTRING, CODE, SHPTYPE,
;;;     SHPTYPE_N, POINT_PROP, CONTIN_NR, ID_CODE, CODE_ID, ORIGINFILE,
;;;     and F_MA_S_ME for samples/finds) mirroring its Xdata, so the same
;;;     values are visible and editable in the Properties palette under
;;;     "Attributes". Lines/polygons have no equivalent, since block
;;;     attributes only exist on block references (INSERT), never on
;;;     POLYLINE or other geometry entities - their data lives in Xdata
;;;     only.
;;;
;;; Data quality notes:
;;;   - A line with only 4 columns (point_ID, x, y, z, no code) is
;;;     accepted - it is treated as if a 5th column with the value "-"
;;;     were present, so the "code" attribute simply reads "-" for that
;;;     row. Lines feeding fewer than 4 columns, a point_ID that is
;;;     neither a valid ArchSurv code nor a station ID, or a structurally
;;;     valid point_ID whose shape-type code is not part of the known
;;;     AS4QGIS spectrum, are all skipped and reported (both immediately
;;;     and in a summary) on the command line.
;;;   - If the same feature+container+shape-type combination (shpcontainer)
;;;     appears twice - e.g. two people accidentally measuring into the
;;;     same container on a long day - both measurements are kept in full;
;;;     the sequence-number reset is detected and the points are split
;;;     into separate lines/polygons rather than being merged into one
;;;     geometry that jumps between the two unrelated point sets. This is
;;;     also reported on the command line.
;;;   - AS4IMPORT writes nothing to disk beyond the drawing
;;;     itself; those diagnostic reports are command-line only. The
;;;     AS4SET* settings commands are the one exception - they write the
;;;     small settings file described above.
;;;
;;; Platform notes:
;;;   - No (vl-load-com): that call initializes ActiveX/COM, which is
;;;     Windows-only and unused by this script.
;;;   - Uses only standard AutoLISP and core Visual LISP functions (no
;;;     vlax-*/vla-*/acet-* ActiveX or Express Tools calls, no DCL
;;;     dialogs), and creates geometry through plain DXF group codes only.
;;;     Tested to load and run in AutoCAD and BricsCAD; ZWCAD, GstarCAD
;;;     and ARES Commander (Graebert) implement a compatible AutoLISP
;;;     engine and should also work, though this has not been verified
;;;     firsthand. Applications without any AutoLISP support (e.g.
;;;     DraftSight, QCAD) cannot run this script.
;;; ============================================================================

;; -----------------------------------------------------------------------
;; global settings (defaults kept intentionally small)
;; -----------------------------------------------------------------------
(setq *AS4:VERSION* "1.3.7")
;; true color constants (no exact ACI equivalent) - used as the factory
;; default for sample (brown) and find (light blue) colors throughout
(setq *AS4:TC-BROWN* 9127187)      ;; RGB(139,69,19)
(setq *AS4:TC-LIGHTBLUE* 11393254) ;; RGB(173,216,230)

(if (not *AS4:LAYERFIELD*)   (setq *AS4:LAYERFIELD* "ID"))
(if (not *AS4:VERTEXRADIUS*) (setq *AS4:VERTEXRADIUS* 0.02))
(if (not *AS4:TEXTHEIGHT*)   (setq *AS4:TEXTHEIGHT* 0.08))
(if (not *AS4:SYMBOLSCALE*)  (setq *AS4:SYMBOLSCALE* 0.4))
(setq *AS4:LABELED-LAYERS* '())

;; per-category layer assignment mode, set via AS4SETLAYER:
;;   "A" - own layer, named with a category PREFIX (e.g. heights_<feature>)
;;   "B" - own layer, named with a category SUFFIX (e.g. <feature>_heights)
;;   "C" - shares the per-feature layer with that feature's lines/polygons
;;   "D" - one shared collective layer for every occurrence of that type
(if (not *AS4:MODE-HEIGHTS*)  (setq *AS4:MODE-HEIGHTS* "C"))
(if (not *AS4:MODE-SAMPLES*)  (setq *AS4:MODE-SAMPLES* "B"))
(if (not *AS4:MODE-FINDS*)    (setq *AS4:MODE-FINDS* "B"))
(if (not *AS4:MODE-MARKERS*)  (setq *AS4:MODE-MARKERS* "B"))
(if (not *AS4:MODE-SECTIONS*) (setq *AS4:MODE-SECTIONS* "B"))
(if (not *AS4:MODE-FIXED*)    (setq *AS4:MODE-FIXED* "D"))

;; per-symbol-type appearance, set via AS4SETSYMBOL. Shape is one of
;; "Circle"/"Triangle"/"Square"/"Hexagon"; marker (the centre mark) is one
;; of "Crosshair"/"X"/"Dot"/"Circle". Colors are (group . value) pairs,
;; group 62 = ACI index, group 420 = true color. Height and Section nail
;; keep their own fixed, purpose-built designs and are not covered here.
(if (not *AS4:SHAPE-FIXED*)      (setq *AS4:SHAPE-FIXED* "Circle"))
(if (not *AS4:MARKER-FIXED*)     (setq *AS4:MARKER-FIXED* "Crosshair"))
(if (not *AS4:COLOR-FIXED*)      (setq *AS4:COLOR-FIXED* (cons 62 1)))       ;; red
(if (not *AS4:CROSSCOLOR-FIXED*) (setq *AS4:CROSSCOLOR-FIXED* (cons 62 8))) ;; grey

(if (not *AS4:SHAPE-STATION*)      (setq *AS4:SHAPE-STATION* "Circle"))
(if (not *AS4:MARKER-STATION*)     (setq *AS4:MARKER-STATION* "Crosshair"))
(if (not *AS4:COLOR-STATION*)      (setq *AS4:COLOR-STATION* (cons 62 2)))       ;; yellow
(if (not *AS4:CROSSCOLOR-STATION*) (setq *AS4:CROSSCOLOR-STATION* (cons 62 8))) ;; grey

(if (not *AS4:SHAPE-SAMPLE*)      (setq *AS4:SHAPE-SAMPLE* "Circle"))
(if (not *AS4:MARKER-SAMPLE*)     (setq *AS4:MARKER-SAMPLE* "X"))
(if (not *AS4:COLOR-SAMPLE*)      (setq *AS4:COLOR-SAMPLE* (cons 420 *AS4:TC-BROWN*))) ;; brown
(if (not *AS4:CROSSCOLOR-SAMPLE*) (setq *AS4:CROSSCOLOR-SAMPLE* (cons 62 7)))   ;; white

(if (not *AS4:SHAPE-FIND*)      (setq *AS4:SHAPE-FIND* "Circle"))
(if (not *AS4:MARKER-FIND*)     (setq *AS4:MARKER-FIND* "X"))
(if (not *AS4:COLOR-FIND*)      (setq *AS4:COLOR-FIND* (cons 420 *AS4:TC-LIGHTBLUE*))) ;; light blue
(if (not *AS4:CROSSCOLOR-FIND*) (setq *AS4:CROSSCOLOR-FIND* (cons 62 7)))    ;; white

(if (not *AS4:SHAPE-MARKER3D*)      (setq *AS4:SHAPE-MARKER3D* "Circle"))
(if (not *AS4:MARKER-MARKER3D*)     (setq *AS4:MARKER-MARKER3D* "X"))
(if (not *AS4:COLOR-MARKER3D*)      (setq *AS4:COLOR-MARKER3D* (cons 62 6))) ;; magenta
(if (not *AS4:CROSSCOLOR-MARKER3D*) (setq *AS4:CROSSCOLOR-MARKER3D* (cons 62 7))) ;; white

;; per-shptype-group line/polygon appearance, set via AS4SETVECTOR. Each
;; VCOLOR is a (group . value) color pair or nil (ByLayer, no override);
;; each VLW is a lineweight in hundredths of mm (e.g. 60 = 0.60 mm) or nil
;; (ByLayer, no override).
(if (not *AS4:VCOLOR-FEATURE*) (setq *AS4:VCOLOR-FEATURE* nil))
(if (not *AS4:VLW-FEATURE*)    (setq *AS4:VLW-FEATURE* 25)) ;; 0.25 mm, AutoCAD's common default weight
(if (not *AS4:VCOLOR-SAMPLE*)  (setq *AS4:VCOLOR-SAMPLE* (cons 420 *AS4:TC-BROWN*)))
(if (not *AS4:VLW-SAMPLE*)     (setq *AS4:VLW-SAMPLE* nil))
(if (not *AS4:VCOLOR-FIND*)    (setq *AS4:VCOLOR-FIND* (cons 420 *AS4:TC-LIGHTBLUE*)))
(if (not *AS4:VLW-FIND*)       (setq *AS4:VLW-FIND* nil))
(if (not *AS4:VCOLOR-TRENCH*)  (setq *AS4:VCOLOR-TRENCH* (cons 62 8))) ;; dark grey (was light grey)
(if (not *AS4:VLW-TRENCH*)     (setq *AS4:VLW-TRENCH* 20)) ;; 0.20 mm
(if (not *AS4:VCOLOR-SECTION*) (setq *AS4:VCOLOR-SECTION* nil))
(if (not *AS4:VLW-SECTION*)    (setq *AS4:VLW-SECTION* nil))

;; per-symbol-type label text size and color, set via AS4SETTEXT. Covers
;; all seven labelled symbol types, including Height and Section nail
;; (which AS4SETSYMBOL does not cover for shape/marker, since their
;; geometry is purpose-built - but their labels are ordinary text like
;; every other symbol's). TEXTCOLOR defaults match each symbol's own
;; default color; TEXTSIZE defaults to 0.08 except Height, which stays
;; smaller (0.04) to match its deliberately small symbol.
(if (not *AS4:TEXTSIZE-FIXED*)   (setq *AS4:TEXTSIZE-FIXED* 0.08))
(if (not *AS4:TEXTCOLOR-FIXED*)  (setq *AS4:TEXTCOLOR-FIXED* (cons 62 1)))
(if (not *AS4:TEXTSIZE-STATION*)  (setq *AS4:TEXTSIZE-STATION* 0.08))
(if (not *AS4:TEXTCOLOR-STATION*) (setq *AS4:TEXTCOLOR-STATION* (cons 62 2)))
(if (not *AS4:TEXTSIZE-SAMPLE*)  (setq *AS4:TEXTSIZE-SAMPLE* 0.08))
(if (not *AS4:TEXTCOLOR-SAMPLE*) (setq *AS4:TEXTCOLOR-SAMPLE* (cons 420 *AS4:TC-BROWN*)))
(if (not *AS4:TEXTSIZE-FIND*)  (setq *AS4:TEXTSIZE-FIND* 0.08))
(if (not *AS4:TEXTCOLOR-FIND*) (setq *AS4:TEXTCOLOR-FIND* (cons 420 *AS4:TC-LIGHTBLUE*)))
(if (not *AS4:TEXTSIZE-HEIGHT*)  (setq *AS4:TEXTSIZE-HEIGHT* 0.04))
(if (not *AS4:TEXTCOLOR-HEIGHT*) (setq *AS4:TEXTCOLOR-HEIGHT* (cons 62 250)))
(if (not *AS4:TEXTSIZE-MARKER3D*)  (setq *AS4:TEXTSIZE-MARKER3D* 0.08))
(if (not *AS4:TEXTCOLOR-MARKER3D*) (setq *AS4:TEXTCOLOR-MARKER3D* (cons 62 6)))
(if (not *AS4:TEXTSIZE-SECTION*)  (setq *AS4:TEXTSIZE-SECTION* 0.08))

;; export defaults, set via AS4SETXPORT
(if (not *AS4:XPORT-FORMAT*) (setq *AS4:XPORT-FORMAT* "Raw"))
(if (not *AS4:XPORT-EPSG*)   (setq *AS4:XPORT-EPSG* ""))

(if (not *AS4:TEXTCOLOR-SECTION*) (setq *AS4:TEXTCOLOR-SECTION* (cons 62 8)))

;; Clear any stale commands still defined in this session from an older
;; version of this script (LISP function definitions persist until the
;; CAD application is restarted, so removing a command from this file
;; alone does not remove it from an already-running session).
(setq c:AS4STATION nil)
(setq c:AS4SETTINGS nil)
(setq c:AS4DEFAULT nil)
(setq c:AS4LAYERSET nil)
(setq c:AS4SYMBOLSET nil)
(setq c:AS4SETSYMBOLSTYLE nil)
(setq c:AS4TOGGLELABELS nil)
(setq c:AS4INFO nil)
(setq c:AS4EXPORT nil)
(setq c:AS4POINTEXPORT nil)
(setq c:AS4EXPORTPOINTSCSV nil)
(setq c:AS4POINTEXPORTCSV nil)
(setq c:AS4QGISEXPORT nil)

;; -----------------------------------------------------------------------
;; settings persistence, two levels. LISP variables normally only live
;; for the current session, so without this every setting would have to
;; be re-entered after every restart.
;;   - Project level: saved next to the current drawing (DWGPREFIX), so
;;     it follows that project/folder. Always saved automatically by
;;     AS4SETSYMBOL/AS4SETLAYER.
;;   - Global level: saved in the user's home directory, so it applies to
;;     every project as a fallback default. Only saved when the user
;;     opts in at the end of AS4SETSYMBOL/AS4SETLAYER.
;; On load, global settings are applied first (as the base), then project
;; settings override them if present - so a project's own choices always
;; win over the global default.
;; Best-effort throughout: if a drawing has never been saved, the home
;; directory can't be determined, or a folder is not writable, saving or
;; loading at that level is silently skipped rather than erroring.
;; -----------------------------------------------------------------------
(defun AS4:settings-path ( / d)
  (setq d (getvar "DWGPREFIX"))
  (if (and d (> (strlen d) 0)) (strcat d "as4cad_settings.dat") nil)
)

(defun AS4:home-dir ( / h)
  (setq h (cond ((getenv "HOME")) ((getenv "USERPROFILE")) (t nil)))
  (if (and h (> (strlen h) 0))
    (if (= (substr h (strlen h) 1) "/") h (strcat h "/"))
    nil
  )
)

(defun AS4:settings-global-path ( / h)
  (setq h (AS4:home-dir))
  (if h (strcat h ".as4cad_settings.dat") nil)
)

;; serializes a colorspec (group . value) or nil to a string, and back
(defun AS4:color-to-str (cs) (if cs (strcat (itoa (car cs)) ":" (itoa (cdr cs))) "NIL"))
(defun AS4:str-to-color (s / p)
  (if (= s "NIL") nil
    (progn (setq p (vl-string-search ":" s)) (cons (atoi (substr s 1 p)) (atoi (substr s (+ p 2)))))
  )
)
(defun AS4:num-to-str (n) (if n (itoa n) "NIL"))
(defun AS4:str-to-num (s) (if (= s "NIL") nil (atoi s)))

(defun AS4:save-settings-to (path / f)
  (if path
    (progn
      (setq f (open path "w"))
      (if f
        (progn
          (write-line (strcat "LAYERFIELD=" *AS4:LAYERFIELD*) f)
          (write-line (strcat "VERTEXRADIUS=" (rtos *AS4:VERTEXRADIUS* 2 3)) f)
          (write-line (strcat "TEXTHEIGHT=" (rtos *AS4:TEXTHEIGHT* 2 3)) f)
          (write-line (strcat "SYMBOLSCALE=" (rtos *AS4:SYMBOLSCALE* 2 3)) f)
          (write-line (strcat "MODE-HEIGHTS=" *AS4:MODE-HEIGHTS*) f)
          (write-line (strcat "MODE-SAMPLES=" *AS4:MODE-SAMPLES*) f)
          (write-line (strcat "MODE-FINDS=" *AS4:MODE-FINDS*) f)
          (write-line (strcat "MODE-MARKERS=" *AS4:MODE-MARKERS*) f)
          (write-line (strcat "MODE-SECTIONS=" *AS4:MODE-SECTIONS*) f)
          (write-line (strcat "MODE-FIXED=" *AS4:MODE-FIXED*) f)
          (write-line (strcat "SHAPE-FIXED=" *AS4:SHAPE-FIXED*) f)
          (write-line (strcat "MARKER-FIXED=" *AS4:MARKER-FIXED*) f)
          (write-line (strcat "COLOR-FIXED=" (AS4:color-to-str *AS4:COLOR-FIXED*)) f)
          (write-line (strcat "CROSSCOLOR-FIXED=" (AS4:color-to-str *AS4:CROSSCOLOR-FIXED*)) f)
          (write-line (strcat "SHAPE-STATION=" *AS4:SHAPE-STATION*) f)
          (write-line (strcat "MARKER-STATION=" *AS4:MARKER-STATION*) f)
          (write-line (strcat "COLOR-STATION=" (AS4:color-to-str *AS4:COLOR-STATION*)) f)
          (write-line (strcat "CROSSCOLOR-STATION=" (AS4:color-to-str *AS4:CROSSCOLOR-STATION*)) f)
          (write-line (strcat "SHAPE-SAMPLE=" *AS4:SHAPE-SAMPLE*) f)
          (write-line (strcat "MARKER-SAMPLE=" *AS4:MARKER-SAMPLE*) f)
          (write-line (strcat "COLOR-SAMPLE=" (AS4:color-to-str *AS4:COLOR-SAMPLE*)) f)
          (write-line (strcat "CROSSCOLOR-SAMPLE=" (AS4:color-to-str *AS4:CROSSCOLOR-SAMPLE*)) f)
          (write-line (strcat "SHAPE-FIND=" *AS4:SHAPE-FIND*) f)
          (write-line (strcat "MARKER-FIND=" *AS4:MARKER-FIND*) f)
          (write-line (strcat "COLOR-FIND=" (AS4:color-to-str *AS4:COLOR-FIND*)) f)
          (write-line (strcat "CROSSCOLOR-FIND=" (AS4:color-to-str *AS4:CROSSCOLOR-FIND*)) f)
          (write-line (strcat "SHAPE-MARKER3D=" *AS4:SHAPE-MARKER3D*) f)
          (write-line (strcat "MARKER-MARKER3D=" *AS4:MARKER-MARKER3D*) f)
          (write-line (strcat "COLOR-MARKER3D=" (AS4:color-to-str *AS4:COLOR-MARKER3D*)) f)
          (write-line (strcat "CROSSCOLOR-MARKER3D=" (AS4:color-to-str *AS4:CROSSCOLOR-MARKER3D*)) f)
          (write-line (strcat "VCOLOR-FEATURE=" (AS4:color-to-str *AS4:VCOLOR-FEATURE*)) f)
          (write-line (strcat "VLW-FEATURE=" (AS4:num-to-str *AS4:VLW-FEATURE*)) f)
          (write-line (strcat "VCOLOR-SAMPLE=" (AS4:color-to-str *AS4:VCOLOR-SAMPLE*)) f)
          (write-line (strcat "VLW-SAMPLE=" (AS4:num-to-str *AS4:VLW-SAMPLE*)) f)
          (write-line (strcat "VCOLOR-FIND=" (AS4:color-to-str *AS4:VCOLOR-FIND*)) f)
          (write-line (strcat "VLW-FIND=" (AS4:num-to-str *AS4:VLW-FIND*)) f)
          (write-line (strcat "VCOLOR-TRENCH=" (AS4:color-to-str *AS4:VCOLOR-TRENCH*)) f)
          (write-line (strcat "VLW-TRENCH=" (AS4:num-to-str *AS4:VLW-TRENCH*)) f)
          (write-line (strcat "VCOLOR-SECTION=" (AS4:color-to-str *AS4:VCOLOR-SECTION*)) f)
          (write-line (strcat "VLW-SECTION=" (AS4:num-to-str *AS4:VLW-SECTION*)) f)
          (write-line (strcat "TEXTSIZE-FIXED=" (rtos *AS4:TEXTSIZE-FIXED* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-FIXED=" (AS4:color-to-str *AS4:TEXTCOLOR-FIXED*)) f)
          (write-line (strcat "TEXTSIZE-STATION=" (rtos *AS4:TEXTSIZE-STATION* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-STATION=" (AS4:color-to-str *AS4:TEXTCOLOR-STATION*)) f)
          (write-line (strcat "TEXTSIZE-SAMPLE=" (rtos *AS4:TEXTSIZE-SAMPLE* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-SAMPLE=" (AS4:color-to-str *AS4:TEXTCOLOR-SAMPLE*)) f)
          (write-line (strcat "TEXTSIZE-FIND=" (rtos *AS4:TEXTSIZE-FIND* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-FIND=" (AS4:color-to-str *AS4:TEXTCOLOR-FIND*)) f)
          (write-line (strcat "TEXTSIZE-HEIGHT=" (rtos *AS4:TEXTSIZE-HEIGHT* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-HEIGHT=" (AS4:color-to-str *AS4:TEXTCOLOR-HEIGHT*)) f)
          (write-line (strcat "TEXTSIZE-MARKER3D=" (rtos *AS4:TEXTSIZE-MARKER3D* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-MARKER3D=" (AS4:color-to-str *AS4:TEXTCOLOR-MARKER3D*)) f)
          (write-line (strcat "TEXTSIZE-SECTION=" (rtos *AS4:TEXTSIZE-SECTION* 2 3)) f)
          (write-line (strcat "TEXTCOLOR-SECTION=" (AS4:color-to-str *AS4:TEXTCOLOR-SECTION*)) f)
          (write-line (strcat "XPORT-FORMAT=" *AS4:XPORT-FORMAT*) f)
          (write-line (strcat "XPORT-EPSG=" *AS4:XPORT-EPSG*) f)
          (close f)
        )
      )
    )
  )
)
(defun AS4:save-settings () (AS4:save-settings-to (AS4:settings-path)))
(defun AS4:save-settings-global () (AS4:save-settings-to (AS4:settings-global-path)))

(defun AS4:apply-setting (key val)
  (cond
    ((= key "LAYERFIELD") (setq *AS4:LAYERFIELD* val))
    ((= key "VERTEXRADIUS") (setq *AS4:VERTEXRADIUS* (atof val)))
    ((= key "TEXTHEIGHT") (setq *AS4:TEXTHEIGHT* (atof val)))
    ((= key "SYMBOLSCALE") (setq *AS4:SYMBOLSCALE* (atof val)))
    ((= key "MODE-HEIGHTS") (setq *AS4:MODE-HEIGHTS* val))
    ((= key "MODE-SAMPLES") (setq *AS4:MODE-SAMPLES* val))
    ((= key "MODE-FINDS") (setq *AS4:MODE-FINDS* val))
    ((= key "MODE-MARKERS") (setq *AS4:MODE-MARKERS* val))
    ((= key "MODE-SECTIONS") (setq *AS4:MODE-SECTIONS* val))
    ((= key "MODE-FIXED") (setq *AS4:MODE-FIXED* val))
    ((= key "SHAPE-FIXED") (setq *AS4:SHAPE-FIXED* val))
    ((= key "MARKER-FIXED") (setq *AS4:MARKER-FIXED* val))
    ((= key "COLOR-FIXED") (setq *AS4:COLOR-FIXED* (AS4:str-to-color val)))
    ((= key "CROSSCOLOR-FIXED") (setq *AS4:CROSSCOLOR-FIXED* (AS4:str-to-color val)))
    ((= key "SHAPE-STATION") (setq *AS4:SHAPE-STATION* val))
    ((= key "MARKER-STATION") (setq *AS4:MARKER-STATION* val))
    ((= key "COLOR-STATION") (setq *AS4:COLOR-STATION* (AS4:str-to-color val)))
    ((= key "CROSSCOLOR-STATION") (setq *AS4:CROSSCOLOR-STATION* (AS4:str-to-color val)))
    ((= key "SHAPE-SAMPLE") (setq *AS4:SHAPE-SAMPLE* val))
    ((= key "MARKER-SAMPLE") (setq *AS4:MARKER-SAMPLE* val))
    ((= key "COLOR-SAMPLE") (setq *AS4:COLOR-SAMPLE* (AS4:str-to-color val)))
    ((= key "CROSSCOLOR-SAMPLE") (setq *AS4:CROSSCOLOR-SAMPLE* (AS4:str-to-color val)))
    ((= key "SHAPE-FIND") (setq *AS4:SHAPE-FIND* val))
    ((= key "MARKER-FIND") (setq *AS4:MARKER-FIND* val))
    ((= key "COLOR-FIND") (setq *AS4:COLOR-FIND* (AS4:str-to-color val)))
    ((= key "CROSSCOLOR-FIND") (setq *AS4:CROSSCOLOR-FIND* (AS4:str-to-color val)))
    ((= key "SHAPE-MARKER3D") (setq *AS4:SHAPE-MARKER3D* val))
    ((= key "MARKER-MARKER3D") (setq *AS4:MARKER-MARKER3D* val))
    ((= key "COLOR-MARKER3D") (setq *AS4:COLOR-MARKER3D* (AS4:str-to-color val)))
    ((= key "CROSSCOLOR-MARKER3D") (setq *AS4:CROSSCOLOR-MARKER3D* (AS4:str-to-color val)))
    ((= key "VCOLOR-FEATURE") (setq *AS4:VCOLOR-FEATURE* (AS4:str-to-color val)))
    ((= key "VLW-FEATURE") (setq *AS4:VLW-FEATURE* (AS4:str-to-num val)))
    ((= key "VCOLOR-SAMPLE") (setq *AS4:VCOLOR-SAMPLE* (AS4:str-to-color val)))
    ((= key "VLW-SAMPLE") (setq *AS4:VLW-SAMPLE* (AS4:str-to-num val)))
    ((= key "VCOLOR-FIND") (setq *AS4:VCOLOR-FIND* (AS4:str-to-color val)))
    ((= key "VLW-FIND") (setq *AS4:VLW-FIND* (AS4:str-to-num val)))
    ((= key "VCOLOR-TRENCH") (setq *AS4:VCOLOR-TRENCH* (AS4:str-to-color val)))
    ((= key "VLW-TRENCH") (setq *AS4:VLW-TRENCH* (AS4:str-to-num val)))
    ((= key "VCOLOR-SECTION") (setq *AS4:VCOLOR-SECTION* (AS4:str-to-color val)))
    ((= key "VLW-SECTION") (setq *AS4:VLW-SECTION* (AS4:str-to-num val)))
    ((= key "TEXTSIZE-FIXED") (setq *AS4:TEXTSIZE-FIXED* (atof val)))
    ((= key "TEXTCOLOR-FIXED") (setq *AS4:TEXTCOLOR-FIXED* (AS4:str-to-color val)))
    ((= key "TEXTSIZE-STATION") (setq *AS4:TEXTSIZE-STATION* (atof val)))
    ((= key "TEXTCOLOR-STATION") (setq *AS4:TEXTCOLOR-STATION* (AS4:str-to-color val)))
    ((= key "TEXTSIZE-SAMPLE") (setq *AS4:TEXTSIZE-SAMPLE* (atof val)))
    ((= key "TEXTCOLOR-SAMPLE") (setq *AS4:TEXTCOLOR-SAMPLE* (AS4:str-to-color val)))
    ((= key "TEXTSIZE-FIND") (setq *AS4:TEXTSIZE-FIND* (atof val)))
    ((= key "TEXTCOLOR-FIND") (setq *AS4:TEXTCOLOR-FIND* (AS4:str-to-color val)))
    ((= key "TEXTSIZE-HEIGHT") (setq *AS4:TEXTSIZE-HEIGHT* (atof val)))
    ((= key "TEXTCOLOR-HEIGHT") (setq *AS4:TEXTCOLOR-HEIGHT* (AS4:str-to-color val)))
    ((= key "TEXTSIZE-MARKER3D") (setq *AS4:TEXTSIZE-MARKER3D* (atof val)))
    ((= key "TEXTCOLOR-MARKER3D") (setq *AS4:TEXTCOLOR-MARKER3D* (AS4:str-to-color val)))
    ((= key "TEXTSIZE-SECTION") (setq *AS4:TEXTSIZE-SECTION* (atof val)))
    ((= key "TEXTCOLOR-SECTION") (setq *AS4:TEXTCOLOR-SECTION* (AS4:str-to-color val)))
    ((= key "XPORT-FORMAT") (setq *AS4:XPORT-FORMAT* val))
    ((= key "XPORT-EPSG") (setq *AS4:XPORT-EPSG* val))
  )
)

(defun AS4:load-settings-from (path / f line eq key val)
  (if (and path (findfile path))
    (progn
      (setq f (open path "r"))
      (if f
        (progn
          (while (setq line (read-line f))
            (setq eq (vl-string-search "=" line))
            (if eq
              (progn
                (setq key (substr line 1 eq))
                (setq val (substr line (+ eq 2)))
                (AS4:apply-setting key val)
              )
            )
          )
          (close f)
        )
      )
    )
  )
)
(defun AS4:load-settings () (AS4:load-settings-from (AS4:settings-path)))
(defun AS4:load-settings-global () (AS4:load-settings-from (AS4:settings-global-path)))

(AS4:load-settings-global)
(AS4:load-settings)

;; resets every setting to the AS4CAD factory defaults
;; normalizes a getkword result from a "Yes No Y N" keyword list down
;; to plain "Yes"/"No", so every call site can keep comparing against
;; the full word regardless of whether the person typed the full word
;; or the English abbreviation. Deliberately does not accept "J"/"Ja"/
;; "Nein" - AS4CAD's own prompts stay unambiguously English even on a
;; German-language AutoCAD/BricsCAD, so answers are never accidentally
;; mixed between the two.
(defun AS4:norm-yn (kw)
  (cond
    ((member kw (list "Y" "y")) "Yes")
    ((member kw (list "N" "n")) "No")
    (T kw)
  )
)

;; AS4SETTINGS: the only entry point for AS4CAD's configuration
;; commands - layer structure, symbol, text, vector, export defaults,
;; and factory reset are internal functions, not separate commands,
;; reached only through this menu. Type the first letter shown to
;; jump straight to that step, as many times as needed, in any order,
;; until eXit.
(defun c:AS4SETTINGS ( / kw done)
  (setq done nil)
  (while (not done)
    (initget "Layerstructure Vector Symbol Text Export Default eXit L V S T E D X")
    (setq kw (getkword "\nAS4CAD settings [Layerstructure/Vector/Symbol/Text/Export/Default/eXit] <eXit>: "))
    (if (not kw) (setq kw "eXit"))
    (cond
      ((member kw (list "Layerstructure" "L")) (AS4:set-layer))
      ((member kw (list "Vector" "V")) (AS4:set-vector))
      ((member kw (list "Symbol" "S")) (AS4:set-symbol))
      ((member kw (list "Text" "T")) (AS4:set-text))
      ((member kw (list "Export" "E")) (AS4:set-xport))
      ((member kw (list "Default" "D")) (AS4:set-default))
      ((member kw (list "eXit" "X")) (setq done T))
    )
  )
  (princ)
)

;; internal - AS4SETTINGS' "Default" step
(defun AS4:set-default ( / oldiso gkw)
  (setq *AS4:LAYERFIELD* "ID")
  (setq *AS4:VERTEXRADIUS* 0.02)
  (setq *AS4:TEXTHEIGHT* 0.08)
  (setq *AS4:SYMBOLSCALE* 0.4)
  (setq *AS4:MODE-HEIGHTS* "C")
  (setq *AS4:MODE-SAMPLES* "B")
  (setq *AS4:MODE-FINDS* "B")
  (setq *AS4:MODE-MARKERS* "B")
  (setq *AS4:MODE-SECTIONS* "B")
  (setq *AS4:MODE-FIXED* "D")
  (setq *AS4:SHAPE-FIXED* "Circle")      (setq *AS4:MARKER-FIXED* "Crosshair")
  (setq *AS4:COLOR-FIXED* (cons 62 1))   (setq *AS4:CROSSCOLOR-FIXED* (cons 62 8))
  (setq *AS4:SHAPE-STATION* "Circle")    (setq *AS4:MARKER-STATION* "Crosshair")
  (setq *AS4:COLOR-STATION* (cons 62 2)) (setq *AS4:CROSSCOLOR-STATION* (cons 62 8))
  (setq *AS4:SHAPE-SAMPLE* "Circle")     (setq *AS4:MARKER-SAMPLE* "X")
  (setq *AS4:COLOR-SAMPLE* (cons 420 *AS4:TC-BROWN*))  (setq *AS4:CROSSCOLOR-SAMPLE* (cons 62 7))
  (setq *AS4:SHAPE-FIND* "Circle")       (setq *AS4:MARKER-FIND* "X")
  (setq *AS4:COLOR-FIND* (cons 420 *AS4:TC-LIGHTBLUE*))   (setq *AS4:CROSSCOLOR-FIND* (cons 62 7))
  (setq *AS4:SHAPE-MARKER3D* "Circle")   (setq *AS4:MARKER-MARKER3D* "X")
  (setq *AS4:COLOR-MARKER3D* (cons 62 6))       (setq *AS4:CROSSCOLOR-MARKER3D* (cons 62 7))
  (setq *AS4:VCOLOR-FEATURE* nil) (setq *AS4:VLW-FEATURE* 25)
  (setq *AS4:VCOLOR-SAMPLE* (cons 420 *AS4:TC-BROWN*))  (setq *AS4:VLW-SAMPLE* nil)
  (setq *AS4:VCOLOR-FIND* (cons 420 *AS4:TC-LIGHTBLUE*))   (setq *AS4:VLW-FIND* nil)
  (setq *AS4:VCOLOR-TRENCH* (cons 62 8))         (setq *AS4:VLW-TRENCH* 20)
  (setq *AS4:VCOLOR-SECTION* nil) (setq *AS4:VLW-SECTION* nil)
  (setq *AS4:TEXTSIZE-FIXED* 0.08)     (setq *AS4:TEXTCOLOR-FIXED* (cons 62 1))
  (setq *AS4:TEXTSIZE-STATION* 0.08)   (setq *AS4:TEXTCOLOR-STATION* (cons 62 2))
  (setq *AS4:TEXTSIZE-SAMPLE* 0.08)    (setq *AS4:TEXTCOLOR-SAMPLE* (cons 420 *AS4:TC-BROWN*))
  (setq *AS4:TEXTSIZE-FIND* 0.08)      (setq *AS4:TEXTCOLOR-FIND* (cons 420 *AS4:TC-LIGHTBLUE*))
  (setq *AS4:TEXTSIZE-HEIGHT* 0.04)    (setq *AS4:TEXTCOLOR-HEIGHT* (cons 62 250))
  (setq *AS4:TEXTSIZE-MARKER3D* 0.08)  (setq *AS4:TEXTCOLOR-MARKER3D* (cons 62 6))
  (setq *AS4:TEXTSIZE-SECTION* 0.08)   (setq *AS4:TEXTCOLOR-SECTION* (cons 62 8))
  (setq *AS4:XPORT-FORMAT* "Raw") (setq *AS4:XPORT-EPSG* "")
  (AS4:save-settings)
  (setq oldiso (AS4:suppress-autocomplete))
  (initget "Yes No Y N")
  (setq gkw (AS4:norm-yn (getkword "\nAlso reset the global default for every project? [Yes/No] <No>: ")))
  (AS4:restore-autocomplete oldiso)
  (if (= gkw "Yes") (AS4:save-settings-global))
  (princ (strcat "\nAS4CAD settings reset to factory defaults."
                 (if (= gkw "Yes") " (also reset globally)" "")))
  (princ)
)

;; AS4SETXPORT - default output format for AS4XPORTPOINTDATACSV and
;; default EPSG code for AS4XPORTGISGEOJSON, so neither has to be
;; re-entered on every export. Both remain overridable per run - this
;; only changes what appears as the <default> in each prompt.
;; internal - AS4SETTINGS' "Export" step
(defun AS4:set-xport ( / oldiso gkw fkw epsg)
  (setq oldiso (AS4:suppress-autocomplete))
  (initget "Raw Schema")
  (setq fkw (getkword (strcat
    "\nDefault output format for AS4XPORTPOINTDATACSV [Raw/Schema] <" *AS4:XPORT-FORMAT* ">: ")))
  (if fkw (setq *AS4:XPORT-FORMAT* fkw))

  (setq epsg (getstring (strcat
    "\nDefault EPSG code for AS4XPORTGISGEOJSON, or Enter for none (always ask) <"
    (if (> (strlen *AS4:XPORT-EPSG*) 0) *AS4:XPORT-EPSG* "none") ">: ")))
  (if (> (strlen epsg) 0)
    (progn
      (if (and (>= (strlen epsg) 5) (= (strcase (substr epsg 1 5)) "EPSG:"))
        (setq epsg (substr epsg 6))
      )
      (if (AS4:all-digits epsg)
        (setq *AS4:XPORT-EPSG* epsg)
        (princ "\nNot a valid EPSG code (digits only) - default left unchanged.")
      )
    )
  )

  (initget "Yes No Y N")
  (setq gkw (AS4:norm-yn (getkword "\nAlso save as global default for every project? [Yes/No] <No>: ")))
  (AS4:restore-autocomplete oldiso)
  (AS4:save-settings)
  (if (= gkw "Yes") (AS4:save-settings-global))
  (princ (strcat "\nExport defaults updated." (if (= gkw "Yes") " (also saved globally)" "")))
  (princ)
)

(defun c:AS4STATUS ()
  (princ (strcat "\nAS4CAD version: " *AS4:VERSION*))
  (princ (strcat "\nLayer field:  " *AS4:LAYERFIELD*))
  (princ (strcat "\nVertex radius: " (rtos *AS4:VERTEXRADIUS* 2 3)))
  (princ (strcat "\nText height:   " (rtos *AS4:TEXTHEIGHT* 2 3)))
  (princ (strcat "\nSymbol scale:  " (rtos *AS4:SYMBOLSCALE* 2 3)))
  (princ (strcat "\nLayer mode - heights=" *AS4:MODE-HEIGHTS* " samples=" *AS4:MODE-SAMPLES*
                 " finds=" *AS4:MODE-FINDS* " markers=" *AS4:MODE-MARKERS*
                 " sections=" *AS4:MODE-SECTIONS* " fixed=" *AS4:MODE-FIXED*))
  (princ (strcat "\nExport format (AS4XPORT's Csv default): " *AS4:XPORT-FORMAT*))
  (princ (strcat "\nExport EPSG (AS4XPORT's GeoJson default):     " (if (> (strlen *AS4:XPORT-EPSG*) 0) *AS4:XPORT-EPSG* "(ask each time)")))

  (princ)
)

;; -----------------------------------------------------------------------
;; settings dialog (replaces the previous four separate set-commands)
;; -----------------------------------------------------------------------
(defun AS4:layerfield-display ()
  (cond ((= *AS4:LAYERFIELD* "ID") "IDnum")
        ((= *AS4:LAYERFIELD* "IDstring") "IDstr")
        ((= *AS4:LAYERFIELD* "ID_code") "IDstrCode")
        ((= *AS4:LAYERFIELD* "code_ID") "CodeIDstr")
        ((= *AS4:LAYERFIELD* "IDnumcode") "IDnumCode")
        ((= *AS4:LAYERFIELD* "codeIDnum") "CodeIDnum")
        (t "IDnum"))
)

;; Interactive AS4CAD commands are deliberately implemented WITHOUT a DCL
;; dialog. A DCL dialog needs a temp file (load_dialog requires a file on
;; disk), and on some AutoCAD-for-Mac installs neither TEMPPREFIX nor
;; vl-filename-mktemp produce a writable, valid path (sandbox
;; restrictions). Plain command-line prompts have no such dependency and
;; work identically everywhere.
;; Keyword names such as AS4SETLAYER's field choice are chosen so that
;; none is a text prefix of another (IDnum/IDstr/IDcode/codeID rather
;; than ID/IDstring/IDcode/codeID) - with "ID" as its own keyword AND a
;; prefix of "IDstring"/"IDcode", the command-line's dynamic-input
;; suggestion dropdown could commit "ID" even when "IDstring" was picked
;; from the list with the keyboard.
;; The two helpers below temporarily disable AutoCAD's command-line
;; autocomplete suggestion popup (system variable INPUTSEARCHOPTIONS),
;; which can otherwise show unrelated built-in commands (e.g. "ID", the
;; point-coordinate command) and commit the wrong text if picked with the
;; keyboard. Wrapped in vl-catch-all-apply since this system variable may
;; not exist on other CAD applications (e.g. BricsCAD) - on those this
;; silently does nothing.
(defun AS4:suppress-autocomplete ( / old)
  (setq old (vl-catch-all-apply 'getvar (list "INPUTSEARCHOPTIONS")))
  (if (vl-catch-all-error-p old) nil (progn (vl-catch-all-apply 'setvar (list "INPUTSEARCHOPTIONS" 0)) old))
)
(defun AS4:restore-autocomplete (old)
  (if old (vl-catch-all-apply 'setvar (list "INPUTSEARCHOPTIONS" old)))
)

;; AS4SETLAYER - all layer-related choices in one pass: first, which field
;; names the per-feature layer that lines/polygons (and any "C"-mode
;; symbols below) land on; then a quick A/B/C/D prompt per point category,
;; deciding where that category's symbols go. Each prompt spells out what
;; its own four options actually produce (using that category's real
;; prefix/suffix/collective layer names), so only the single letter needs
;; to be typed:
;;   A - own layer, named with a category PREFIX
;;   B - own layer, named with a category SUFFIX
;;   C - shares the per-feature layer with that feature's lines/polygons
;;   D - one shared collective layer for every occurrence of that type
;; Only the symbol's own layer is affected - its label stays on the
;; existing dedicated txt_* layer either way. Choices are saved to disk
;; (AS4:save-settings) so they persist for this project.
;; NOTE: prompt text below uses the non-word placeholder "{ID}" rather
;; than a plain English word like "<layer>" or "<feature>" - any real
;; word risks matching a live AutoCAD/vertical-product command name (LAYER,
;; FEATURE from Civil 3D's Feature Lines, etc.), which AutoCAD's command-
;; line autocomplete then shows as a spurious extra option even with
;; AS4:suppress-autocomplete active. A non-word token can't match any
;; command name, so this class of bug can't resurface with a future word
;; choice.
;; internal - AS4SETTINGS' "Layerstructure" step
(defun AS4:set-layer ( / kw oldiso gkw)
  (setq oldiso (AS4:suppress-autocomplete))
  (initget "IDnum IDstr IDnumCode IDstrCode CodeIDnum CodeIDstr")
  (setq kw (getkword
    (strcat "\nWhich field names the per-feature layer? [IDnum/IDstr/IDnumCode/IDstrCode/CodeIDnum/CodeIDstr] <" (AS4:layerfield-display) ">: ")))
  (cond
    ((= kw "IDnum") (setq *AS4:LAYERFIELD* "ID"))
    ((= kw "IDstr") (setq *AS4:LAYERFIELD* "IDstring"))
    ((= kw "IDnumCode") (setq *AS4:LAYERFIELD* "IDnumcode"))
    ((= kw "IDstrCode") (setq *AS4:LAYERFIELD* "ID_code"))
    ((= kw "CodeIDnum") (setq *AS4:LAYERFIELD* "codeIDnum"))
    ((= kw "CodeIDstr") (setq *AS4:LAYERFIELD* "code_ID"))
  )
  (initget "A B C D")
  (setq kw (getkword (strcat
    "\nHeight points (01) - A: as4_heights_{ID}  B: {ID}_heights  C: shared with lines  D: as4_heights (all)"
    "\nChoice [A/B/C/D] <" *AS4:MODE-HEIGHTS* ">: ")))
  (if kw (setq *AS4:MODE-HEIGHTS* kw))
  (initget "A B C D E")
  (setq kw (getkword (strcat
    "\nSamples (51/52/53) - A: as4_samples_{ID}  B: {ID}_sample  C: shared with lines  D: as4_samples (all)  E: as4_sample-{SEQ}_{ID} (one layer per sample)"
    "\nChoice [A/B/C/D/E] <" *AS4:MODE-SAMPLES* ">: ")))
  (if kw (setq *AS4:MODE-SAMPLES* kw))
  (initget "A B C D E")
  (setq kw (getkword (strcat
    "\nFinds (71/72/73) - A: as4_finds_{ID}  B: {ID}_find  C: shared with lines  D: as4_finds (all)  E: as4_find-{SEQ}_{ID} (one layer per find)"
    "\nChoice [A/B/C/D/E] <" *AS4:MODE-FINDS* ">: ")))
  (if kw (setq *AS4:MODE-FINDS* kw))
  (initget "A B C D")
  (setq kw (getkword (strcat
    "\n3D markers (81) - A: as4_3d-markers_{ID}  B: {ID}_3D-marker  C: shared with lines  D: as4_3d-markers (all)"
    "\nChoice [A/B/C/D] <" *AS4:MODE-MARKERS* ">: ")))
  (if kw (setq *AS4:MODE-MARKERS* kw))
  (initget "A B C D")
  (setq kw (getkword (strcat
    "\nSection nails (00) - A: as4_sections_{ID}  B: {ID}_section  C: shared with lines  D: as4_section-nails (all)"
    "\nChoice [A/B/C/D] <" *AS4:MODE-SECTIONS* ">: ")))
  (if kw (setq *AS4:MODE-SECTIONS* kw))
  (initget "A B C D")
  (setq kw (getkword (strcat
    "\nFixed points (91) - A: as4_fixed_{ID}  B: {ID}_fixed  C: shared with lines  D: as4_fixed-points (all)"
    "\nChoice [A/B/C/D] <" *AS4:MODE-FIXED* ">: ")))
  (if kw (setq *AS4:MODE-FIXED* kw))
  (initget "Yes No Y N")
  (setq gkw (AS4:norm-yn (getkword "\nAlso save as global default for every project? [Yes/No] <No>: ")))
  (AS4:restore-autocomplete oldiso)
  (AS4:save-settings)
  (if (= gkw "Yes") (AS4:save-settings-global))
  (princ (strcat "\nLayer assignment updated. field=" *AS4:LAYERFIELD*
                 " heights=" *AS4:MODE-HEIGHTS*
                 " samples=" *AS4:MODE-SAMPLES* " finds=" *AS4:MODE-FINDS*
                 " markers=" *AS4:MODE-MARKERS* " sections=" *AS4:MODE-SECTIONS*
                 " fixed=" *AS4:MODE-FIXED*
                 (if (= gkw "Yes") " (also saved globally)" "")))
  (princ)
)

;; shared prompt helpers for AS4SETSYMBOL / AS4SETVECTOR / AS4SETTEXT
(setq *AS4:ACI-LEGEND* "1=red 2=yellow 3=green 4=cyan 5=blue 6=magenta 7=white/black 8=dark grey 9=light grey 250=very dark grey")

(defun AS4:aci-display (colorspec)
  (cond ((not colorspec) "ByLayer") ((= (car colorspec) 62) (itoa (cdr colorspec))) (t "custom"))
)
(defun AS4:shape-letter (s) (cond ((= s "Circle") "A") ((= s "Triangle") "B") ((= s "Square") "C") ((= s "Hexagon") "D") (t "A")))
(defun AS4:marker-letter (m) (cond ((= m "Crosshair") "A") ((= m "X") "B") ((= m "Dot") "C") ((= m "Circle") "D") (t "A")))

(defun AS4:ask-shape (label current / kw)
  (initget "A B C D")
  (setq kw (getkword (strcat "\n" label " shape - A: Circle  B: Triangle  C: Square  D: Hexagon"
    "\nChoice [A/B/C/D] <" (AS4:shape-letter current) ">: ")))
  (cond ((= kw "A") "Circle") ((= kw "B") "Triangle") ((= kw "C") "Square") ((= kw "D") "Hexagon") (t current))
)
(defun AS4:ask-marker (label current / kw)
  (initget "A B C D")
  (setq kw (getkword (strcat "\n" label " center marker - A: Crosshair  B: X  C: Dot  D: Circle"
    "\nChoice [A/B/C/D] <" (AS4:marker-letter current) ">: ")))
  (cond ((= kw "A") "Crosshair") ((= kw "B") "X") ((= kw "C") "Dot") ((= kw "D") "Circle") (t current))
)
;; always-on color (symbols always have a color - no ByLayer option here)
(defun AS4:ask-color (label current / v)
  (setq v (getint (strcat "\n" label " color - ACI number (" *AS4:ACI-LEGEND* ") <" (AS4:aci-display current) ">: ")))
  (if v (cons 62 v) current)
)
;; optional color (lines can be ByLayer/no override - entering 0 clears it)
(defun AS4:ask-vcolor (label current / v)
  (setq v (getint (strcat "\n" label " color - ACI number (" *AS4:ACI-LEGEND* "), 0 = ByLayer/no override <" (AS4:aci-display current) ">: ")))
  (cond ((not v) current) ((= v 0) nil) (t (cons 62 v)))
)
;; optional lineweight in mm (0 clears to ByLayer/no override)
(defun AS4:ask-vlw (label current / v)
  (setq v (getreal (strcat "\n" label " lineweight in mm, 0 = ByLayer/no override <"
    (if current (rtos (/ current 100.0) 2 2) "ByLayer") ">: ")))
  (cond ((not v) current) ((= v 0.0) nil) (t (fix (+ 0.5 (* v 100.0)))))
)

;; AS4SETSYMBOL - shape, center marker, colors, vertex marker radius and
;; symbol scale for the five customizable point symbols (Fixed/Station/
;; Sample/Find/3D-marker). Height and Section nail are not covered here -
;; their designs (apex-at-coordinate triangle, crossing-point-at-
;; coordinate X) are purpose-built and do not fit the generic "shape +
;; centered marker" model, though they do share the vertex radius/symbol
;; scale settings. Label text size/color for all seven labelled symbol
;; types (including Height and Section nail) live in AS4SETTEXT instead.
;; internal - AS4SETTINGS' "Symbol" step
(defun AS4:set-symbol ( / oldiso gkw vr ss)
  (setq oldiso (AS4:suppress-autocomplete))
  (setq vr (getreal (strcat "\nVertex marker radius <" (rtos *AS4:VERTEXRADIUS* 2 3) ">: ")))
  (if (and vr (> vr 0.0)) (setq *AS4:VERTEXRADIUS* vr))
  (setq ss (getreal (strcat "\nPoint symbol scale <" (rtos *AS4:SYMBOLSCALE* 2 3) ">: ")))
  (if (and ss (> ss 0.0)) (setq *AS4:SYMBOLSCALE* ss))
  (princ (strcat "\nColor legend: " *AS4:ACI-LEGEND*))
  (setq *AS4:SHAPE-FIXED*      (AS4:ask-shape  "Fixed point"  *AS4:SHAPE-FIXED*))
  (setq *AS4:MARKER-FIXED*     (AS4:ask-marker "Fixed point"  *AS4:MARKER-FIXED*))
  (setq *AS4:COLOR-FIXED*      (AS4:ask-color  "Fixed point shape"  *AS4:COLOR-FIXED*))
  (setq *AS4:CROSSCOLOR-FIXED* (AS4:ask-color  "Fixed point marker" *AS4:CROSSCOLOR-FIXED*))
  (setq *AS4:SHAPE-STATION*      (AS4:ask-shape  "Station point" *AS4:SHAPE-STATION*))
  (setq *AS4:MARKER-STATION*     (AS4:ask-marker "Station point" *AS4:MARKER-STATION*))
  (setq *AS4:COLOR-STATION*      (AS4:ask-color  "Station point shape"  *AS4:COLOR-STATION*))
  (setq *AS4:CROSSCOLOR-STATION* (AS4:ask-color  "Station point marker" *AS4:CROSSCOLOR-STATION*))
  (setq *AS4:SHAPE-SAMPLE*      (AS4:ask-shape  "Sample point" *AS4:SHAPE-SAMPLE*))
  (setq *AS4:MARKER-SAMPLE*     (AS4:ask-marker "Sample point" *AS4:MARKER-SAMPLE*))
  (setq *AS4:COLOR-SAMPLE*      (AS4:ask-color  "Sample point shape"  *AS4:COLOR-SAMPLE*))
  (setq *AS4:CROSSCOLOR-SAMPLE* (AS4:ask-color  "Sample point marker" *AS4:CROSSCOLOR-SAMPLE*))
  (setq *AS4:SHAPE-FIND*      (AS4:ask-shape  "Finds point" *AS4:SHAPE-FIND*))
  (setq *AS4:MARKER-FIND*     (AS4:ask-marker "Finds point" *AS4:MARKER-FIND*))
  (setq *AS4:COLOR-FIND*      (AS4:ask-color  "Finds point shape"  *AS4:COLOR-FIND*))
  (setq *AS4:CROSSCOLOR-FIND* (AS4:ask-color  "Finds point marker" *AS4:CROSSCOLOR-FIND*))
  (setq *AS4:SHAPE-MARKER3D*      (AS4:ask-shape  "3D marker" *AS4:SHAPE-MARKER3D*))
  (setq *AS4:MARKER-MARKER3D*     (AS4:ask-marker "3D marker" *AS4:MARKER-MARKER3D*))
  (setq *AS4:COLOR-MARKER3D*      (AS4:ask-color  "3D marker shape"  *AS4:COLOR-MARKER3D*))
  (setq *AS4:CROSSCOLOR-MARKER3D* (AS4:ask-color  "3D marker center mark" *AS4:CROSSCOLOR-MARKER3D*))
  (initget "Yes No Y N")
  (setq gkw (AS4:norm-yn (getkword "\nAlso save as global default for every project? [Yes/No] <No>: ")))
  (AS4:restore-autocomplete oldiso)
  (AS4:save-settings)
  (if (= gkw "Yes") (AS4:save-settings-global))
  (princ (strcat "\nSymbol settings updated." (if (= gkw "Yes") " (also saved globally)" "")))
  (princ)
)

;; AS4SETVECTOR - color and lineweight for the five line/polygon shape-
;; type groups: feature (02/03/61), sample (52/53), find (72/73), trench
;; (92/93) and section nail lines (00). Entering 0 for color or
;; lineweight clears that override back to ByLayer - new geometry on that
;; layer then simply takes on the layer's own assigned color/lineweight.
;; internal - AS4SETTINGS' "Vector" step
(defun AS4:set-vector ( / oldiso gkw)
  (setq oldiso (AS4:suppress-autocomplete))
  (princ (strcat "\nColor legend: " *AS4:ACI-LEGEND*))
  (setq *AS4:VCOLOR-FEATURE* (AS4:ask-vcolor "Standard lines/polygons (02/03/61)" *AS4:VCOLOR-FEATURE*))
  (setq *AS4:VLW-FEATURE*    (AS4:ask-vlw    "Standard lines/polygons (02/03/61)" *AS4:VLW-FEATURE*))
  (setq *AS4:VCOLOR-SAMPLE*  (AS4:ask-vcolor "Sample lines/polygons (52/53)" *AS4:VCOLOR-SAMPLE*))
  (setq *AS4:VLW-SAMPLE*     (AS4:ask-vlw    "Sample lines/polygons (52/53)" *AS4:VLW-SAMPLE*))
  (setq *AS4:VCOLOR-FIND*    (AS4:ask-vcolor "Finds lines/polygons (72/73)" *AS4:VCOLOR-FIND*))
  (setq *AS4:VLW-FIND*       (AS4:ask-vlw    "Finds lines/polygons (72/73)" *AS4:VLW-FIND*))
  (setq *AS4:VCOLOR-TRENCH*  (AS4:ask-vcolor "Trench lines/polygons (92/93)" *AS4:VCOLOR-TRENCH*))
  (setq *AS4:VLW-TRENCH*     (AS4:ask-vlw    "Trench lines/polygons (92/93)" *AS4:VLW-TRENCH*))
  (setq *AS4:VCOLOR-SECTION* (AS4:ask-vcolor "Section nail lines (00)" *AS4:VCOLOR-SECTION*))
  (setq *AS4:VLW-SECTION*    (AS4:ask-vlw    "Section nail lines (00)" *AS4:VLW-SECTION*))
  (initget "Yes No Y N")
  (setq gkw (AS4:norm-yn (getkword "\nAlso save as global default for every project? [Yes/No] <No>: ")))
  (AS4:restore-autocomplete oldiso)
  (AS4:save-settings)
  (if (= gkw "Yes") (AS4:save-settings-global))
  ;; lineweight overrides are invisible in Model Space unless lineweight
  ;; display is on - AutoCAD/BricsCAD default this off, so turn it on
  ;; here rather than leaving the user to wonder why nothing changed
  ;; visually. Wrapped defensively in case LWDISPLAY doesn't exist on
  ;; some other CAD application.
  (vl-catch-all-apply 'setvar (list "LWDISPLAY" 1))
  (princ (strcat "\nLine/polygon style updated. (Lineweight display turned on so changes are visible in Model Space.)"
                 (if (= gkw "Yes") " (also saved globally)" "")))
  (princ)
)

;; per-type label text size/color prompt helper
(defun AS4:ask-textsize (label current / v)
  (setq v (getreal (strcat "\n" label " label text height <" (rtos current 2 3) ">: ")))
  (if (and v (> v 0.0)) v current)
)

;; AS4SETTEXT - label text height and ACI color for each of the seven
;; labelled symbol types (Fixed/Station/Sample/Find/Height/3D-marker/
;; Section nail). Height and Section nail are included here even though
;; AS4SETSYMBOL does not cover their shape - their labels are ordinary
;; text like every other symbol's.
;; internal - AS4SETTINGS' "Text" step
(defun AS4:set-text ( / oldiso gkw)
  (setq oldiso (AS4:suppress-autocomplete))
  (princ (strcat "\nColor legend: " *AS4:ACI-LEGEND*))
  (setq *AS4:TEXTSIZE-FIXED*  (AS4:ask-textsize "Fixed point"  *AS4:TEXTSIZE-FIXED*))
  (setq *AS4:TEXTCOLOR-FIXED* (AS4:ask-color    "Fixed point label" *AS4:TEXTCOLOR-FIXED*))
  (setq *AS4:TEXTSIZE-STATION*  (AS4:ask-textsize "Station point"  *AS4:TEXTSIZE-STATION*))
  (setq *AS4:TEXTCOLOR-STATION* (AS4:ask-color    "Station point label" *AS4:TEXTCOLOR-STATION*))
  (setq *AS4:TEXTSIZE-SAMPLE*  (AS4:ask-textsize "Sample point"  *AS4:TEXTSIZE-SAMPLE*))
  (setq *AS4:TEXTCOLOR-SAMPLE* (AS4:ask-color    "Sample point label" *AS4:TEXTCOLOR-SAMPLE*))
  (setq *AS4:TEXTSIZE-FIND*  (AS4:ask-textsize "Finds point"  *AS4:TEXTSIZE-FIND*))
  (setq *AS4:TEXTCOLOR-FIND* (AS4:ask-color    "Finds point label" *AS4:TEXTCOLOR-FIND*))
  (setq *AS4:TEXTSIZE-HEIGHT*  (AS4:ask-textsize "Height point"  *AS4:TEXTSIZE-HEIGHT*))
  (setq *AS4:TEXTCOLOR-HEIGHT* (AS4:ask-color    "Height point label" *AS4:TEXTCOLOR-HEIGHT*))
  (setq *AS4:TEXTSIZE-MARKER3D*  (AS4:ask-textsize "3D marker"  *AS4:TEXTSIZE-MARKER3D*))
  (setq *AS4:TEXTCOLOR-MARKER3D* (AS4:ask-color    "3D marker label" *AS4:TEXTCOLOR-MARKER3D*))
  (setq *AS4:TEXTSIZE-SECTION*  (AS4:ask-textsize "Section nail"  *AS4:TEXTSIZE-SECTION*))
  (setq *AS4:TEXTCOLOR-SECTION* (AS4:ask-color    "Section nail label" *AS4:TEXTCOLOR-SECTION*))
  (initget "Yes No Y N")
  (setq gkw (AS4:norm-yn (getkword "\nAlso save as global default for every project? [Yes/No] <No>: ")))
  (AS4:restore-autocomplete oldiso)
  (AS4:save-settings)
  (if (= gkw "Yes") (AS4:save-settings-global))
  (princ (strcat "\nLabel text settings updated." (if (= gkw "Yes") " (also saved globally)" "")))
  (princ)
)

;; -----------------------------------------------------------------------
;; string helpers
;; -----------------------------------------------------------------------

(defun AS4:rtrim (s)
  (while (and (> (strlen s) 0)
              (member (substr s (strlen s) 1) (list "\r" "\n" " " "\t")))
    (setq s (substr s 1 (1- (strlen s))))
  )
  s
)

(defun AS4:ltrim (s)
  (while (and (> (strlen s) 0)
              (member (substr s 1 1) (list "\r" "\n" " " "\t")))
    (setq s (substr s 2))
  )
  s
)

;; strips surrounding whitespace, then one matching pair of surrounding
;; double-quotes if present (some spreadsheet/device exports quote
;; every field, or just fields containing the delimiter character) -
;; without this, a quoted point_ID would fail its 10-character length
;; check and be skipped, and a quoted numeric field would make atof
;; silently return 0.0 rather than the real coordinate. A second
;; whitespace trim afterward catches e.g. " VF " that was inside the
;; quotes. A lone, unpaired quote character is left as-is.
(defun AS4:trim (s / s2)
  (setq s2 (AS4:ltrim (AS4:rtrim s)))
  (if (and (>= (strlen s2) 2)
           (= (substr s2 1 1) "\"")
           (= (substr s2 (strlen s2) 1) "\"")
      )
    (setq s2 (AS4:ltrim (AS4:rtrim (substr s2 2 (- (strlen s2) 2)))))
  )
  s2
)

(defun AS4:split (str ch / lst pos)
  (setq lst '())
  (while (setq pos (vl-string-search ch str))
    (setq lst (cons (substr str 1 pos) lst))
    (setq str (substr str (+ pos 1 (strlen ch))))
  )
  (reverse (cons str lst))
)

;; atof that also accepts a decimal comma ("12,5"); empty or nil gives 0.0
(defun AS4:safe-atof (s)
  (if (and s (> (strlen s) 0)) (atof (vl-string-subst "." "," s)) 0.0)
)

;; collapses consecutive repeats of a single delimiter character into one,
;; so files that use e.g. multiple tabs as visual column padding (rather
;; than as meaningful field separators) don't produce spurious empty
;; fields that shift every later column by one. A single delimiter next
;; to genuinely empty content (e.g. a blank trailing "code" field) is
;; untouched, since there is no repeat to collapse there.
(defun AS4:collapse-repeats (str ch / out i c prevdelim)
  (setq out "" i 1 prevdelim nil)
  (while (<= i (strlen str))
    (setq c (substr str i 1))
    (if (= c ch)
      (progn (if (not prevdelim) (setq out (strcat out c))) (setq prevdelim T))
      (progn (setq out (strcat out c)) (setq prevdelim nil))
    )
    (setq i (1+ i))
  )
  out
)

;; auto-detects the delimiter (tab, then semicolon, then pipe, then
;; comma - the first one that splits the line into more than one field
;; wins), collapses repeated delimiter runs first, then trims every
;; resulting field. Comma is tried last since it is also the decimal
;; separator in many European locales, making it the least reliable
;; signal of the four.
(defun AS4:split-auto (line / parts)
  (cond
    ((> (length (setq parts (AS4:split (AS4:collapse-repeats line "\t") "\t"))) 1) nil)
    ((> (length (setq parts (AS4:split (AS4:collapse-repeats line ";") ";"))) 1) nil)
    ((> (length (setq parts (AS4:split (AS4:collapse-repeats line "|") "|"))) 1) nil)
    ((> (length (setq parts (AS4:split (AS4:collapse-repeats line ",") ","))) 1) nil)
    (t (setq parts (list line)))
  )
  (mapcar 'AS4:trim parts)
)

(defun AS4:digits-p (s / i ok)
  (setq i 1 ok T)
  (while (and ok (<= i (strlen s)))
    (if (not (member (substr s i 1) '("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")))
      (setq ok nil)
    )
    (setq i (1+ i))
  )
  ok
)

;; a point_ID is a "station" ID if it consists only of digits and at least
;; one of '.', '-', '_' - such an ID can never be a valid 10-character
;; ArchSurv code (which uses digits + one letter only).
(defun AS4:station-id-p (s / i ch ok hasspecial)
  (setq i 1 ok T hasspecial nil)
  (while (and ok (<= i (strlen s)))
    (setq ch (substr s i 1))
    (cond
      ((member ch '("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")) nil)
      ((member ch '("." "-" "_")) (setq hasspecial T))
      (t (setq ok nil))
    )
    (setq i (1+ i))
  )
  (and ok hasspecial)
)

;; -----------------------------------------------------------------------
;; ArchSurv point_ID parsing: XXXX Y ZZ 001
;; -----------------------------------------------------------------------
(defun AS4:parse-id (id / feature container shptype seq)
  (if (and (= (strlen id) 10) (AS4:digits-p (substr id 1 4)))
    (progn
      (setq feature   (substr id 1 4)
            container (substr id 5 1)
            shptype   (substr id 6 2)
            seq       (atoi (substr id 8 3)))
      (list feature container shptype seq)
    )
    nil
  )
)

;; shape type category: "point" / "posthole" / "polyline" / "polygon" / nil
(defun AS4:category (shptype)
  (cond
    ((member shptype '("01" "51" "71" "81" "91")) "point")
    ((member shptype '("61" "06")) "posthole")
    ((member shptype '("00" "02" "33" "52" "72" "92")) "polyline")
    ((member shptype '("03" "53" "73" "93")) "polygon")
    (t nil)
  )
)

;; color/lineweight override for line and polygon types, set via
;; AS4SETVECTOR. Returns (colorspec-or-nil lineweight-or-nil):
;;   colorspec, if present, is a (group . value) pair (62=ACI, 420=true
;;   color); nil means ByLayer/no override for that property.
(defun AS4:line-style (shptype)
  (cond
    ((member shptype '("02" "03" "61" "06")) (list *AS4:VCOLOR-FEATURE* *AS4:VLW-FEATURE*))
    ((member shptype '("52" "53")) (list *AS4:VCOLOR-SAMPLE* *AS4:VLW-SAMPLE*))
    ((member shptype '("72" "73")) (list *AS4:VCOLOR-FIND* *AS4:VLW-FIND*))
    ((member shptype '("92" "93")) (list *AS4:VCOLOR-TRENCH* *AS4:VLW-TRENCH*))
    ((= shptype "00") (list *AS4:VCOLOR-SECTION* *AS4:VLW-SECTION*))
    (t nil)
  )
)

;; expands an AS4:line-style result into the extra DXF pairs to splice
;; into a POLYLINE header's entmake list (color, and/or lineweight, each
;; only if actually set - otherwise the entity stays ByLayer for that
;; property)
(defun AS4:style-extra (style / lst colorspec lw)
  (if (not style)
    nil
    (progn
      (setq colorspec (nth 0 style) lw (nth 1 style))
      (setq lst nil)
      (if colorspec (setq lst (list (cons (car colorspec) (cdr colorspec)))))
      (if lw (setq lst (append lst (list (cons 370 lw)))))
      lst
    )
  )
)

;; human-readable label for the import summary
(defun AS4:shptype-name (shptype)
  (cond
    ((= shptype "00") "Section nail") ((= shptype "01") "Height point")
    ((= shptype "02") "Polyline") ((= shptype "03") "Polygon")
    ((= shptype "06") "Posthole") ((= shptype "33") "Closed polyline (as line)")
    ((= shptype "51") "Sample point") ((= shptype "52") "Sample polyline")
    ((= shptype "53") "Sample polygon") ((= shptype "61") "Posthole")
    ((= shptype "71") "Find point") ((= shptype "72") "Find polyline")
    ((= shptype "73") "Find polygon") ((= shptype "81") "3D marker")
    ((= shptype "91") "Fixed point") ((= shptype "92") "Trench polyline")
    ((= shptype "93") "Trench polygon") ((= shptype "station") "Station point")
    (t (strcat "Type " shptype))
  )
)

;; find-material (shptype 71, point_prop A-Z) / sample-method (shptype 51,
;; point_prop A-Z) lookup, matching the AS4QGIS "f_ma/s_me" field exactly.
(defun AS4:material-method (shptype letter)
  (cond
    ((= shptype "71")
      (cond
        ((= letter "A") "undeclared") ((= letter "B") "metal") ((= letter "C") "coin")
        ((= letter "D") "stone_object") ((= letter "E") "silex") ((= letter "F") "iron")
        ((= letter "G") "glass") ((= letter "H") "homo") ((= letter "I") "animal_bones")
        ((= letter "J") "architectural_ceramics") ((= letter "K") "ceramics") ((= letter "L") "burnt_daub")
        ((= letter "M") "mortar") ((= letter "N") "slag") ((= letter "O") "organic")
        ((= letter "P") "excav.specif.cat.1") ((= letter "Q") "excav.specif.cat.2") ((= letter "R") "excav.specif.cat.3")
        ((= letter "S") "excav.specif.cat.4") ((= letter "T") "excav.specif.cat.5") ((= letter "U") "excav.specif.cat.6")
        ((= letter "V") "excav.specif.cat.7") ((= letter "W") "excav.specif.cat.8") ((= letter "X") "excav.specif.cat.9")
        ((= letter "Y") "excav.specif.cat.10") ((= letter "Z") "misc")
        (t "")
      )
    )
    ((= shptype "51")
      (cond
        ((= letter "A") "undeclared-sample") ((= letter "B") "brick-sample") ((= letter "C") "c14-sample")
        ((= letter "D") "dendro-sample") ((= letter "E") "soil_bulk_sample") ((= letter "F") "soil_block_sample")
        ((= letter "G") "soil_core_sample") ((= letter "H") "soil_monolith_sample") ((= letter "I") "soil_kubiena_sample")
        ((= letter "J") "soil_waterlogged_sample") ((= letter "K") "excav.specif.meth.1") ((= letter "L") "excav.specif.meth.2")
        ((= letter "M") "excav.specif.meth.3") ((= letter "N") "excav.specif.meth.4") ((= letter "O") "excav.specif.meth.5")
        ((= letter "P") "excav.specif.meth.6") ((= letter "Q") "excav.specif.meth.7") ((= letter "R") "excav.specif.meth.8")
        ((= letter "S") "excav.specif.meth.9") ((= letter "T") "excav.specif.meth.10") ((= letter "U") "excav.specif.meth.11")
        ((= letter "V") "excav.specif.meth.12") ((= letter "W") "excav.specif.meth.13") ((= letter "X") "excav.specif.meth.14")
        ((= letter "Y") "excav.specif.meth.15") ((= letter "Z") "excav.specif.meth.16")
        (t "")
      )
    )
    (t "")
  )
)

;; posthole radius in drawing units (assumes metres): container letter
;; A = 1 cm ... Z = 26 cm, matching the AS4QGIS point-property table.
(defun AS4:posthole-radius (letter / idx)
  (setq idx (- (ascii (strcase letter)) (ascii "A")))
  (if (or (< idx 0) (> idx 25)) (setq idx 0))
  (/ (float (1+ idx)) 200.0) ;; diameter(cm)/100 -> m, /2 -> radius
)

;; -----------------------------------------------------------------------
;; layer handling
;; -----------------------------------------------------------------------
(defun AS4:ensure-layer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake
      (list
        '(0 . "LAYER")
        '(100 . "AcDbSymbolTableRecord")
        '(100 . "AcDbLayerTableRecord")
        (cons 2 name)
        '(70 . 0)
        '(62 . 7)
        '(6 . "Continuous")
      )
    )
  )
  name
)

;; resolves a point symbol's target layer from its AS4SETLAYER mode:
;;   "A" -> its own layer, named "as4_" + category prefix + a clean ID
;;          (the fixed "as4_" pre-prefix keeps every AS4CAD-generated
;;          layer sorted together in the layer list, regardless of
;;          category)
;;   "B" -> its own layer, named with a clean ID + category suffix
;;   "C" -> the per-feature layer (shared with that feature's lines,
;;          named per whatever AS4LAYERFIELD field is selected)
;;   "D" -> one fixed collective layer, regardless of feature
;;   "E" -> (samples/finds only) one layer per individual measurement,
;;          named "as4_" + singular category + "-" + running number +
;;          "_" + a clean ID
;; "cleanid" is deliberately NOT the same value as "layername": layername
;; follows whatever field AS4SETLAYER's first question selected, which
;; may be a composite like "0243_GR" (ID+code) - appropriate for mode C,
;; where the symbol must share the exact same layer as that feature's
;; lines, but redundant/confusing for A/B/E, which already carry their
;; own category prefix/suffix as the distinguishing part of the name.
;; cleanid is always just the plain ID: the unpadded number if
;; AS4LAYERFIELD is number-based (ID/IDnumcode/codeIDnum), or the
;; 4-digit padded string if it is string-based (IDstring/ID_code/code_ID).
(defun AS4:point-layer (mode layername cleanid prefix suffix collective esingular seq)
  (cond
    ((= mode "A") (AS4:ensure-layer (strcat "as4_" prefix cleanid)))
    ((= mode "B") (AS4:ensure-layer (strcat cleanid suffix)))
    ((= mode "E") (AS4:ensure-layer (strcat "as4_" esingular "-" (itoa seq) "_" cleanid)))
    ((= mode "D") (AS4:ensure-layer collective))
    (t layername)
  )
)

;; the plain, code-free ID matching whichever "family" (numeric or
;; zero-padded string) AS4LAYERFIELD is currently set to - see AS4:point-layer
(defun AS4:clean-id (idnum idstring)
  (if (member *AS4:LAYERFIELD* '("ID" "IDnumcode" "codeIDnum"))
    (itoa idnum)
    idstring
  )
)

;; -----------------------------------------------------------------------
;; Xdata (full structured attribute set, APPID "AS4QGIS")
;; -----------------------------------------------------------------------

;; builds the raw (-3 ...) xdata group list for the given attrs, without
;; attaching it to anything - splice this directly into an entmakex call
;; so the entity is created WITH its xdata already attached, rather than
;; attaching it afterward via entmod. Complex entities (POLYLINE with its
;; VERTEX/SEQEND chain) can be unreliable targets for entmod once fully
;; built - see AS4:add-xdata below, which is still used for symbols
;; (INSERT), where entmod-after-creation is not a complex-entity target.
(defun AS4:xdata-group (attrs)
  (regapp "AS4QGIS")
  (list (cons -3
    (list (cons "AS4QGIS"
      (apply 'append
        (mapcar
          '(lambda (p) (list (cons 1000 (strcat (car p) "=" (vl-princ-to-string (cdr p))))))
          attrs
        )
      )
    ))
  ))
)

(defun AS4:add-xdata (ent attrs / xd)
  (if ent
    (progn
      (regapp "AS4QGIS")
      (setq xd (list (cons -3
        (list (cons "AS4QGIS"
          (apply 'append
            (mapcar
              '(lambda (p) (list (cons 1000 (strcat (car p) "=" (vl-princ-to-string (cdr p))))))
              attrs
            )
          )
        ))
      )))
      (entmod (append (entget ent) xd))
    )
  )
)

(defun AS4:layer-value (idnum idstring idcode codeid code)
  (cond
    ((= *AS4:LAYERFIELD* "ID") (itoa idnum))
    ((= *AS4:LAYERFIELD* "IDstring") idstring)
    ((= *AS4:LAYERFIELD* "ID_code") idcode)
    ((= *AS4:LAYERFIELD* "code_ID") codeid)
    ((= *AS4:LAYERFIELD* "IDnumcode") (strcat (itoa idnum) "_" code))
    ((= *AS4:LAYERFIELD* "codeIDnum") (strcat code "_" (itoa idnum)))
    (t idstring)
  )
)

;; -----------------------------------------------------------------------
;; generic per-feature "ID <IDstring>" label (layer txt_ID)
;; -----------------------------------------------------------------------
(defun AS4:text-offset (pt)
  (list (+ (car pt) (* 1.5 *AS4:VERTEXRADIUS*)) (+ (cadr pt) (* 1.5 *AS4:VERTEXRADIUS*)) (caddr pt))
)

(defun AS4:add-text (str pt layer)
  (entmakex (list
    (cons 0 "TEXT") (cons 8 layer) (cons 10 (AS4:text-offset pt))
    (cons 40 *AS4:TEXTHEIGHT*) (cons 1 str)
  ))
)

;; like AS4:add-text, but with an explicit text height, insertion point
;; and rotation (radians) instead of the standard diagonal offset from a
;; reference point - used where two related labels need distinct
;; positions/orientations (e.g. AS4NETTXT's horizontal X / vertical Y pair)
(defun AS4:add-text-rot (str pt layer height rotation)
  (entmakex (list
    (cons 0 "TEXT") (cons 8 layer) (cons 10 pt)
    (cons 40 height) (cons 1 str) (cons 50 rotation)
  ))
)

;; adds one "ID <IDstring>" label per generated layer, the first time that
;; layer is used - always shows the plain feature ID, independent of
;; whichever field AS4SETLAYER currently uses to name the layer itself.
(defun AS4:label-layer-once (layername idnum pt)
  (if (not (member layername *AS4:LABELED-LAYERS*))
    (progn
      (AS4:ensure-layer "as4_txt_ID")
      (AS4:add-text (itoa idnum) pt "as4_txt_ID")
      (setq *AS4:LABELED-LAYERS* (cons layername *AS4:LABELED-LAYERS*))
    )
  )
)

;; -----------------------------------------------------------------------
;; symbol block definitions
;; All geometry is in block-local coordinates with the insertion point
;; (0,0,0) at the actual measured coordinate. Blocks are always
;; (re)defined - see AS4:ensure-block - so an updated script always
;; produces updated symbols even in a drawing that already contains
;; older block definitions with the same names. Every block also carries
;; an ATTDEF (tag LABEL) so the running-number label created at insertion
;; time is a real, editable block attribute rather than a separate text.
;; -----------------------------------------------------------------------
(defun AS4:ensure-block (name entities / e)
  (entmake (list (cons 0 "BLOCK") (cons 2 name) (cons 70 0)
                  (cons 10 (list 0.0 0.0 0.0)) (cons 3 name) (cons 1 "")))
  (foreach e entities (entmake e))
  (entmake (list (cons 0 "ENDBLK")))
  name
)

;; diagonal offset, used by every symbol except the height point
;; -----------------------------------------------------------------------
;; parametric shape/marker geometry for the customizable point symbols
;; (Fixed/Station/Sample/Find/3D-marker). Height and Section nail keep
;; their own fixed, purpose-built designs (apex-at-coordinate triangle,
;; crossing-point-at-coordinate X) since they are not "shape + centered
;; marker" symbols and do not fit this generic model.
;; -----------------------------------------------------------------------

;; a single DXF color pair from a colorspec (group . value), e.g.
;; (62 . 1) for ACI red or (420 . 9127187) for a true color
(defun AS4:color-pair (colorspec) (cons (car colorspec) (cdr colorspec)))

;; n-sided regular polygon outline, as a list of LINE entity defs
(defun AS4:polygon-lines (n r cp / i a1 a2 out)
  (setq out '() i 0)
  (while (< i n)
    (setq a1 (* (/ (* 2.0 pi) n) i))
    (setq a2 (* (/ (* 2.0 pi) n) (1+ i)))
    (setq out (cons
      (list (cons 0 "LINE") (cons 8 "0") cp
            (cons 10 (list (* r (cos a1)) (* r (sin a1)) 0.0))
            (cons 11 (list (* r (cos a2)) (* r (sin a2)) 0.0)))
      out))
    (setq i (1+ i))
  )
  (reverse out)
)

;; outer symbol shape, radius fixed at 0.1 (matches the previous circle
;; symbols' size), colored per colorspec
(defun AS4:shape-entities (shape colorspec / r cp)
  (setq r 0.1)
  (setq cp (AS4:color-pair colorspec))
  (cond
    ((= shape "Triangle") (AS4:polygon-lines 3 r cp))
    ((= shape "Square") (AS4:polygon-lines 4 r cp))
    ((= shape "Hexagon") (AS4:polygon-lines 6 r cp))
    (t (list (list (cons 0 "CIRCLE") (cons 8 "0") cp (cons 10 (list 0.0 0.0 0.0)) (cons 40 r))))
  )
)

;; center marker, colored per colorspec
(defun AS4:marker-entities (marker colorspec / cp)
  (setq cp (AS4:color-pair colorspec))
  (cond
    ((= marker "X")
      (list
        (list (cons 0 "LINE") (cons 8 "0") cp (cons 10 (list -0.06 -0.06 0.0)) (cons 11 (list 0.06 0.06 0.0)))
        (list (cons 0 "LINE") (cons 8 "0") cp (cons 10 (list -0.06 0.06 0.0)) (cons 11 (list 0.06 -0.06 0.0)))
      )
    )
    ((= marker "Dot")
      (list (list (cons 0 "SOLID") (cons 8 "0") cp
        (cons 10 (list -0.02 -0.02 0.0)) (cons 11 (list 0.02 -0.02 0.0))
        (cons 12 (list -0.02 0.02 0.0)) (cons 13 (list 0.02 0.02 0.0))))
    )
    ((= marker "Circle")
      (list (list (cons 0 "CIRCLE") (cons 8 "0") cp (cons 10 (list 0.0 0.0 0.0)) (cons 40 0.03)))
    )
    (t ;; "Crosshair" - extends slightly beyond the outer shape
      (list
        (list (cons 0 "LINE") (cons 8 "0") cp (cons 10 (list -0.14 0.0 0.0)) (cons 11 (list 0.14 0.0 0.0)))
        (list (cons 0 "LINE") (cons 8 "0") cp (cons 10 (list 0.0 -0.14 0.0)) (cons 11 (list 0.0 0.14 0.0)))
      )
    )
  )
)

;; full geometry (shape + marker) for a customizable symbol type
(defun AS4:symbol-geometry (shape marker colorspec crosscolorspec)
  (append (AS4:shape-entities shape colorspec) (AS4:marker-entities marker crosscolorspec))
)

(defun AS4:attdef-entry-diag ()
  (list (cons 0 "ATTDEF") (cons 8 "0") (cons 10 (list 0.15 0.15 0.0))
        (cons 40 *AS4:TEXTHEIGHT*) (cons 1 "") (cons 2 "LABEL") (cons 3 "Label") (cons 70 0))
)

;; centered, placed directly above localpos - used by the height point so
;; its label sits centered above the triangle instead of diagonally offset
(defun AS4:attdef-entry-centered (localpos)
  (list (cons 0 "ATTDEF") (cons 8 "0") (cons 10 localpos) (cons 11 localpos)
        (cons 40 *AS4:TEXTHEIGHT*) (cons 1 "") (cons 2 "LABEL") (cons 3 "Label") (cons 70 0)
        (cons 72 1) (cons 73 2))
)

;; second, invisible attribute carrying the full point_ID - shows up in
;; the Properties palette under "Attributes" without cluttering the
;; drawing with extra visible text (flag 70 = 1 = invisible)
(defun AS4:attdef-entry-pointid ()
  (list (cons 0 "ATTDEF") (cons 8 "0") (cons 10 (list 0.0 0.0 0.0))
        (cons 40 *AS4:TEXTHEIGHT*) (cons 1 "") (cons 2 "POINT_ID") (cons 3 "Point ID") (cons 70 1))
)

;; generic invisible ATTDEF for a given tag - used to mirror the Xdata
;; fields as real, Properties-palette-visible block attributes
(defun AS4:attdef-entry-invisible (tag)
  (list (cons 0 "ATTDEF") (cons 8 "0") (cons 10 (list 0.0 0.0 0.0))
        (cons 40 *AS4:TEXTHEIGHT*) (cons 1 "") (cons 2 tag) (cons 3 tag) (cons 70 1))
)
(defun AS4:attdef-entries-invisible (tags)
  (mapcar 'AS4:attdef-entry-invisible tags)
)

;; tag sets mirroring the Xdata attached to each symbol type
(setq *AS4:TAGS-COMMON* '("ID" "IDSTRING" "CODE" "SHPTYPE" "SHPTYPE_N" "POINT_PROP" "CONTIN_NR" "ID_CODE" "CODE_ID" "ORIGINFILE"))
(setq *AS4:TAGS-SAMPLEFIND* (append *AS4:TAGS-COMMON* '("F_MA_S_ME")))
(setq *AS4:TAGS-STATION* '("TYPE" "SHPTYPE_N" "CODE" "ORIGINFILE"))
(setq *AS4:TAGS-SECTIONNAIL* '("ID" "IDSTRING" "CODE" "SHPTYPE" "SHPTYPE_N" "POINT_PROP" "CONTIN_NR" "ID_CODE" "CODE_ID" "ORIGINFILE"))

;; Fixed point (91): shape/marker/colors customizable via AS4SETSYMBOL.
(defun AS4:def-fixed ()
  (AS4:ensure-block "AS4_Fixed"
    (append (AS4:symbol-geometry *AS4:SHAPE-FIXED* *AS4:MARKER-FIXED* *AS4:COLOR-FIXED* *AS4:CROSSCOLOR-FIXED*)
      (list (AS4:attdef-entry-diag) (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-COMMON*)
    )
  )
)

;; Station point (free station / backsight coordinate): customizable via
;; AS4SETSYMBOL, same as the other symbol types.
(defun AS4:def-station ()
  (AS4:ensure-block "AS4_Station"
    (append (AS4:symbol-geometry *AS4:SHAPE-STATION* *AS4:MARKER-STATION* *AS4:COLOR-STATION* *AS4:CROSSCOLOR-STATION*)
      (list (AS4:attdef-entry-diag) (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-STATION*)
    )
  )
)

;; Sample point (51): shape/marker/colors customizable via AS4SETSYMBOL.
(defun AS4:def-sample ()
  (AS4:ensure-block "AS4_Sample"
    (append (AS4:symbol-geometry *AS4:SHAPE-SAMPLE* *AS4:MARKER-SAMPLE* *AS4:COLOR-SAMPLE* *AS4:CROSSCOLOR-SAMPLE*)
      (list (AS4:attdef-entry-diag) (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-SAMPLEFIND*)
    )
  )
)

;; Find point (71): shape/marker/colors customizable via AS4SETSYMBOL.
(defun AS4:def-find ()
  (AS4:ensure-block "AS4_Find"
    (append (AS4:symbol-geometry *AS4:SHAPE-FIND* *AS4:MARKER-FIND* *AS4:COLOR-FIND* *AS4:CROSSCOLOR-FIND*)
      (list (AS4:attdef-entry-diag) (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-SAMPLEFIND*)
    )
  )
)

;; 3D marker (81, e.g. photogrammetry target): shape/marker/colors
;; customizable via AS4SETSYMBOL.
(defun AS4:def-marker3d ()
  (AS4:ensure-block "AS4_Marker3D"
    (append (AS4:symbol-geometry *AS4:SHAPE-MARKER3D* *AS4:MARKER-MARKER3D* *AS4:COLOR-MARKER3D* *AS4:CROSSCOLOR-MARKER3D*)
      (list (AS4:attdef-entry-diag) (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-COMMON*)
    )
  )
)

;; Height point (01): small inverted triangle, apex = actual coordinate,
;; a crossbar running exactly through the apex (the coordinate itself),
;; dark grey. Deliberately very small since height points are typically
;; numerous on a single excavation.
(defun AS4:def-height ()
  (AS4:ensure-block "AS4_Height"
    (append (list
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 250) (cons 10 (list -0.016 0.036 0.0)) (cons 11 (list 0.016 0.036 0.0)))
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 250) (cons 10 (list 0.016 0.036 0.0)) (cons 11 (list 0.0 0.0 0.0)))
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 250) (cons 10 (list 0.0 0.0 0.0)) (cons 11 (list -0.016 0.036 0.0)))
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 250) (cons 10 (list -0.009 0.0 0.0)) (cons 11 (list 0.009 0.0 0.0)))
      (AS4:attdef-entry-centered (list 0.0 0.05 0.0))
      (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-COMMON*)
    )
  )
)

;; Section nail (00): grey X, crossing point = actual coordinate, plus a
;; slightly thicker grey shaft coming straight down (in Z) onto the
;; coordinate - drawn along the block's local Z axis so it renders as a
;; true vertical in 3D/isometric views.
(defun AS4:def-sectionnail ()
  (AS4:ensure-block "AS4_SectionNail"
    (append (list
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 8) (cons 10 (list -0.12 -0.12 0.0)) (cons 11 (list 0.12 0.12 0.0)))
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 8) (cons 10 (list -0.12 0.12 0.0)) (cons 11 (list 0.12 -0.12 0.0)))
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 8) (cons 370 30) (cons 10 (list 0.0 0.0 0.0)) (cons 11 (list 0.0 0.0 0.3)))
      (AS4:attdef-entry-diag)
      (AS4:attdef-entry-pointid))
      (AS4:attdef-entries-invisible *AS4:TAGS-SECTIONNAIL*)
    )
  )
)

;; Vertex marker: a unit circle (green), scaled at insertion time by
;; AS4VERTEXRADIUS, carrying only an invisible POINT_ID attribute - no
;; visible LABEL, since vertex points are not meant to be individually
;; labelled in the drawing.
(defun AS4:def-vertex ()
  (AS4:ensure-block "AS4_Vertex"
    (list
      (list (cons 0 "CIRCLE") (cons 8 "0") (cons 62 3) (cons 10 (list 0.0 0.0 0.0)) (cons 40 1.0))
      (AS4:attdef-entry-pointid)
    )
  )
)

;; inserts an AS4_Vertex block reference at pt, scaled to AS4VERTEXRADIUS,
;; with its POINT_ID attribute set - this is how a vertex marker gets a
;; "Name" in the Properties palette (only block references have one)
(defun AS4:insert-vertex (pt layer pid / ins)
  (setq ins (entmakex (list
    (cons 0 "INSERT") (cons 8 layer) (cons 2 "AS4_Vertex") (cons 10 pt)
    (cons 41 *AS4:VERTEXRADIUS*) (cons 42 *AS4:VERTEXRADIUS*) (cons 43 *AS4:VERTEXRADIUS*)
    (cons 50 0.0) (cons 66 1))))
  (entmake (list (cons 0 "ATTRIB") (cons 8 layer) (cons 10 pt)
    (cons 40 *AS4:TEXTHEIGHT*) (cons 1 pid) (cons 2 "POINT_ID") (cons 70 1)))
  (entmake (list (cons 0 "SEQEND") (cons 8 layer)))
  ins
)

;; (re)defines every symbol block once - called at the start of AS4:run-import
(defun AS4:define-all-symbols ()
  (AS4:def-fixed) (AS4:def-station) (AS4:def-sample) (AS4:def-find)
  (AS4:def-marker3d) (AS4:def-height) (AS4:def-sectionnail) (AS4:def-vertex)
)

;; label position in world coordinates, scaled with the symbol
(defun AS4:symbol-label-worldpos (pt)
  (list (+ (car pt) (* 0.15 *AS4:SYMBOLSCALE*)) (+ (cadr pt) (* 0.15 *AS4:SYMBOLSCALE*)) (caddr pt))
)

;; inserts a symbol block reference together with its LABEL attribute, an
;; invisible POINT_ID attribute, and any further invisible attributes
;; passed in "extra" (a list of (tag . value) pairs) that mirror the
;; entity's Xdata as real, Properties-palette-visible block attributes.
(defun AS4:insert-symbol-labeled (blockname pt symlayer txtlayer labeltext colorgroup colorval height pid extra / ins pair)
  (setq ins (entmakex (list
    (cons 0 "INSERT") (cons 8 symlayer) (cons 2 blockname) (cons 10 pt)
    (cons 41 *AS4:SYMBOLSCALE*) (cons 42 *AS4:SYMBOLSCALE*) (cons 43 *AS4:SYMBOLSCALE*)
    (cons 50 0.0) (cons 66 1))))
  (entmake (append
    (list (cons 0 "ATTRIB") (cons 8 txtlayer) (cons 10 (AS4:symbol-label-worldpos pt))
          (cons 40 height) (cons 1 labeltext) (cons 2 "LABEL") (cons 70 0))
    (if (= colorgroup 420) (list (cons 420 colorval)) (list (cons 62 colorval)))
  ))
  (entmake (list (cons 0 "ATTRIB") (cons 8 symlayer) (cons 10 pt)
    (cons 40 height) (cons 1 pid) (cons 2 "POINT_ID") (cons 70 1)))
  (foreach pair extra
    (entmake (list (cons 0 "ATTRIB") (cons 8 symlayer) (cons 10 pt)
      (cons 40 height) (cons 1 (vl-princ-to-string (cdr pair))) (cons 2 (car pair)) (cons 70 1)))
  )
  (entmake (list (cons 0 "SEQEND") (cons 8 symlayer)))
  ins
)

;; like AS4:insert-symbol-labeled, but places the label centered directly
;; above the insertion point (gap = local distance above pt, scaled with
;; the symbol) instead of the default diagonal offset - used for the
;; height point so its value sits centered over the triangle.
(defun AS4:insert-symbol-labeled-centered (blockname pt symlayer txtlayer labeltext colorgroup colorval height gap pid extra / ins pos pair)
  (setq pos (list (car pt) (+ (cadr pt) (* gap *AS4:SYMBOLSCALE*)) (caddr pt)))
  (setq ins (entmakex (list
    (cons 0 "INSERT") (cons 8 symlayer) (cons 2 blockname) (cons 10 pt)
    (cons 41 *AS4:SYMBOLSCALE*) (cons 42 *AS4:SYMBOLSCALE*) (cons 43 *AS4:SYMBOLSCALE*)
    (cons 50 0.0) (cons 66 1))))
  (entmake (append
    (list (cons 0 "ATTRIB") (cons 8 txtlayer) (cons 10 pos) (cons 11 pos)
          (cons 40 height) (cons 1 labeltext) (cons 2 "LABEL") (cons 70 0)
          (cons 72 1) (cons 73 2))
    (if (= colorgroup 420) (list (cons 420 colorval)) (list (cons 62 colorval)))
  ))
  (entmake (list (cons 0 "ATTRIB") (cons 8 symlayer) (cons 10 pt)
    (cons 40 height) (cons 1 pid) (cons 2 "POINT_ID") (cons 70 1)))
  (foreach pair extra
    (entmake (list (cons 0 "ATTRIB") (cons 8 symlayer) (cons 10 pt)
      (cons 40 height) (cons 1 (vl-princ-to-string (cdr pair))) (cons 2 (car pair)) (cons 70 1)))
  )
  (entmake (list (cons 0 "SEQEND") (cons 8 symlayer)))
  ins
)

;; -----------------------------------------------------------------------
;; posthole: 32-vertex circular polygon, radius from container letter.
;; Vertices are generated, not measured, so they are NOT added to the
;; vertices layer. Colored/weighted the same as shape types 02/03/61
;; (see AS4:line-style), since postholes are also a "feature" polygon.
;; -----------------------------------------------------------------------
(defun AS4:make-posthole (cx cy cz radius layer shptype xdattrs / i ang header n)
  (setq n 32)
  (setq header (entmakex (append (list
    '(0 . "POLYLINE") (cons 8 layer) '(66 . 1)
    (list 10 0.0 0.0 0.0) '(70 . 9)) ;; 8 = 3D polyline, +1 closed
    (AS4:style-extra (AS4:line-style shptype))
    (AS4:xdata-group xdattrs)
  )))
  (setq i 0)
  (while (< i n)
    (setq ang (* i (/ (* 2.0 pi) n)))
    (entmake (list '(0 . "VERTEX") (cons 8 layer)
      (list 10 (+ cx (* radius (cos ang))) (+ cy (* radius (sin ang))) cz)
      '(70 . 32)))
    (setq i (1+ i))
  )
  (entmake (list '(0 . "SEQEND") (cons 8 layer)))
  header
)

;; -----------------------------------------------------------------------
;; feature-count summary helpers
;; -----------------------------------------------------------------------
(defun AS4:bump-assoc (key lst / pair)
  (setq pair (assoc key lst))
  (if pair
    (subst (cons key (1+ (cdr pair))) pair lst)
    (cons (cons key 1) lst)
  )
)

;; -----------------------------------------------------------------------
;; core import routine (called by AS4IMPORT)
;; -----------------------------------------------------------------------
;; splits a group's points (already in original file-reading order) into
;; separate runs whenever the sequence number resets or repeats (<=
;; previous). This is how two independent measurements that accidentally
;; share the same shpcontainer (feature+container+shptype) get preserved
;; as distinct lines/polygons instead of being merged into one geometry
;; that jumps between unrelated points - each run's sequence numbers are
;; expected to start near 1, per the ArchSurv convention.
(defun AS4:split-runs (pts / prevseq runs current p)
  (setq runs '() current '() prevseq nil)
  (foreach p pts
    (if (and prevseq (<= (car p) prevseq))
      (progn (setq runs (cons (reverse current) runs)) (setq current (list p)))
      (setq current (cons p current))
    )
    (setq prevseq (car p))
  )
  (if current (setq runs (cons (reverse current) runs)))
  (reverse runs)
)

(defun AS4:run-import (originfile / f line parts pid xv yv zv code parsed
                        feature container shptype seq idnum idstring idcode codeid
                        cat layername pt ent groups key grp gdata sorted
                        gfeature gcontainer gshptype gcat glayer zvals maxh minh
                        firstpt closed flags header vname style radius
                        skipcount skiplog pblk stationcount
                        runlist runcount runidx run splitlog symlayer p s c sc)

  (AS4:define-all-symbols)

  (setq groups '())
  (setq skipcount 0)
  (setq stationcount 0)
  (setq skiplog '())
  (setq splitlog '())
  (setq *AS4:LABELED-LAYERS* '())
  (setq *AS4:COUNTS* '())

  (setq f (open originfile "r"))
  (if (not f)
    (progn (princ "\nCould not open file.") (princ) (exit))
  )

  (while (setq line (read-line f))
    (setq line (AS4:rtrim line))
    (if (> (strlen line) 0)
      (progn
        (setq parts (AS4:split-auto line))
        ;; a 4-column line (no code field) is accepted - treated as if a
        ;; 5th column with value "-" were present
        (if (= (length parts) 4) (setq parts (append parts (list "-"))))
        (if (>= (length parts) 5)
          (progn
            (setq pid  (AS4:rtrim (nth 0 parts))
                  xv   (AS4:safe-atof (nth 1 parts))
                  yv   (AS4:safe-atof (nth 2 parts))
                  zv   (AS4:safe-atof (nth 3 parts))
                  code (AS4:rtrim (nth 4 parts)))
            (setq pt (list xv yv zv))

            (cond
              ;; --- station point: numeric ID with '.', '-' or '_' ---
              ((AS4:station-id-p pid)
                (AS4:ensure-layer "as4_station")
                (AS4:ensure-layer "as4_txt_station")
                (setq ent (AS4:insert-symbol-labeled "AS4_Station" pt "as4_station" "as4_txt_station"
                            pid (car *AS4:TEXTCOLOR-STATION*) (cdr *AS4:TEXTCOLOR-STATION*) *AS4:TEXTSIZE-STATION* pid
                            (list (cons "TYPE" "station") (cons "SHPTYPE_N" "station_setup")
                                  (cons "CODE" code) (cons "ORIGINFILE" originfile))))
                (AS4:add-xdata ent (list
                  (cons "point_ID" pid) (cons "type" "station")
                  (cons "shptype_n" "station_setup")
                  (cons "code" code) (cons "originfile" originfile)))
                (setq stationcount (1+ stationcount))
                (setq *AS4:COUNTS* (AS4:bump-assoc "station" *AS4:COUNTS*))
              )

              ;; --- regular ArchSurv point_ID ---
              (T
                (setq parsed (AS4:parse-id pid))
                (if parsed
                  (progn
                    (setq feature   (nth 0 parsed)
                          container (nth 1 parsed)
                          shptype   (nth 2 parsed)
                          seq       (nth 3 parsed))
                    (setq idnum    (atoi feature)
                          idstring feature
                          idcode   (strcat feature "_" code)
                          codeid   (strcat code "_" feature))
                    (setq cat (AS4:category shptype))
                    (setq layername (AS4:ensure-layer
                      (AS4:layer-value idnum idstring idcode codeid code)))

                    (cond
                      ;; --- standalone point (pointdata) ---
                      ((= cat "point")
                        (cond
                          ((= shptype "91")
                            (setq symlayer (AS4:point-layer *AS4:MODE-FIXED* layername (AS4:clean-id idnum idstring) "fixed_" "_fixed" "as4_fixed-points" "fixed" seq))
                            (AS4:ensure-layer "as4_txt_fixed-points")
                            (setq ent (AS4:insert-symbol-labeled "AS4_Fixed" pt symlayer "as4_txt_fixed-points"
                                        (strcat "fix_" (itoa seq)) (car *AS4:TEXTCOLOR-FIXED*) (cdr *AS4:TEXTCOLOR-FIXED*) *AS4:TEXTSIZE-FIXED* pid
                                        (list (cons "ID" idnum) (cons "IDSTRING" idstring) (cons "CODE" code)
                                              (cons "SHPTYPE" shptype) (cons "SHPTYPE_N" (AS4:shptype-name shptype))
                                              (cons "POINT_PROP" container) (cons "CONTIN_NR" seq)
                                              (cons "ID_CODE" idcode) (cons "CODE_ID" codeid) (cons "ORIGINFILE" originfile))))
                          )
                          ((= shptype "51")
                            (setq symlayer (AS4:point-layer *AS4:MODE-SAMPLES* layername (AS4:clean-id idnum idstring) "samples_" "_sample" "as4_samples" "sample" seq))
                            (AS4:ensure-layer "as4_txt_samples")
                            (setq ent (AS4:insert-symbol-labeled "AS4_Sample" pt symlayer "as4_txt_samples"
                                        (strcat "sample_" (itoa seq)) (car *AS4:TEXTCOLOR-SAMPLE*) (cdr *AS4:TEXTCOLOR-SAMPLE*) *AS4:TEXTSIZE-SAMPLE* pid
                                        (list (cons "ID" idnum) (cons "IDSTRING" idstring) (cons "CODE" code)
                                              (cons "SHPTYPE" shptype) (cons "SHPTYPE_N" (AS4:shptype-name shptype))
                                              (cons "POINT_PROP" container) (cons "CONTIN_NR" seq)
                                              (cons "ID_CODE" idcode) (cons "CODE_ID" codeid) (cons "ORIGINFILE" originfile)
                                              (cons "F_MA_S_ME" (AS4:material-method shptype container)))))
                          )
                          ((= shptype "71")
                            (setq symlayer (AS4:point-layer *AS4:MODE-FINDS* layername (AS4:clean-id idnum idstring) "finds_" "_find" "as4_finds" "find" seq))
                            (AS4:ensure-layer "as4_txt_finds")
                            (setq ent (AS4:insert-symbol-labeled "AS4_Find" pt symlayer "as4_txt_finds"
                                        (strcat "find_" (itoa seq)) (car *AS4:TEXTCOLOR-FIND*) (cdr *AS4:TEXTCOLOR-FIND*) *AS4:TEXTSIZE-FIND* pid
                                        (list (cons "ID" idnum) (cons "IDSTRING" idstring) (cons "CODE" code)
                                              (cons "SHPTYPE" shptype) (cons "SHPTYPE_N" (AS4:shptype-name shptype))
                                              (cons "POINT_PROP" container) (cons "CONTIN_NR" seq)
                                              (cons "ID_CODE" idcode) (cons "CODE_ID" codeid) (cons "ORIGINFILE" originfile)
                                              (cons "F_MA_S_ME" (AS4:material-method shptype container)))))
                          )
                          ((= shptype "01")
                            (setq symlayer (AS4:point-layer *AS4:MODE-HEIGHTS* layername (AS4:clean-id idnum idstring) "heights_" "_heights" "as4_heights" "height" seq))
                            (AS4:ensure-layer "as4_txt_heights")
                            (setq ent (AS4:insert-symbol-labeled-centered "AS4_Height" pt symlayer "as4_txt_heights"
                                        (rtos zv 2 2) (car *AS4:TEXTCOLOR-HEIGHT*) (cdr *AS4:TEXTCOLOR-HEIGHT*) *AS4:TEXTSIZE-HEIGHT* 0.05 pid
                                        (list (cons "ID" idnum) (cons "IDSTRING" idstring) (cons "CODE" code)
                                              (cons "SHPTYPE" shptype) (cons "SHPTYPE_N" (AS4:shptype-name shptype))
                                              (cons "POINT_PROP" container) (cons "CONTIN_NR" seq)
                                              (cons "ID_CODE" idcode) (cons "CODE_ID" codeid) (cons "ORIGINFILE" originfile))))
                          )
                          ((= shptype "81")
                            (setq symlayer (AS4:point-layer *AS4:MODE-MARKERS* layername (AS4:clean-id idnum idstring) "3d-markers_" "_3D-marker" "as4_3d-markers" "3d-marker" seq))
                            (AS4:ensure-layer "as4_txt_3d-markers")
                            (setq ent (AS4:insert-symbol-labeled "AS4_Marker3D" pt symlayer "as4_txt_3d-markers"
                                        (strcat (itoa idnum) "_" (itoa seq)) (car *AS4:TEXTCOLOR-MARKER3D*) (cdr *AS4:TEXTCOLOR-MARKER3D*) *AS4:TEXTSIZE-MARKER3D* pid
                                        (list (cons "ID" idnum) (cons "IDSTRING" idstring) (cons "CODE" code)
                                              (cons "SHPTYPE" shptype) (cons "SHPTYPE_N" (AS4:shptype-name shptype))
                                              (cons "POINT_PROP" container) (cons "CONTIN_NR" seq)
                                              (cons "ID_CODE" idcode) (cons "CODE_ID" codeid) (cons "ORIGINFILE" originfile))))
                          )
                          (t
                            (setq ent (entmakex (list '(0 . "POINT") (cons 8 layername) (cons 10 pt))))
                            (AS4:label-layer-once layername idnum pt)
                          )
                        )
                        (AS4:add-xdata ent (append (list
                          (cons "ID" idnum) (cons "IDstring" idstring)
                          (cons "code" code) (cons "shptype" shptype)
                          (cons "shptype_n" (AS4:shptype-name shptype))
                          (cons "point_prop" container) (cons "contin-nr" seq)
                          (cons "point_ID" pid) (cons "ID_code" idcode)
                          (cons "code_ID" codeid) (cons "originfile" originfile))
                          (if (or (= shptype "51") (= shptype "71"))
                            (list (cons "f_ma/s_me" (AS4:material-method shptype container)))
                            nil
                          )
                        ))
                        (setq *AS4:COUNTS* (AS4:bump-assoc shptype *AS4:COUNTS*))
                      )

                      ;; --- posthole: synthetic 32-vertex circle, no grouping ---
                      ((= cat "posthole")
                        (setq radius (AS4:posthole-radius container))
                        (setq header (AS4:make-posthole xv yv zv radius layername shptype (list
                          (cons "ID" idnum) (cons "IDstring" idstring)
                          (cons "code" code) (cons "shptype" shptype)
                          (cons "shptype_n" (AS4:shptype-name shptype))
                          (cons "point_prop" container) (cons "contin-nr" seq)
                          (cons "point_ID" pid) (cons "geom_ID" (strcat feature container shptype))
                          (cons "ID_code" idcode) (cons "code_ID" codeid)
                          ;; a posthole is generated from a single measured point, so
                          ;; its elevation "range" is just that one point's own Z
                          (cons "maxH" zv) (cons "minH" zv)
                          (cons "diameter_cm" (* 200.0 radius))
                          (cons "originfile" originfile))))
                        (AS4:label-layer-once layername idnum pt)
                        (setq *AS4:COUNTS* (AS4:bump-assoc shptype *AS4:COUNTS*))
                      )

                      ;; --- vertex of a polyline/polygon (incl. section nail 00) ---
                      ((or (= cat "polyline") (= cat "polygon"))
                        (setq vname (AS4:ensure-layer "as4_vertices"))
                        (setq ent (AS4:insert-vertex pt vname pid))
                        (AS4:add-xdata ent (list
                          (cons "ID" idnum) (cons "IDstring" idstring)
                          (cons "code" code) (cons "shptype" shptype)
                          (cons "shptype_n" (AS4:shptype-name shptype))
                          (cons "point_prop" container) (cons "contin-nr" seq)
                          (cons "point_ID" pid)))

                        (if (= shptype "00")
                          (progn
                            (setq symlayer (AS4:point-layer *AS4:MODE-SECTIONS* layername (AS4:clean-id idnum idstring) "sections_" "_section" "as4_section-nails" "section" seq))
                            (AS4:ensure-layer "as4_txt_section-nails")
                            (setq pblk (AS4:insert-symbol-labeled "AS4_SectionNail" pt symlayer "as4_txt_section-nails"
                                         (strcat "sec_" (itoa idnum) "_" (itoa seq)) (car *AS4:TEXTCOLOR-SECTION*) (cdr *AS4:TEXTCOLOR-SECTION*) *AS4:TEXTSIZE-SECTION* pid
                                         (list (cons "ID" idnum) (cons "IDSTRING" idstring) (cons "CODE" code)
                                               (cons "SHPTYPE" shptype) (cons "SHPTYPE_N" (AS4:shptype-name shptype))
                                               (cons "POINT_PROP" container) (cons "CONTIN_NR" seq)
                                               (cons "ID_CODE" idcode) (cons "CODE_ID" codeid) (cons "ORIGINFILE" originfile))))
                            (AS4:add-xdata pblk (list
                              (cons "ID" idnum) (cons "IDstring" idstring)
                              (cons "code" code) (cons "shptype" shptype) (cons "shptype_n" (AS4:shptype-name shptype))
                              (cons "point_prop" container) (cons "contin-nr" seq)
                              (cons "ID_code" idcode) (cons "code_ID" codeid) (cons "originfile" originfile)
                              (cons "point_ID" pid)))
                          )
                          (AS4:label-layer-once layername idnum pt)
                        )

                        (setq key (strcat feature container shptype))
                        (setq grp (assoc key groups))
                        (setq gdata (list seq xv yv zv code layername idnum idstring idcode codeid feature container shptype))
                        (if grp
                          (setq groups (subst
                            (cons key (cons gdata (cdr grp))) grp groups))
                          (setq groups (cons (cons key (list gdata)) groups))
                        )
                      )

                      ;; --- unrecognized shape type: structurally valid point_ID
                      ;; (10 chars, digits+letter+digits) but the 2-digit shape
                      ;; type code is not part of the known AS4QGIS spectrum ---
                      (t
                        (princ (strcat "\nUnrecognized shape type '" shptype "' skipped: " pid))
                        (setq skipcount (1+ skipcount))
                        (setq skiplog (cons (strcat pid " | unrecognized shape type " shptype) skiplog))
                      )
                    )
                  )
                  (progn
                    (princ (strcat "\nInvalid point_ID skipped: " pid))
                    (setq skipcount (1+ skipcount))
                    (setq skiplog (cons (strcat pid " | " line) skiplog))
                  )
                )
              )
            )
          )
          (progn
            (princ (strcat "\nSkipped line (not enough columns): " line))
            (setq skipcount (1+ skipcount))
            (setq skiplog (cons (strcat "(not enough columns) | " line) skiplog))
          )
        )
      )
    )
  )
  (close f)

;; --- build polylines/polygons from the grouped points ---
  (foreach grp groups
    (setq runlist (AS4:split-runs (reverse (cdr grp))))
    (setq runcount (length runlist))
    (setq runidx 0)
    (if (> runcount 1)
      (setq splitlog (cons (cons (car grp) runcount) splitlog))
    )
    (foreach run runlist
      (setq runidx (1+ runidx))
      (setq sorted (vl-sort run '(lambda (a b) (< (nth 0 a) (nth 0 b)))))
      (setq firstpt (car sorted))
      (setq gfeature   (nth 10 firstpt)
            gcontainer (nth 11 firstpt)
            gshptype   (nth 12 firstpt)
            glayer     (nth 5 firstpt))
      (setq gcat (AS4:category gshptype))
      (setq closed (or (= gcat "polygon") (= gshptype "33")))
      (setq flags (if closed 9 8))
      (setq style (AS4:line-style gshptype))

      ;; trench boundary lines/polygons (92/93) always go to a dedicated
      ;; "as4_trench_<code>" layer, independent of AS4SETLAYER
      (if (member gshptype '("92" "93"))
        (setq glayer (AS4:ensure-layer (strcat "as4_trench_" (nth 4 firstpt))))
      )

      (setq zvals (mapcar '(lambda (p) (nth 3 p)) sorted))
      (setq maxh (apply 'max zvals))
      (setq minh (apply 'min zvals))

      (setq header (entmakex (append (list
        '(0 . "POLYLINE")
        (cons 8 glayer)
        '(66 . 1)
        (list 10 0.0 0.0 0.0)
        (cons 70 flags))
        (AS4:style-extra style)
        (AS4:xdata-group (list
          (cons "ID" (nth 6 firstpt)) (cons "IDstring" (nth 7 firstpt))
          (cons "shptype" gshptype) (cons "shptype_n" (AS4:shptype-name gshptype))
          (cons "code" (nth 4 firstpt))
          (cons "geom_ID" (if (> runcount 1)
                             (strcat gfeature gcontainer gshptype "_" (itoa runidx))
                             (strcat gfeature gcontainer gshptype)))
          (cons "ID_code" (nth 8 firstpt)) (cons "code_ID" (nth 9 firstpt))
          (cons "maxH" maxh) (cons "minH" minh)
          (cons "originfile" originfile)))
      )))

      (foreach p sorted
        (entmake (list
          '(0 . "VERTEX")
          (cons 8 glayer)
          (list 10 (nth 1 p) (nth 2 p) (nth 3 p))
          '(70 . 32)))
      )
      (entmake (list '(0 . "SEQEND") (cons 8 glayer)))

      (setq *AS4:COUNTS* (AS4:bump-assoc gshptype *AS4:COUNTS*))
    )
  )

  ;; --- command-line report for skipped lines and split shpcontainers ---
  (if (> skipcount 0)
    (progn
      (princ (strcat "\n--- " (itoa skipcount) " skipped line(s) (invalid point_ID/structure) ---"))
      (foreach s (reverse skiplog) (princ (strcat "\n" s)))
    )
  )
  (if splitlog
    (progn
      (princ (strcat "\n--- " (itoa (length splitlog)) " shpcontainer(s) split into separate objects ---"))
      (foreach sc (reverse splitlog)
        (princ (strcat "\n" (car sc) ": " (itoa (cdr sc)) " distinct lines/polygons"))
      )
    )
  )
  (if (> stationcount 0)
    (princ (strcat "\n" (itoa stationcount) " station point(s) detected and placed."))
  )

  ;; --- import summary ---
  (princ "\n--- Import summary ---")
  (foreach c (reverse *AS4:COUNTS*)
    (princ (strcat "\n" (AS4:shptype-name (car c)) ": " (itoa (cdr c))))
  )
  (princ (strcat "\nDistinct feature layers: " (itoa (length *AS4:LABELED-LAYERS*))))

  (command "_.ZOOM" "_E")
  (princ (strcat "\nAS4IMPORT complete. Layer field: " *AS4:LAYERFIELD*))
  (princ)
)

;; -----------------------------------------------------------------------
;; AS4IMPORT: prompt for a file and import it
;; -----------------------------------------------------------------------
(defun c:AS4IMPORT ( / originfile)
  ;; getfiled has no concept of a true multi-entry "Files of type"
  ;; dropdown (distinct named filters like "All Files"/"CSV Files"/...) -
  ;; confirmed across multiple official Autodesk documentation versions
  ;; and by testing here: its ext argument is a single extension string,
  ;; nothing more. Two alternatives were tried and both fell short of
  ;; what was actually wanted: ext="" (shows everything, no ArchSurv
  ;; focus at all) and a pre-dialog keyword prompt to pick one specific
  ;; extension first (an extra step, and still only one type at a time).
  ;; Back to the original single call, letting the dialog's own default
  ;; extension box start on "csv" with "txt"/"asc" still reachable by
  ;; editing that box - not a real dropdown, but keeps every file picked
  ;; from this dialog an ArchSurv candidate, which matters more.
  (setq originfile (getfiled "Select ArchSurv text file" "" "csv;txt;asc" 4))
  (if originfile
    (AS4:run-import originfile)
    (progn (princ "\nCancelled.") (princ))
  )
)

;; =========================================================================
;; AS4XPORTPOINTDATACSV: writes every point symbol in the drawing out as a
;; CSV file, reading its actual block attribute VALUES (so any manual
;; correction made in the Properties palette after import is respected,
;; rather than recomputing everything fresh from point_ID). x/y/z come
;; from the block's own insertion point; maxH/minH are aggregated across
;; every point sharing the same ID in a single pass over the selection.
;;
;; Deliberately structured so the "collect" and "write" steps are two
;; separate loops over two separate lists (a plain indexed loop to build
;; a list of raw per-point data, then a foreach to write it out) rather
;; than two indexed loops sharing one counter variable - that structure
;; previously caused the second loop to silently run zero times while
;; the header (written unconditionally beforehand) still appeared,
;; producing a CSV with headers but no data rows.
;; =========================================================================

;; walks an INSERT's ATTRIB children (up to its SEQEND) and returns them
;; as an assoc list of (TAG . VALUE)
(defun AS4:get-attributes (ent / e edata out)
  (setq out '())
  (setq e (entnext ent))
  (while (and e (/= (cdr (assoc 0 (entget e))) "SEQEND"))
    (setq edata (entget e))
    (if (= (cdr (assoc 0 edata)) "ATTRIB")
      (setq out (cons (cons (cdr (assoc 2 edata)) (cdr (assoc 1 edata))) out))
    )
    (setq e (entnext e))
  )
  out
)
(defun AS4:attr-get (alist tag / p)
  (setq p (assoc tag alist))
  (if p (cdr p) "")
)

;; per-feature elevation range table: assoc list (idnum maxz minz)
(defun AS4:bump-elev (idnum z / pair)
  (setq pair (assoc idnum *AS4:ELEV*))
  (if pair
    (setq *AS4:ELEV* (subst (list idnum (max z (cadr pair)) (min z (caddr pair))) pair *AS4:ELEV*))
    (setq *AS4:ELEV* (cons (list idnum z z) *AS4:ELEV*))
  )
)
(defun AS4:get-elev (idnum / pair)
  (setq pair (assoc idnum *AS4:ELEV*))
  (if pair (list (cadr pair) (caddr pair)) (list nil nil))
)

;; pseudo-date matching AS4QGIS's Temporal Controller formula
(defun AS4:pad2 (n) (if (< n 10) (strcat "0" (itoa n)) (itoa n)))
(defun AS4:pseudo-date (h / yr fracpart frac mo)
  (if (not h) ""
    (progn
      (setq yr (+ 1000 (fix h)))
      (setq fracpart (- h (fix h)))
      (setq frac (fix (+ 0.5 (* fracpart 1000.0))))
      (if (> frac 999) (setq frac 999))
      (if (< frac 0) (setq frac 0))
      (setq mo (1+ (fix (/ frac 100.0))))
      (if (> mo 10) (setq mo 10))
      (strcat (itoa yr) "-" (AS4:pad2 mo) "-01")
    )
  )
)

;; CSV field quoting/escaping
(defun AS4:csv-escape (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (setq out (strcat out (if (= ch "\"") "\"\"" ch)))
    (setq i (1+ i))
  )
  out
)
(defun AS4:csv-field (v)
  (strcat "\"" (AS4:csv-escape (if (null v) "" (vl-princ-to-string v))) "\"")
)
(defun AS4:csv-row (vals / s first v)
  (setq s "" first T)
  (foreach v vals
    (if (not first) (setq s (strcat s ",")))
    (setq s (strcat s (AS4:csv-field v)))
    (setq first nil)
  )
  s
)

;; AS4XPORT: the only entry point for AS4CAD's export commands - the
;; point-data CSV and the combined GeoJSON export are internal
;; functions, not separate commands, reached only through this menu.
(defun c:AS4XPORT ( / kw done)
  (setq done nil)
  (while (not done)
    (initget "Csv GeoJson eXit C G X")
    (setq kw (getkword "\nAS4CAD export [Csv/GeoJson/eXit] <eXit>: "))
    (if (not kw) (setq kw "eXit"))
    (cond
      ((member kw (list "Csv" "C")) (AS4:xport-csv))
      ((member kw (list "GeoJson" "G")) (AS4:xport-geojson))
      ((member kw (list "eXit" "X")) (setq done T))
    )
  )
  (princ)
)

;; internal - AS4XPORT's "Csv" step
(defun AS4:xport-csv ( / base ss i ent attrs ox oy oz idstr pid shptype elev mx mn
                        fout rows rowdata fmt fkw)
  (initget "Raw Schema")
  (setq fkw (getkword (strcat
    "\nOutput format - Raw: point_ID,x,y,z,code (re-importable with AS4IMPORT)  Schema: full AS4QGIS attribute set"
    "\nChoice [Raw/Schema] <" *AS4:XPORT-FORMAT* ">: ")))
  (setq fmt (if fkw fkw *AS4:XPORT-FORMAT*))

  (princ "\nSelect point symbols to export (press Enter with nothing selected to export the whole drawing instead): ")
  (setq ss (ssget))
  (if (not ss) (setq ss (ssget "X")))

  (if (or (not ss) (= (sslength ss) 0))
    (princ "\nNothing selected and the drawing appears to be empty.")
    (progn
      (setq base (getfiled "AS4 point export - enter a file name" "" "csv" 1))
      (if (not base)
        (princ "\nCancelled.")
        (progn
          (setq *AS4:ELEV* '())
          (setq rows '())

          ;; step 1: collect raw per-point data + the elevation table, in one
          ;; pass. Membership is decided by whether the entity actually
          ;; carries a POINT_ID attribute (i.e. is one of AS4CAD's own
          ;; symbols), not via an Xdata ssget filter - some AutoCAD builds
          ;; do not reliably support filtering ssget by Xdata application
          ;; name (DXF group -3), so this is checked per entity instead.
          ;; AS4_Vertex block references (line/polygon vertex markers) are
          ;; skipped - only point-data symbols belong in this export.
          (setq i 0)
          (while (< i (sslength ss))
            (setq ent (ssname ss i))
            (if (and (= (cdr (assoc 0 (entget ent))) "INSERT")
                     (/= (cdr (assoc 2 (entget ent))) "AS4_Vertex"))
              (progn
                (setq attrs (AS4:get-attributes ent))
                (setq pid (AS4:attr-get attrs "POINT_ID"))
                (if (> (strlen pid) 0)
                  (progn
                    (setq ox (car (cdr (assoc 10 (entget ent)))))
                    (setq oy (cadr (cdr (assoc 10 (entget ent)))))
                    (setq oz (caddr (cdr (assoc 10 (entget ent)))))
                    (setq idstr (AS4:attr-get attrs "ID"))
                    (if (> (strlen idstr) 0) (AS4:bump-elev (atoi idstr) oz))
                    (setq rows (cons (list attrs ox oy oz) rows))
                  )
                )
              )
            )
            (setq i (1+ i))
          )
          (setq rows (reverse rows))

          (if (= (length rows) 0)
            (princ "\nNo AS4CAD point symbols (blocks with a POINT_ID attribute) found in the selection/drawing - nothing to export. Make sure you are in the same drawing where AS4IMPORT was run.")
            (progn
              ;; step 2: write the CSV - a plain foreach over the list built
              ;; above, not a second indexed loop, so it cannot silently run
              ;; zero times
              (setq fout (open base "w"))
              ;; Raw mode has no header row and no quoting, so the file is
              ;; directly usable as-is as a new AS4IMPORT input file - a
              ;; header line would otherwise be reported as one invalid/
              ;; skipped row, and quoted fields would break point_ID parsing
              (if (= fmt "Schema")
                (write-line (AS4:csv-row (list "ID" "code" "shptype_n" "shptype" "point-prop" "find-nr."
                  "sample-nr." "f_ma/s_me" "contin-nr." "point-ID" "x" "y" "z" "maxH" "minH"
                  "maxHtemp" "minHtemp" "originfile" "of_epsg" "IDstring" "ID_code" "code_ID")) fout)
              )

              (foreach rowdata rows
                (setq attrs (car rowdata) ox (nth 1 rowdata) oy (nth 2 rowdata) oz (nth 3 rowdata))
                (setq idstr (AS4:attr-get attrs "ID"))
                (setq shptype (AS4:attr-get attrs "SHPTYPE"))
                (setq elev (if (> (strlen idstr) 0) (AS4:get-elev (atoi idstr)) (list nil nil)))
                (setq mx (car elev) mn (cadr elev))
                (if (= fmt "Raw")
                  (write-line (strcat
                    (AS4:attr-get attrs "POINT_ID") ","
                    (rtos ox 2 3) "," (rtos oy 2 3) "," (rtos oz 2 3) ","
                    (AS4:attr-get attrs "CODE")) fout)
                  (write-line (AS4:csv-row (list
                    idstr
                    (AS4:attr-get attrs "CODE")
                    (AS4:attr-get attrs "SHPTYPE_N")
                    shptype
                    (AS4:attr-get attrs "POINT_PROP")
                    (if (= shptype "71") (AS4:attr-get attrs "CONTIN_NR") "")
                    (if (= shptype "51") (AS4:attr-get attrs "CONTIN_NR") "")
                    (AS4:attr-get attrs "F_MA_S_ME")
                    (AS4:attr-get attrs "CONTIN_NR")
                    (AS4:attr-get attrs "POINT_ID")
                    (rtos ox 2 3) (rtos oy 2 3) (rtos oz 2 3)
                    (if mx (rtos mx 2 3) "") (if mn (rtos mn 2 3) "")
                    (AS4:pseudo-date mx) (AS4:pseudo-date mn)
                    (AS4:attr-get attrs "ORIGINFILE") ""
                    (AS4:attr-get attrs "IDSTRING")
                    (AS4:attr-get attrs "ID_CODE")
                    (AS4:attr-get attrs "CODE_ID")
                  )) fout)
                )
              )
              (close fout)
              (princ (strcat "\nExported " (itoa (length rows)) " point(s) to: " base))
            )
          )
        )
      )
    )
  )
  (princ)
)

;; =========================================================================
;; AS4ZOOM / AS4SELECTXDATA / AS4SELECTLAYER: locate objects either by
;; feature ID/code, independent of layer naming/configuration
;; (AS4SETTINGS' Layerstructure step's chosen field and placement mode
;; change what a feature's layer is called, so matching by layer name
;; would be fragile for this) - every entity in the drawing is checked
;; directly for its own ID - block attribute "ID" for point symbols,
;; Xdata "ID" for line/polygon POLYLINE headers - and the view zooms
;; to the combined bounding box of whatever matches; or by a wildcard
;; layer-name pattern instead (AS4:find-by-layer-pattern), for when the
;; layer itself, not an AS4CAD ID/code, is what is actually known.
;; =========================================================================

;; reads one Xdata value by key ("KEY=VALUE" strings under APPID AS4QGIS) -
;; needed here since POLYLINE entities can't carry block attributes
;; like AS4:xdata-get, but pulls several keys from a single pass over
;; the entity's AS4QGIS xdata instead of one entget+scan per key -
;; used where more than one key is needed from the same entity (e.g.
;; ID and code together in AS4:entity-id-code)
(defun AS4:xdata-get-multi (ent keys / xd lst pair kv eq k out)
  (setq xd (assoc -3 (entget ent '("AS4QGIS"))))
  (setq out '())
  (if xd
    (progn
      (setq lst (cdr (assoc "AS4QGIS" (cdr xd))))
      (foreach pair lst
        (if (= (car pair) 1000)
          (progn
            (setq kv (cdr pair))
            (setq eq (vl-string-search "=" kv))
            (if eq
              (progn
                (setq k (substr kv 1 eq))
                (if (member k keys)
                  (setq out (cons (cons k (substr kv (+ eq 2))) out))
                )
              )
            )
          )
        )
      )
    )
  )
  out
)

(defun AS4:xdata-get (ent key / xd lst pair found kv eq)
  (setq xd (assoc -3 (entget ent '("AS4QGIS"))))
  (setq found nil)
  (if xd
    (progn
      (setq lst (cdr (assoc "AS4QGIS" (cdr xd))))
      (foreach pair lst
        (if (= (car pair) 1000)
          (progn
            (setq kv (cdr pair))
            (setq eq (vl-string-search "=" kv))
            (if (and eq (= (substr kv 1 eq) key))
              (setq found (substr kv (+ eq 2)))
            )
          )
        )
      )
    )
  )
  found
)

;; walks an old-style POLYLINE's VERTEX sub-entities, returns their points
(defun AS4:polyline-points (ent / e edata pts)
  (setq pts '())
  (setq e (entnext ent))
  (while (and e (/= (cdr (assoc 0 (entget e))) "SEQEND"))
    (setq edata (entget e))
    (if (= (cdr (assoc 0 edata)) "VERTEX")
      (setq pts (cons (cdr (assoc 10 edata)) pts))
    )
    (setq e (entnext e))
  )
  (reverse pts)
)

;; the feature ID of any AS4CAD entity, or nil if it doesn't have one
;; combined replacement for the old separate AS4:entity-id / AS4:entity-code
;; - a single entget and, for an INSERT, a single attribute-chain walk
;; instead of two (find-by-criteria used to call the ID lookup and the
;; code lookup separately, each redoing the same entget and the same
;; entnext walk over the attribute chain). Also skips AS4CAD's own
;; non-data blocks (AS4_Vertex, AS4_GridCross) before ever touching
;; their attribute chain, since they never carry ID/CODE attributes -
;; AS4NET in particular can add many thousands of AS4_GridCross
;; instances to a drawing, and without this check each one still paid
;; for a full (empty) attribute walk on every AS4ZOOM/AS4SELECTXDATA search.
;; Returns (id code etype), id/code nil when not present/applicable.
(defun AS4:entity-id-code (ent / edata etype bname attrs id code xdvals)
  (setq edata (entget ent))
  (setq etype (cdr (assoc 0 edata)))
  (setq id nil code nil)
  (cond
    ((= etype "INSERT")
      (setq bname (cdr (assoc 2 edata)))
      (if (not (member bname (list "AS4_Vertex" "AS4_GridCross")))
        (progn
          (setq attrs (AS4:get-attributes ent))
          (setq id (AS4:attr-get attrs "ID"))
          (if (and id (> (strlen id) 0)) (setq id (atoi id)) (setq id nil))
          (setq code (AS4:attr-get attrs "CODE"))
          (if (not (and code (> (strlen code) 0))) (setq code nil))
        )
      )
    )
    ((= etype "POLYLINE")
      (setq xdvals (AS4:xdata-get-multi ent (list "ID" "code")))
      (setq id (cdr (assoc "ID" xdvals)))
      (if id (setq id (atoi id)))
      (setq code (cdr (assoc "code" xdvals)))
    )
  )
  (list id code etype)
)

;; expands a running (minx miny maxx maxy) bounding box by one point
(defun AS4:bbox-update (pt bbox)
  (if (not bbox)
    (list (car pt) (cadr pt) (car pt) (cadr pt))
    (list (min (car pt) (nth 0 bbox)) (min (cadr pt) (nth 1 bbox))
          (max (car pt) (nth 2 bbox)) (max (cadr pt) (nth 3 bbox)))
  )
)

;; true if s is a plain (optionally signed) integer, e.g. "40" or "-7" -
;; used to tell an ID apart from a code in a mixed search term
(defun AS4:is-integer-str (s / i ch ok)
  (setq ok (> (strlen s) 0))
  (setq i 1)
  (while (and ok (<= i (strlen s)))
    (setq ch (substr s i 1))
    (if (not (or (and (>= (ascii ch) 48) (<= (ascii ch) 57))
                 (and (= i 1) (member ch '("-" "+")) (> (strlen s) 1))))
      (setq ok nil)
    )
    (setq i (1+ i))
  )
  ok
)

;; scans the drawing for entities whose ID is in idlist OR whose code
;; (case-insensitive) is in codelist - returns (found bbox). Restricted
;; to INSERT/POLYLINE via the ssget filter (a plain entity-type test,
;; not the xdata-based filtering that proved unreliable elsewhere in
;; this project) since nothing else can ever match - this alone skips
;; every TEXT label (AS4NET's Label coordinate labels included) at the C
;; level, before a single entget is spent on them.
(defun AS4:find-by-criteria (idlist codelist / ss i ent idc id code bbox found etype p)
  (setq bbox nil found '())
  (setq ss (ssget "X" (list (cons 0 "INSERT,POLYLINE"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq idc (AS4:entity-id-code ent))
        (setq id (nth 0 idc) code (nth 1 idc) etype (nth 2 idc))
        (if (or (and id (member id idlist))
                (and code (member (strcase code) codelist)))
          (progn
            (setq found (cons ent found))
            (cond
              ((= etype "INSERT")
                (setq bbox (AS4:bbox-update (cdr (assoc 10 (entget ent))) bbox))
              )
              ((= etype "POLYLINE")
                (foreach p (AS4:polyline-points ent) (setq bbox (AS4:bbox-update p bbox)))
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (list found bbox)
)

;; finds every entity, of any type, on a layer matching pattern (the
;; same wildcard syntax as the Layer Panel's own "Search for Layer"
;; box: * matches any run of characters, ? matches one, etc. -
;; wcmatch's exact syntax) - via ssget's own (8 . pattern) layer
;; filter, which understands these wildcards natively at the C level,
;; the same mechanism the Layer Panel itself is built on. Unlike
;; AS4:find-by-criteria this is not restricted to INSERT/POLYLINE -
;; a layer can hold text labels, AS4NET grid crosses, or anything
;; else, and a layer-name search is about WHERE something is drawn,
;; not WHAT kind of AS4CAD data it carries. Returns a selection set,
;; or nil if nothing matched.
(defun AS4:find-by-layer-pattern (pattern)
  (ssget "X" (list (cons 8 pattern)))
)

;; zooms the view to every entity, of any type, in a selection set -
;; used for the layer-pattern search since a selection can span types
;; this file has no manual bounding-box logic for (TEXT, CIRCLE, ...);
;; ZOOM Object computes the extents itself instead.
(defun AS4:zoom-to-selection (ss)
  (command "_.ZOOM" "_Object" ss "")
)
;; escapes wcmatch's special characters in an exact layer name so it
;; matches literally inside an (8 . pattern) filter - needed when the
;; layer comes from a picked object rather than from a typed pattern.
(defun AS4:wc-escape (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (member ch '("`" "*" "?" "#" "@" "." "~" "[" "]" "," "'" "\""))
      (setq out (strcat out "`" ch))
      (setq out (strcat out ch))
    )
    (setq i (1+ i))
  )
  out
)

;; one prompt that accepts EITHER a click on an object OR typed text.
;; entsel cannot do this - initget bit 128 (arbitrary input) does not
;; apply to entsel, so typed text was rejected. getpoint does support
;; it: a click returns a point (the object under it is then looked up
;; with ssget), typed text comes back as a string - the same
;; type-at-the-cursor prompt as getstring. Returns an entity name
;; (clicked), a string (typed; "" for a plain Enter), or nil (Esc /
;; nothing under the click).
;; Caveat: typed text that is itself a valid point, e.g. "4,12" (two
;; IDs), reaches getpoint as the point 4,12 - when no object lies there
;; the typed text is recovered from LASTPROMPT. A space ends typed
;; input, so use ? instead of a space inside a layer pattern.
(defun AS4:pick-or-text (prompt / r ss res lp pos nxt tail dyn)
  (setq res nil)
  ;; Dynamic Input's pointer-input fields (X / Y / Z boxes at the
  ;; cursor) turn a getpoint prompt into several text boxes where
  ;; Tab/comma/* jump to the next field. Switch pointer input off for
  ;; this one prompt (DYNMODE 1/3 -> 2: dimension input only) so typed
  ;; text lands in the single command-prompt box instead; the user's
  ;; setting is restored right after, also on Esc.
  (setq dyn (vl-catch-all-apply 'getvar (list "DYNMODE")))
  (if (and (not (vl-catch-all-error-p dyn)) (member dyn '(1 3)))
    (vl-catch-all-apply 'setvar (list "DYNMODE" 2))
    (setq dyn nil)
  )
  (initget 128)
  (setq r (vl-catch-all-apply 'getpoint (list prompt)))
  (if dyn (vl-catch-all-apply 'setvar (list "DYNMODE" dyn)))
  (if (vl-catch-all-error-p r) (setq r 'ESC))
  (cond
    ((= r 'ESC) (setq res nil))
    ;; plain Enter: empty string = "current layer" for the callers
    ((null r) (setq res ""))
    ((= (type r) 'STR) (setq res (AS4:trim r)))
    ((and r (listp r))
      (setq ss (ssget r))
      (if ss
        (setq res (ssname ss 0))
        (progn
          (setq lp (getvar "LASTPROMPT") pos nil nxt (vl-string-search ": " lp))
          (while nxt (setq pos nxt nxt (vl-string-search ": " lp (1+ nxt))))
          (if pos
            (progn
              (setq tail (AS4:trim (substr lp (+ pos 3))))
              (if (and (> (strlen tail) 0) (not (wcmatch tail "*<*")))
                (setq res tail)
                (princ "\nNo object at that point.")))
            (princ "\nNo object at that point.")))))
  )
  res
)

;; selects + zooms to everything on layers matching pattern, reports
;; with label describing where the pattern came from
(defun AS4:select-layer-pattern (pattern label / ss)
  (setq ss (AS4:find-by-layer-pattern pattern))
  (if (not ss)
    (princ (strcat "\nNo objects found on " label "."))
    (progn
      (AS4:zoom-to-selection ss)
      (sssetfirst nil ss)
      (princ (strcat "\nZoomed to and selected " (itoa (sslength ss)) " object(s) on " label "."))
    )
  )
)

;; zooms the view to a (minx miny maxx maxy) bbox, with a margin so
;; objects aren't flush against the screen edge
(defun AS4:zoom-to-bbox (bbox / margin)
  (setq margin (* 0.1 (max (- (nth 2 bbox) (nth 0 bbox)) (- (nth 3 bbox) (nth 1 bbox)) 1.0)))
  (command "_.ZOOM" "_W"
    (list (- (nth 0 bbox) margin) (- (nth 1 bbox) margin))
    (list (+ (nth 2 bbox) margin) (+ (nth 3 bbox) margin)))
)

;; parses a comma-separated list of mixed IDs and codes, e.g.
;; "4,12,VF,FUND" -> ((4 12) ("VF" "FUND")) - each token is an ID if it
;; is a plain integer, a code (uppercased, case-insensitive) otherwise
(defun AS4:parse-criteria (s / parts p idlist codelist)
  (setq parts (AS4:split s ","))
  (setq idlist '() codelist '())
  (foreach p parts
    (setq p (AS4:trim p))
    (if (> (strlen p) 0)
      (if (AS4:is-integer-str p)
        (setq idlist (cons (atoi p) idlist))
        (setq codelist (cons (strcase p) codelist))
      )
    )
  )
  (list (reverse idlist) (reverse codelist))
)

;; counts how many of the found entities are point symbols (INSERT) vs
;; lines/polygons (POLYLINE) - diagnostic breakdown for AS4ZOOM/AS4SELECTXDATA
(defun AS4:count-by-type (found / npoints nlines e)
  (setq npoints 0 nlines 0)
  (foreach e found
    (cond
      ((= (cdr (assoc 0 (entget e))) "INSERT") (setq npoints (1+ npoints)))
      ((= (cdr (assoc 0 (entget e))) "POLYLINE") (setq nlines (1+ nlines)))
    )
  )
  (strcat (itoa npoints) " point symbol(s), " (itoa nlines) " line/polygon(s)")
)

;; zoom-only helpers shared by the AS4ZOOM branches
(defun AS4:zoom-layer (pattern label / ss)
  (setq ss (AS4:find-by-layer-pattern pattern))
  (if (not ss)
    (princ (strcat "\nNo objects found on " label "."))
    (progn
      (AS4:zoom-to-selection ss)
      (princ (strcat "\nZoomed to " (itoa (sslength ss)) " object(s) on " label "."))
    )
  )
)
(defun AS4:zoom-criteria (idlist codelist label / result bbox)
  (setq result (AS4:find-by-criteria idlist codelist))
  (setq bbox (cadr result))
  (if (not bbox)
    (princ (strcat "\nNo objects found for " label "."))
    (progn
      (AS4:zoom-to-bbox bbox)
      (princ (strcat "\nZoomed to " (itoa (length (car result))) " object(s) for " label
                     " (" (AS4:count-by-type (car result)) ")."))
    )
  )
)

;; AS4ZOOM: same input as AS4SELECTXDATA/AS4SELECTLAYER - click an
;; object, c, or typed text. A click zooms to everything sharing the
;; object's ID (or code; for an object with neither, its layer), c to
;; the current layer. Typed text containing "*" or "?" is a layer-name
;; pattern, anything else an ID/code list (IDs and codes never contain
;; those characters in practice, so this is unambiguous).
(defun c:AS4ZOOM ( / inp ic id code crit lay)
  (setq inp (AS4:pick-or-text "\nClick an object (its ID/code), Enter = current layer, or ID(s)/code(s) (e.g. 40 or 4,12,VF), or layer name(s) with * or ? (e.g. *193*,AS4_*): "))
  (cond
    ((not inp) (princ "\nCancelled."))
    ((= (type inp) 'ENAME)
      (setq ic (AS4:entity-id-code inp) id (car ic) code (cadr ic))
      (cond
        (id (AS4:zoom-criteria (list id) nil (strcat "ID " (itoa id))))
        (code (AS4:zoom-criteria nil (list (strcase code)) (strcat "code " code)))
        (T (setq lay (cdr (assoc 8 (entget inp))))
           (AS4:zoom-layer (AS4:wc-escape lay) (strcat "layer \"" lay "\"")))
      )
    )
    ((= inp "")
      (setq lay (getvar "CLAYER"))
      (AS4:zoom-layer (AS4:wc-escape lay) (strcat "the current layer \"" lay "\"")))
    ((or (vl-string-search "*" inp) (vl-string-search "?" inp))
      (AS4:zoom-layer inp (strcat "a layer matching \"" inp "\"")))
    (T
      (setq crit (AS4:parse-criteria inp))
      (if (and (null (car crit)) (null (cadr crit)))
        (princ "\nNo valid IDs or codes entered.")
        (AS4:zoom-criteria (car crit) (cadr crit) (strcat "\"" inp "\""))))
  )
  (princ)
)

;; internal name/code/Xdata search - was the standalone command
;; AS4SELECT, renamed alongside the new AS4SELECTLAYER so the two
;; search kinds (by ID/code vs. by layer name) are named distinctly
;; rather than one plain AS4SELECT meaning only one of them
(defun c:AS4SELECTXDATA ( / inp ic id code crit idlist codelist result found bbox ss ss2 e i n cur)
  (setq inp (AS4:pick-or-text "\nClick an object (its ID), Enter = current layer, or ID(s)/code(s), comma-separated (e.g. 40 or 4,12,VF,FUND): "))
  (cond
    ((not inp) (princ "\nCancelled."))
    ;; --- click: everything sharing the picked object's ID (or, if it
    ;; has none, its code)
    ((= (type inp) 'ENAME)
      (setq ic (AS4:entity-id-code inp) id (car ic) code (cadr ic))
      (cond
        (id (setq idlist (list id) codelist nil))
        (code (setq idlist nil codelist (list (strcase code))))
      )
      (if (not (or idlist codelist))
        (princ "\nThe picked object carries no AS4 ID or code.")
        (progn
          (setq result (AS4:find-by-criteria idlist codelist))
          (setq found (car result) bbox (cadr result))
          (if (not bbox)
            (princ "\nNo objects found.")
            (progn
              (AS4:zoom-to-bbox bbox)
              (setq ss2 (ssadd))
              (foreach e found (setq ss2 (ssadd e ss2)))
              (sssetfirst nil ss2)
              (princ (strcat "\nZoomed to and selected " (itoa (length found)) " object(s) with "
                             (if idlist (strcat "ID " (itoa id)) (strcat "code " code))
                             " (" (AS4:count-by-type found) ")."))
            )
          )
        )
      )
    )
    ;; --- "c": every AS4 point/line/polygon on the current layer
    ((= inp "")
      (setq cur (getvar "CLAYER"))
      (setq ss (ssget "X" (list (cons 0 "INSERT,POLYLINE") (cons 8 (AS4:wc-escape cur)))))
      (setq ss2 (ssadd) n 0)
      (if ss
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq e (ssname ss i))
            (setq ic (AS4:entity-id-code e))
            (if (or (car ic) (cadr ic)) (progn (setq ss2 (ssadd e ss2)) (setq n (1+ n))))
            (setq i (1+ i))
          )
        )
      )
      (if (= n 0)
        (princ (strcat "\nNo AS4 objects found on the current layer \"" cur "\"."))
        (progn
          (AS4:zoom-to-selection ss2)
          (sssetfirst nil ss2)
          (princ (strcat "\nZoomed to and selected " (itoa n) " AS4 object(s) on the current layer \"" cur "\"."))
        )
      )
    )
    ;; --- typed IDs/codes (unchanged behaviour)
    (T
      (setq crit (AS4:parse-criteria inp))
      (setq idlist (car crit) codelist (cadr crit))
      (if (and (= (length idlist) 0) (= (length codelist) 0))
        (princ "\nNo valid IDs or codes entered.")
        (progn
          (setq result (AS4:find-by-criteria idlist codelist))
          (setq found (car result) bbox (cadr result))
          (if (not bbox)
            (princ "\nNo objects found for the given ID(s)/code(s).")
            (progn
              (AS4:zoom-to-bbox bbox)
              (setq ss2 (ssadd))
              (foreach e found (setq ss2 (ssadd e ss2)))
              (sssetfirst nil ss2)
              (princ (strcat "\nZoomed to and selected " (itoa (length found)) " object(s) for "
                             (itoa (+ (length idlist) (length codelist)))
                             " criterion/criteria (" (AS4:count-by-type found) ")."))
            )
          )
        )
      )
    )
  )
  (princ)
)

;; layer-name search, wildcard-based - the same "Search for Layer"
;; style matching as the Layer Panel's own filter box: * matches any
;; run of characters, ? matches exactly one (full wcmatch syntax).
;; Typing a plain name with no wildcard matches only that exact layer
;; name - wrap it in *asterisks* for a "contains" search, the way the
;; Layer Panel's own box is usually used. Note: unlike the Layer
;; Panel's own search field, this prompt cannot start pre-filled with
;; "**" and the cursor placed between them - AutoLISP's getstring is a
;; plain text prompt with no support for pre-filled/positioned text,
;; that specific convenience is a GUI-dialog-only capability.
(defun c:AS4SELECTLAYER ( / inp lay)
  (setq inp (AS4:pick-or-text "\nClick an object (its layer), Enter = current layer, or layer name(s): * = any characters, ? = one character, comma = several (e.g. *193*,AS4_*): "))
  (cond
    ((not inp) (princ "\nCancelled."))
    ;; click: the picked object's layer, matched literally
    ((= (type inp) 'ENAME)
      (setq lay (cdr (assoc 8 (entget inp))))
      (AS4:select-layer-pattern (AS4:wc-escape lay) (strcat "layer \"" lay "\"")))
    ;; c: current layer, matched literally
    ((= inp "")
      (setq lay (getvar "CLAYER"))
      (AS4:select-layer-pattern (AS4:wc-escape lay) (strcat "the current layer \"" lay "\"")))
    ;; typed wildcard pattern (unchanged behaviour)
    (T (AS4:select-layer-pattern inp (strcat "a layer matching \"" inp "\"")))
  )
  (princ)
)

;; =========================================================================
;; AS4NET / AS4NETTXT: a reference survey grid (crosses at round
;; coordinates, e.g. every 10 m) over a picked window, and a label
;; command to write X/Y text next to any selected points.
;; =========================================================================

;; true mathematical floor of a real number, as an integer
(defun AS4:floor-int (v / f)
  (setq f (fix v))
  (if (and (< v 0.0) (/= v f)) (1- f) f)
)
(defun AS4:grid-floor (v step) (* step (AS4:floor-int (/ v step))))
(defun AS4:grid-ceil (v step) (- (AS4:grid-floor (- v) step)))

;; small cross symbol, unit-sized, scaled at insertion time
(defun AS4:def-gridcross ()
  (AS4:ensure-block "AS4_GridCross"
    (list
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 7) (cons 10 (list -1.0 0.0 0.0)) (cons 11 (list 1.0 0.0 0.0)))
      (list (cons 0 "LINE") (cons 8 "0") (cons 62 7) (cons 10 (list 0.0 -1.0 0.0)) (cons 11 (list 0.0 1.0 0.0)))
    )
  )
)
(defun AS4:insert-gridcross (pt layer scale)
  (entmakex (list
    (cons 0 "INSERT") (cons 8 layer) (cons 2 "AS4_GridCross") (cons 10 pt)
    (cons 41 scale) (cons 42 scale) (cons 43 scale) (cons 50 0.0)
  ))
)

;; AS4NET: the only entry point for AS4CAD's reference survey grid -
;; drawing the grid crosses and labeling picked points with their
;; coordinates are internal functions, not separate commands, reached
;; only through this menu.
(defun c:AS4NET ( / kw done)
  (setq done nil)
  (while (not done)
    (initget "Grid Label eXit G L X")
    (setq kw (getkword "\nAS4CAD survey grid [Grid/Label/eXit] <eXit>: "))
    (if (not kw) (setq kw "eXit"))
    (cond
      ((member kw (list "Grid" "G")) (AS4:net-grid))
      ((member kw (list "Label" "L")) (AS4:net-label))
      ((member kw (list "eXit" "X")) (setq done T))
    )
  )
  (princ)
)

;; internal - the AS4NET umbrella's "Grid" step
(defun AS4:net-grid ( / pt1 pt2 minx maxx miny maxy spacing gminx gmaxx gminy gmaxy
                    x y z0 layer scale cnt)
  (setq pt1 (getpoint "\nFirst corner of area to cover: "))
  (if (not pt1)
    (princ "\nCancelled.")
    (progn
      (setq pt2 (getcorner pt1 "\nOpposite corner: "))
      (if (not pt2)
        (princ "\nCancelled.")
        (progn
          (setq spacing (getreal "\nGrid spacing in metres <10>: "))
          (if (or (not spacing) (<= spacing 0.0)) (setq spacing 10.0))
          (setq z0 (getreal "\nZ elevation for the grid <0.0>: "))
          (if (not z0) (setq z0 0.0))
          (setq minx (min (car pt1) (car pt2)) maxx (max (car pt1) (car pt2)))
          (setq miny (min (cadr pt1) (cadr pt2)) maxy (max (cadr pt1) (cadr pt2)))
          (setq layer (AS4:ensure-layer "as4_survey-grid"))
          (AS4:def-gridcross)
          (setq scale (* spacing 0.05 (/ 2.0 3.0))) ;; one third smaller than the original 0.05 factor
          (setq gminx (AS4:grid-floor minx spacing))
          (setq gmaxx (AS4:grid-ceil maxx spacing))
          (setq gminy (AS4:grid-floor miny spacing))
          (setq gmaxy (AS4:grid-ceil maxy spacing))
          (setq cnt 0)
          (setq x gminx)
          (while (<= x gmaxx)
            (if (and (>= x minx) (<= x maxx))
              (progn
                (setq y gminy)
                (while (<= y gmaxy)
                  (if (and (>= y miny) (<= y maxy))
                    (progn
                      (AS4:insert-gridcross (list x y z0) layer scale)
                      (setq cnt (1+ cnt))
                    )
                  )
                  (setq y (+ y spacing))
                )
              )
            )
            (setq x (+ x spacing))
          )
          (princ (strcat "\nPlaced " (itoa cnt) " grid point(s) at " (rtos spacing 2 2)
                         "m spacing, Z=" (rtos z0 2 2) ", on layer as4_survey-grid."))
        )
      )
    )
  )
  (princ)
)

;; the representative coordinate of a generic entity (for AS4NETTXT)
(defun AS4:entity-point (ent / etype edata)
  (setq edata (entget ent))
  (setq etype (cdr (assoc 0 edata)))
  (cond
    ((= etype "INSERT") (cdr (assoc 10 edata)))
    ((= etype "POINT") (cdr (assoc 10 edata)))
    ((= etype "CIRCLE") (cdr (assoc 10 edata)))
    ((= etype "LINE") (cdr (assoc 10 edata)))
    (t nil)
  )
)

;; internal - the AS4NET umbrella's "Label" step
(defun AS4:net-label ( / ss i ent pt txtlayer cnt th xpt ypt offs)
  (princ "\nSelect points to label with X/Y coordinates: ")
  (setq ss (ssget))
  (if (not ss)
    (princ "\nNothing selected.")
    (progn
      (setq txtlayer (AS4:ensure-layer "as4_txt_survey-grid"))
      (setq th (* *AS4:TEXTHEIGHT* 1.5)) ;; 50% larger than the base label text height
      (setq offs (* 1.5 *AS4:VERTEXRADIUS*))
      (setq cnt 0)
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq pt (AS4:entity-point ent))
        (if pt
          (progn
            ;; X label: normal horizontal text, offset to the right
            (setq xpt (list (+ (car pt) offs) (cadr pt) (caddr pt)))
            (AS4:add-text-rot (strcat "X=" (rtos (car pt) 2 3)) xpt txtlayer th 0.0)
            ;; Y label: rotated 90 degrees (reads bottom-to-top), offset upward
            (setq ypt (list (car pt) (+ (cadr pt) offs) (caddr pt)))
            (AS4:add-text-rot (strcat "Y=" (rtos (cadr pt) 2 3)) ypt txtlayer th (/ pi 2.0))
            (setq cnt (1+ cnt))
          )
        )
        (setq i (1+ i))
      )
      (princ (strcat "\nLabeled " (itoa cnt) " point(s) on layer as4_txt_survey-grid."))
    )
  )
  (princ)
)

;; =========================================================================
;; AS4XPORTGISGEOJSON: writes a combined GeoJSON FeatureCollection - point
;; symbols AS Point features, lines/polygons/postholes as LineString/
;; Polygon features - in one file, geometry and attributes together, so
;; it can be opened directly in QGIS with no DXF export and no manual
;; attribute join required.
;;
;; Reuses the same robustness patterns as AS4XPORTPOINTDATACSV: entities are
;; found by scanning the selection/drawing and checking for their own
;; POINT_ID attribute or being a POLYLINE (not via an Xdata ssget filter,
;; which is not reliable on every AutoCAD build - see AS4XPORTPOINTDATACSV);
;; AS4_Vertex and AS4_GridCross block references are excluded, since they
;; are markers, not point-data symbols.
;; =========================================================================

(defun AS4:json-escape (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (cond
      ((= ch "\"") (setq out (strcat out "\\\"")))
      ((= ch "\\") (setq out (strcat out "\\\\")))
      (t (setq out (strcat out ch)))
    )
    (setq i (1+ i))
  )
  out
)
(defun AS4:json-str (v)
  (if (or (null v) (= v "")) "null" (strcat "\"" (AS4:json-escape v) "\""))
)
;; v is already a plain numeric-looking string (or "" / nil) - GeoJSON
;; numbers are unquoted, and our stored numeric attributes are already
;; valid numeric text, so no reformatting is needed, only a null check
(defun AS4:json-rawnum (v)
  (if (or (null v) (= v "")) "null" v)
)
(defun AS4:json-coord (pt)
  (strcat "[" (rtos (car pt) 2 3) "," (rtos (cadr pt) 2 3) "," (rtos (caddr pt) 2 3) "]")
)
(defun AS4:json-coord-list (pts / s first p)
  (setq s "[" first T)
  (foreach p pts
    (if (not first) (setq s (strcat s ",")))
    (setq s (strcat s (AS4:json-coord p)))
    (setq first nil)
  )
  (strcat s "]")
)
;; pairs: list of (key . already-formatted-json-value-string)
(defun AS4:json-props (pairs / s first p)
  (setq s "{" first T)
  (foreach p pairs
    (if (not first) (setq s (strcat s ",")))
    (setq s (strcat s "\"" (car p) "\":" (cdr p)))
    (setq first nil)
  )
  (strcat s "}")
)
(defun AS4:is-polygon-shptype (shptype)
  (if (member shptype '("03" "53" "61" "06" "73" "93")) T nil)
)
;; string -> real, or nil for an empty/missing string (atof alone would
;; silently return 0.0 for "", which is a real elevation value and would
;; be indistinguishable from an actual zero)
(defun AS4:atof-or-nil (s)
  (if (and s (> (strlen s) 0)) (AS4:safe-atof s) nil)
)
;; GeoJSON polygon rings must be closed (first coordinate repeated as the
;; last); AutoCAD's POLYLINE closed flag doesn't duplicate the vertex
(defun AS4:close-ring (pts)
  (if (and pts (not (equal (car pts) (last pts))))
    (append pts (list (car pts)))
    pts
  )
)

;; internal - AS4XPORT's "GeoJson" step
(defun AS4:xport-geojson ( / ss i ent etype attrs pid ox oy oz idstr base fout
                    rows rowdata kind mx mn shptype pts ring
                    geomjson props first cnt epsg mirror ispoly mirrorjson)
  (princ "\nSelect objects to export (press Enter with nothing selected to export the whole drawing instead): ")
  (setq ss (ssget))
  (if (not ss) (setq ss (ssget "X")))

  (if (or (not ss) (= (sslength ss) 0))
    (princ "\nNothing selected and the drawing appears to be empty.")
    (progn
      ;; auto-tag first: any line/polygon in the selection that has no
      ;; AS4CAD attributes yet, but whose layer name encodes an ID (e.g.
      ;; traced over a photogrammetry mesh and organized by layer), gets
      ;; tagged now - so the export below never has to fall back to
      ;; null-filled properties for something that could have been
      ;; resolved. Lines that still can't be parsed after this are
      ;; excluded from the export entirely (see the collection step)
      ;; rather than being included with nulls.
      (AS4:auto-tag-lines ss)

      (setq base (getfiled "AS4 QGIS export - enter a file name" "" "geojson" 1))
      (if (not base)
        (princ "\nCancelled.")
        (progn
          (setq *AS4:ELEV* '())
          (setq rows '())

          ;; step 1: collect raw per-entity data + the point elevation
          ;; table, in one pass
          (setq i 0)
          (while (< i (sslength ss))
            (setq ent (ssname ss i))
            (setq etype (cdr (assoc 0 (entget ent))))
            (cond
              ((and (= etype "INSERT")
                    (/= (cdr (assoc 2 (entget ent))) "AS4_Vertex")
                    (/= (cdr (assoc 2 (entget ent))) "AS4_GridCross"))
                (setq attrs (AS4:get-attributes ent))
                (setq pid (AS4:attr-get attrs "POINT_ID"))
                (if (> (strlen pid) 0)
                  (progn
                    (setq ox (car (cdr (assoc 10 (entget ent)))))
                    (setq oy (cadr (cdr (assoc 10 (entget ent)))))
                    (setq oz (caddr (cdr (assoc 10 (entget ent)))))
                    (setq idstr (AS4:attr-get attrs "ID"))
                    (if (> (strlen idstr) 0) (AS4:bump-elev (atoi idstr) oz))
                    (setq rows (cons (list "point" attrs (list ox oy oz)) rows))
                  )
                )
              )
              ;; only lines/polygons that actually carry AS4CAD Xdata (own
              ;; import, manual AS4TAGFROMLAYER earlier, or the auto-tag
              ;; step just above) are exported - anything still untagged
              ;; at this point has no ID to attach meaningful attributes
              ;; to and would only produce a null-filled feature
              ((and (= etype "POLYLINE") (AS4:xdata-get ent "ID"))
                (setq rows (cons (list "line" ent nil) rows))
              )
            )
            (setq i (1+ i))
          )
          (setq rows (reverse rows))

          (if (= (length rows) 0)
            (princ "\nNo AS4CAD point symbols or lines/polygons found in the selection/drawing - nothing to export.")
            (progn
              ;; mirror polygons to an additional polyline feature -
              ;; matches AS4QGIS's own "mirror polygons to polylines"
              ;; option. Applies to shptypes 03/53/61(06)/73/93 - the
              ;; ones this export actually writes as Polygon geometry
              ;; (AS4:is-polygon-shptype). Shptype 33 is NOT included:
              ;; in this system it is already exported as a LineString,
              ;; not a Polygon (see the "line" branch below), so
              ;; mirroring it would just duplicate what it already is.
              (initget "Yes No Y N")
              (setq mirror (AS4:norm-yn (getkword "\nAlso export polygons (03/53/61/06/73/93) as an additional mirrored polyline feature? [Yes/No] <No>: ")))
              (if (not mirror) (setq mirror "No"))

              ;; GeoJSON (RFC 7946) has no CRS concept at all beyond WGS84 -
              ;; QGIS therefore assumes WGS84 for a plain GeoJSON and never
              ;; even offers to set one, which places these local/projected
              ;; survey coordinates completely wrong. The legacy (pre-2016)
              ;; "crs" member is still read by GDAL/OGR (and so by QGIS) as
              ;; a fallback, so it is embedded here when an EPSG code is
              ;; given.
              (setq epsg (getstring (strcat "\nEPSG code for these coordinates, or Enter to skip (QGIS will then assume WGS84) <"
                (if (> (strlen *AS4:XPORT-EPSG*) 0) *AS4:XPORT-EPSG* "none") ">: ")))
              (if (or (not epsg) (= (strlen epsg) 0)) (setq epsg *AS4:XPORT-EPSG*))
              (if (and epsg (> (strlen epsg) 0))
                (progn
                  (if (and (>= (strlen epsg) 5) (= (strcase (substr epsg 1 5)) "EPSG:"))
                    (setq epsg (substr epsg 6)) ;; tolerate a typed "EPSG:" prefix
                  )
                  (if (not (AS4:all-digits epsg))
                    (progn (princ "\nNot a valid EPSG code (digits only) - continuing without a CRS.") (setq epsg ""))
                  )
                )
                (setq epsg "")
              )

              ;; step 2: write the GeoJSON - a plain foreach over the list
              ;; built above, not a second indexed loop
              (setq fout (open base "w"))
              (if (> (strlen epsg) 0)
                (write-line (strcat "{\"type\":\"FeatureCollection\",\"crs\":{\"type\":\"name\",\"properties\":{\"name\":\"urn:ogc:def:crs:EPSG::" epsg "\"}},\"features\":[") fout)
                (write-line "{\"type\":\"FeatureCollection\",\"features\":[" fout)
              )
              (setq first T cnt 0)

              (foreach rowdata rows
                (setq kind (nth 0 rowdata))
                (setq mirrorjson nil)
                (cond
                  ;; ---------------- point features ----------------
                  ((= kind "point")
                    (setq attrs (nth 1 rowdata))
                    (setq idstr (AS4:attr-get attrs "ID"))
                    (setq shptype (AS4:attr-get attrs "SHPTYPE"))
                    (setq mx (if (> (strlen idstr) 0) (car (AS4:get-elev (atoi idstr))) nil))
                    (setq mn (if (> (strlen idstr) 0) (cadr (AS4:get-elev (atoi idstr))) nil))
                    (setq geomjson (strcat "{\"type\":\"Point\",\"coordinates\":" (AS4:json-coord (nth 2 rowdata)) "}"))
                    (setq props (AS4:json-props (list
                      (cons "ID" (AS4:json-rawnum idstr))
                      (cons "code" (AS4:json-str (AS4:attr-get attrs "CODE")))
                      (cons "shptype_n" (AS4:json-str (AS4:attr-get attrs "SHPTYPE_N")))
                      (cons "shptype" (AS4:json-str shptype))
                      (cons "point_prop" (AS4:json-str (AS4:attr-get attrs "POINT_PROP")))
                      (cons "find_nr" (AS4:json-str (if (= shptype "71") (AS4:attr-get attrs "CONTIN_NR") "")))
                      (cons "sample_nr" (AS4:json-str (if (= shptype "51") (AS4:attr-get attrs "CONTIN_NR") "")))
                      (cons "f_ma_s_me" (AS4:json-str (AS4:attr-get attrs "F_MA_S_ME")))
                      (cons "contin_nr" (AS4:json-str (AS4:attr-get attrs "CONTIN_NR")))
                      (cons "point_ID" (AS4:json-str (AS4:attr-get attrs "POINT_ID")))
                      (cons "maxH" (if mx (rtos mx 2 3) "null"))
                      (cons "minH" (if mn (rtos mn 2 3) "null"))
                      (cons "maxHtemp" (AS4:json-str (AS4:pseudo-date mx)))
                      (cons "minHtemp" (AS4:json-str (AS4:pseudo-date mn)))
                      (cons "originfile" (AS4:json-str (AS4:attr-get attrs "ORIGINFILE")))
                      (cons "IDstring" (AS4:json-str (AS4:attr-get attrs "IDSTRING")))
                      (cons "ID_code" (AS4:json-str (AS4:attr-get attrs "ID_CODE")))
                      (cons "code_ID" (AS4:json-str (AS4:attr-get attrs "CODE_ID")))
                    )))
                  )
                  ;; ---------------- line/polygon features ----------------
                  ((= kind "line")
                    (setq ent (nth 1 rowdata))
                    (setq shptype (AS4:xdata-get ent "shptype"))
                    (setq pts (AS4:polyline-points ent))
                    (setq ispoly (AS4:is-polygon-shptype shptype))
                    (if ispoly
                      (progn
                        (setq ring (AS4:close-ring pts))
                        (setq geomjson (strcat "{\"type\":\"Polygon\",\"coordinates\":[" (AS4:json-coord-list ring) "]}"))
                      )
                      (setq geomjson (strcat "{\"type\":\"LineString\",\"coordinates\":" (AS4:json-coord-list pts) "}"))
                    )
                    (setq props (AS4:json-props (list
                      (cons "ID" (AS4:json-rawnum (AS4:xdata-get ent "ID")))
                      (cons "code" (AS4:json-str (AS4:xdata-get ent "code")))
                      (cons "shptype" (AS4:json-str shptype))
                      (cons "maxH" (AS4:json-rawnum (AS4:xdata-get ent "maxH")))
                      (cons "minH" (AS4:json-rawnum (AS4:xdata-get ent "minH")))
                      (cons "maxHtemp" (AS4:json-str (AS4:pseudo-date (AS4:atof-or-nil (AS4:xdata-get ent "maxH")))))
                      (cons "minHtemp" (AS4:json-str (AS4:pseudo-date (AS4:atof-or-nil (AS4:xdata-get ent "minH")))))
                      (cons "originfile" (AS4:json-str (AS4:xdata-get ent "originfile")))
                      (cons "IDstring" (AS4:json-str (AS4:xdata-get ent "IDstring")))
                      (cons "ID_code" (AS4:json-str (AS4:xdata-get ent "ID_code")))
                      (cons "code_ID" (AS4:json-str (AS4:xdata-get ent "code_ID")))
                    )))
                    ;; the mirrored polyline copy, same properties - a
                    ;; CLOSED LineString using the same ring the Polygon
                    ;; geometry itself used (end point = start point),
                    ;; not the raw open vertex list. A mirrored boundary
                    ;; is supposed to still be a closed outline of the
                    ;; polygon it mirrors; using the open point list
                    ;; here was a bug (this comment used to defend it,
                    ;; incorrectly - the fix is: use "ring", not "pts")
                    (if (and ispoly (= mirror "Yes"))
                      (setq mirrorjson (strcat "{\"type\":\"LineString\",\"coordinates\":" (AS4:json-coord-list ring) "}"))
                      (setq mirrorjson nil)
                    )
                  )
                )
                (write-line (strcat (if first "  " ", ") "{\"type\":\"Feature\",\"geometry\":" geomjson ",\"properties\":" props "}") fout)
                (setq first nil cnt (1+ cnt))
                (if mirrorjson
                  (progn
                    (write-line (strcat ", {\"type\":\"Feature\",\"geometry\":" mirrorjson ",\"properties\":" props "}") fout)
                    (setq cnt (1+ cnt))
                    (setq mirrorjson nil)
                  )
                )
              )

              (write-line "]}" fout)
              (close fout)
              (princ (strcat "\nExported " (itoa cnt) " feature(s) to: " base))
            )
          )
        )
      )
    )
  )
  (princ)
)

(defun AS4:pad4 (n / s)
  (setq s (itoa n))
  (while (< (strlen s) 4) (setq s (strcat "0" s)))
  s
)

;; =========================================================================
;; AS4TAGFROMLAYER: bulk-scans lines/polygons that have no AS4CAD Xdata
;; (e.g. hundreds of lines traced over a photogrammetry mesh in Metashape/
;; 3DF Zephyr, exported as DXF, then copy-pasted into the master plan) and
;; derives ID/code straight from each object's own LAYER NAME - no manual
;; per-line input. Shape type (polyline vs. polygon) is derived from the
;; entity's own closed/open state, matching the same convention AS4QGIS
;; itself recommends (closed = largest extent = polygon, open = polyline).
;; A dry-run summary is shown before anything is changed, since this can
;; touch hundreds of objects in one call.
;; =========================================================================

;; true if every character in s is a digit
(defun AS4:all-digits (s / i ch ok)
  (setq ok (> (strlen s) 0))
  (setq i 1)
  (while (and ok (<= i (strlen s)))
    (setq ch (substr s i 1))
    (if (not (and (>= (ascii ch) 48) (<= (ascii ch) 57))) (setq ok nil))
    (setq i (1+ i))
  )
  ok
)

;; parses a layer name into (idnum . code), or nil if it can't be parsed.
;; Accepts a plain number ("193"), or two parts split by a single "_"
;; where exactly one part is a plain number and the other is the code -
;; in either order ("193_VF" or "VF_193") - matching any of AS4SETLAYER's
;; IDnum/IDstr/IDnumCode/IDstrCode/CodeIDnum/CodeIDstr field conventions,
;; without needing to know which one was used.
(defun AS4:parse-layer-id (lname / parts p1 p2)
  (cond
    ((AS4:all-digits lname) (cons (atoi lname) ""))
    (t
      (setq parts (AS4:split lname "_"))
      (if (= (length parts) 2)
        (progn
          (setq p1 (nth 0 parts) p2 (nth 1 parts))
          (cond
            ((and (AS4:all-digits p1) (not (AS4:all-digits p2))) (cons (atoi p1) p2))
            ((and (AS4:all-digits p2) (not (AS4:all-digits p1))) (cons (atoi p2) p1))
            (t nil)
          )
        )
        nil
      )
    )
  )
)

(defun AS4:join-strings (lst sep / s first x)
  (setq s "" first T)
  (foreach x lst
    (if (not first) (setq s (strcat s sep)))
    (setq s (strcat s x))
    (setq first nil)
  )
  s
)

;; core auto-tagging routine, shared between AS4TAGFROMLAYER and
;; AS4XPORTGISGEOJSON (called there as a preliminary step so lines that CAN be
;; tagged are complete before export, instead of exported with nulls).
;; Scans ss for untagged POLYLINE entities, derives ID/code from each
;; one's layer name, shows a dry-run summary, and - after confirmation -
;; tags whatever could be parsed. Entities that cannot be parsed are left
;; alone (still untagged) so the caller can decide how to handle them.
(defun AS4:auto-tag-lines (ss / i ent edata lname parsed pts todo skiplayers
                    alreadycount nogeocount unparsecount gkw cnt item
                    idnum code idstring countassoc pair letters container
                    zvals maxh minh flagpair closed shptype idcode codeid geomid)
  (setq todo '() skiplayers '() alreadycount 0 nogeocount 0 unparsecount 0 countassoc '())

  ;; pass 1: classify every POLYLINE in the selection - nothing is
  ;; written to the drawing yet
  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq edata (entget ent))
    (if (= (cdr (assoc 0 edata)) "POLYLINE")
      (if (AS4:xdata-get ent "ID")
        (setq alreadycount (1+ alreadycount))
        (progn
          (setq lname (cdr (assoc 8 edata)))
          (if (and lname (>= (strlen lname) 4) (= (strcase (substr lname 1 4)) "AS4_"))
            (setq lname nil) ;; an as4_-prefixed layer is AS4CAD's own system layer, not a candidate
          )
          (setq parsed (if lname (AS4:parse-layer-id lname) nil))
          (if (not parsed)
            (progn
              (setq unparsecount (1+ unparsecount))
              (if (and lname (not (member lname skiplayers))) (setq skiplayers (cons lname skiplayers)))
            )
            (progn
              (setq pts (AS4:polyline-points ent))
              (if (= (length pts) 0)
                (setq nogeocount (1+ nogeocount))
                (setq todo (cons (list ent parsed pts edata) todo))
              )
            )
          )
        )
      )
    )
    (setq i (1+ i))
  )
  (setq todo (reverse todo))
  (setq skiplayers (reverse skiplayers))

  ;; dry-run summary
  (princ (strcat "\n" (itoa (length todo)) " line(s)/polygon(s) can be tagged from their layer name."))
  (if (> alreadycount 0) (princ (strcat "\n" (itoa alreadycount) " already had AS4CAD attributes.")))
  (if (> unparsecount 0)
    (progn
      (princ (strcat "\n" (itoa unparsecount) " could not be parsed (layer name has no clear ID). Affected layer(s): "))
      (princ (AS4:join-strings skiplayers ", "))
    )
  )
  (if (> nogeocount 0) (princ (strcat "\n" (itoa nogeocount) " had no readable vertices.")))

  (if (> (length todo) 0)
    (progn
      (initget "Yes No Y N")
      (setq gkw (AS4:norm-yn (getkword (strcat "\nTag these " (itoa (length todo))
        " line(s)/polygon(s) now? Closed ones become shptype 03 (polygon), open ones become 02 (polyline). [Yes/No] <Yes>: "))))
      (if (= gkw "No")
        (princ "\nSkipped tagging - nothing was changed.")
        (progn
          (setq cnt 0)
          (foreach item todo
            (setq ent (nth 0 item) parsed (nth 1 item) pts (nth 2 item) edata (nth 3 item))
            (setq idnum (car parsed) code (cdr parsed))
            (setq idstring (AS4:pad4 idnum))

            ;; container letter auto-increments per ID within this
            ;; batch, so multiple lines for the same feature get
            ;; distinct geom_ID values instead of colliding
            (setq pair (assoc idnum countassoc))
            (setq letters (if pair (1+ (cdr pair)) 0))
            (setq countassoc (if pair (subst (cons idnum letters) pair countassoc) (cons (cons idnum letters) countassoc)))
            (setq container (if (< letters 26) (chr (+ 65 letters)) "Z"))

            (setq zvals (mapcar '(lambda (p) (caddr p)) pts))
            (setq maxh (apply 'max zvals))
            (setq minh (apply 'min zvals))

            (setq flagpair (assoc 70 edata))
            (setq closed (and flagpair (= 1 (logand (cdr flagpair) 1))))
            (setq shptype (if closed "03" "02"))

            (setq idcode (strcat idstring "_" code))
            (setq codeid (strcat code "_" idstring))
            (setq geomid (strcat idstring container shptype))

            (AS4:add-xdata ent (list
              (cons "ID" idnum) (cons "IDstring" idstring)
              (cons "code" code) (cons "shptype" shptype) (cons "shptype_n" (AS4:shptype-name shptype))
              (cons "geom_ID" geomid)
              (cons "ID_code" idcode) (cons "code_ID" codeid)
              (cons "maxH" maxh) (cons "minH" minh)
              (cons "originfile" "manual")
            ))
            (setq cnt (1+ cnt))
          )
          (princ (strcat "\nTagged " (itoa cnt) " line(s)/polygon(s)."))
        )
      )
    )
  )
)

(defun c:AS4TAGFROMLAYER ( / ss)
  (princ "\nSelect lines/polygons to scan (press Enter with nothing selected to scan the whole drawing instead): ")
  (setq ss (ssget))
  (if (not ss) (setq ss (ssget "X")))

  (if (or (not ss) (= (sslength ss) 0))
    (princ "\nNothing selected and the drawing appears to be empty.")
    (AS4:auto-tag-lines ss)
  )
  (princ)
)

;; =========================================================================
;; AS4TABLE: links an external table (CSV exported from an excavation
;; database) to the drawing's layers, by an ID that is read out of the
;; LAYER NAMES. Layer names are only a snapshot (e.g. the dating part of
;; 202616_1_Vf_RZ may be outdated), the table is the maintained source -
;; so the link uses only the ID part of the name, and the table file
;; itself is never copied into the drawing: it is re-read on every use,
;; so overwriting the CSV is reflected immediately, and the link (file,
;; key column, templates) survives because it refers to keys, not rows.
;;
;; Template syntax (same for layer names and for key column values):
;; tokens separated by one separator character (_ - . / space | : ;),
;; ID = a token that is part of the key (several ID are joined into a
;; composite key, e.g. ID_ID_*_* = excavation number + unit number),
;; * = any token, anything else = literal token (wildcards allowed).
;; The layer must have exactly as many tokens as the template. Keys
;; compare case-insensitively and without leading zeros (04 = 4).
;; (Old templates written with braces, {ID}_{ID}_*_*, still work.)
;;
;; Nothing in the table layout is hard-coded: column names, count and
;; meaning come from the file's header; the key column is chosen by the
;; user. Links are stored next to the drawing in as4cad_tables.dat.
;; =========================================================================

;; ---- small helpers ------------------------------------------------------
(defun AS4:tbl-join (lst sep / out s)
  (setq out "")
  (foreach s lst (setq out (if (= out "") s (strcat out sep s))))
  out
)

(defun AS4:tbl-cell (row i / v)
  (setq v (nth i row))
  (if v v "")
)

(defun AS4:tbl-trim1 (v) (AS4:ltrim (AS4:rtrim v)))

(defun AS4:tbl-pad (s n)
  (while (< (strlen s) n) (setq s (strcat s " ")))
  (if (> (strlen s) n) (substr s 1 n) s)
)

;; one-line, length-limited version of a cell for display
(defun AS4:tbl-oneline (s n / out i ch)
  (setq out "" i 1)
  (while (and (<= i (strlen s)) (< (strlen out) n))
    (setq ch (substr s i 1))
    (setq out (strcat out (if (member ch (list "\n" (chr 13))) " " ch)))
    (setq i (1+ i))
  )
  (if (< (strlen out) (strlen s)) (strcat out "...") out)
)

(defun AS4:tbl-print-list (title items cap / i it)
  (princ (strcat "\n" title " (" (itoa (length items)) "):"))
  (setq i 0)
  (foreach it items
    (if (< i cap) (princ (strcat "\n  " it)))
    (setq i (1+ i))
  )
  (if (> i cap) (princ (strcat "\n  ... and " (itoa (- i cap)) " more")))
)

(defun AS4:tbl-numeric-p (s / i ch seps ok n)
  (setq ok (> (strlen s) 0) seps 0 i 1 n (strlen s))
  (while (and ok (<= i n))
    (setq ch (substr s i 1))
    (cond
      ((and (>= (ascii ch) 48) (<= (ascii ch) 57)))
      ((and (= i 1) (member ch '("-" "+")) (> n 1)))
      ((and (member ch '("." ",")) (= seps 0)) (setq seps 1))
      (T (setq ok nil))
    )
    (setq i (1+ i))
  )
  ok
)

;; "r,g,b" / "r;g;b" / "r g b" / "rgb(r,g,b)" (0-255), "#RRGGBB" or "0xRRGGBB"
;; -> true color integer, or nil
(defun AS4:tbl-hexval (str / v i d)
  (setq v 0 i 1)
  (while (and v (<= i (strlen str)))
    (setq d (vl-string-search (strcase (substr str i 1)) "0123456789ABCDEF"))
    (setq v (if d (+ (* v 16) d) nil) i (1+ i)))
  v
)

(defun AS4:tbl-parse-rgb (s / out i ch parts r g b prev)
  (setq s (AS4:trim s))
  (if (wcmatch (strcase s) "RGB(*)") (setq s (AS4:trim (substr s 5 (- (strlen s) 5)))))
  (cond
    ((= s "") nil)
    ((wcmatch (strcase s) "0X??????")
      (setq r (AS4:tbl-hexval (substr s 3 2)) g (AS4:tbl-hexval (substr s 5 2)) b (AS4:tbl-hexval (substr s 7 2)))
      (if (and r g b) (+ (* r 65536) (* g 256) b) nil))
    ((and (= (strlen s) 7) (= (substr s 1 1) "#"))
      (setq r (AS4:tbl-hexval (substr s 2 2)) g (AS4:tbl-hexval (substr s 4 2)) b (AS4:tbl-hexval (substr s 6 2)))
      (if (and r g b) (+ (* r 65536) (* g 256) b) nil))
    (T
      (setq out "" i 1 prev nil)
      (while (<= i (strlen s))
        (setq ch (substr s i 1))
        (if (member ch '("," ";" " "))
          (progn (if (not prev) (setq out (strcat out ","))) (setq prev T))
          (setq out (strcat out ch) prev nil))
        (setq i (1+ i)))
      (setq parts (AS4:split out ","))
      (if (and (= (length parts) 3)
               (AS4:is-integer-str (nth 0 parts)) (AS4:is-integer-str (nth 1 parts)) (AS4:is-integer-str (nth 2 parts)))
        (progn
          (setq r (atoi (nth 0 parts)) g (atoi (nth 1 parts)) b (atoi (nth 2 parts)))
          (if (and (<= 0 r 255) (<= 0 g 255) (<= 0 b 255)) (+ (* r 65536) (* g 256) b) nil))
        nil))
  )
)

(defun AS4:tbl-all-unique (vals / s ok prev v)
  (setq s (vl-sort vals '<) ok (= (length s) (length vals)) prev nil)
  (foreach v s
    (if (and prev (= v prev)) (setq ok nil))
    (setq prev v)
  )
  ok
)

;; ---- reading the CSV ------------------------------------------------------
;; UTF-8 files read through a legacy ANSI read-line arrive as raw byte
;; sequences. They are decoded here: characters up to U+00FF (umlauts,
;; sharp s, Danish/Swedish letters, accents ...) become the ordinary
;; character of the same code; anything beyond (Turkish dotless i,
;; Polish, Czech, Greek, Cyrillic ...) becomes AutoCAD's own \U+XXXX
;; escape, which is plain ASCII and which AutoCAD displays as the real
;; character in text. A file is only treated as UTF-8 if it has a BOM or
;; every non-ASCII cell is valid UTF-8; otherwise it is left as read.
(defun AS4:tbl-hex (n / digits out)
  (setq digits "0123456789ABCDEF" out "")
  (while (> n 0)
    (setq out (strcat (substr digits (1+ (rem n 16)) 1) out) n (/ n 16)))
  (while (< (strlen out) 4) (setq out (strcat "0" out)))
  out
)

(defun AS4:tbl-cp-str (cp)
  (if (< cp 256) (chr cp) (strcat "\\U+" (AS4:tbl-hex cp)))
)

;; decoded string, or nil if s is not valid UTF-8
(defun AS4:tbl-utf8-decode (s / out i n c need cp k c2 ok)
  (setq out "" i 1 n (strlen s) ok T)
  (while (and ok (<= i n))
    (setq c (ascii (substr s i 1)) need 0)
    (cond
      ((< c 128) (setq out (strcat out (substr s i 1)) i (1+ i)))
      ((and (>= c 194) (<= c 223)) (setq need 1 cp (- c 192)))
      ((and (>= c 224) (<= c 239)) (setq need 2 cp (- c 224)))
      ((and (>= c 240) (<= c 244)) (setq need 3 cp (- c 240)))
      (T (setq ok nil))
    )
    (if (and ok (>= c 128))
      (progn
        (setq k 1)
        (while (and ok (<= k need))
          (setq c2 (if (<= (+ i k) n) (ascii (substr s (+ i k) 1)) 0))
          (if (and (>= c2 128) (<= c2 191))
            (setq cp (+ (* cp 64) (- c2 128)))
            (setq ok nil))
          (setq k (1+ k))
        )
        (if ok (setq out (strcat out (AS4:tbl-cp-str cp)) i (+ i 1 need)))
      )
    )
  )
  (if ok out nil)
)

(defun AS4:tbl-decode-all (recs bom / out ok any r row v d)
  (setq out '() ok T any nil)
  (foreach r recs
    (setq row '())
    (foreach v r
      (setq d (AS4:tbl-utf8-decode v))
      (if d
        (progn (if (/= d v) (setq any T)) (setq row (cons d row)))
        (setq ok nil row (cons v row)))
    )
    (setq out (cons (reverse row) out))
  )
  (if (and any (or ok bom)) (reverse out) recs)
)

(defun AS4:tbl-detect-delim (line / best bestn d n i ch inq)
  (setq best "," bestn 0)
  (foreach d (list "\t" ";" "," "|")
    (setq n 0 inq nil i 1)
    (while (<= i (strlen line))
      (setq ch (substr line i 1))
      (cond
        ((= ch "\"") (setq inq (not inq)))
        ((and (not inq) (= ch d)) (setq n (1+ n)))
      )
      (setq i (1+ i))
    )
    (if (> n bestn) (setq best d bestn n))
  )
  best
)

;; reads a delimited text file into a list of records (each a list of
;; trimmed strings). Handles a BOM, an auto-detected delimiter, quoted
;; fields containing the delimiter, doubled quotes and - importantly -
;; quoted fields that span several lines (read-line is line based, so
;; physical lines are joined while a quote is open).
(defun AS4:tbl-read-records (path / f line recs fields field inq i n ch first delim utf8)
  (setq f (open path "r"))
  (if (not f)
    nil
    (progn
      (setq recs '() fields '() field "" inq nil first T delim "," utf8 nil)
      (while (setq line (read-line f))
        (if (and (> (strlen line) 0) (= (substr line (strlen line)) (chr 13)))
          (setq line (substr line 1 (1- (strlen line)))))
        (if first
          (progn
            (setq first nil)
            (if (and (>= (strlen line) 3)
                     (= (ascii (substr line 1 1)) 239)
                     (= (ascii (substr line 2 1)) 187)
                     (= (ascii (substr line 3 1)) 191))
              (setq line (substr line 4) utf8 T))
            (setq delim (AS4:tbl-detect-delim line))
          )
        )
        (cond
          ((and (not inq) (= line "")) nil)
          ((and (not inq) (not (vl-string-search "\"" line)))
            (setq recs (cons (AS4:split line delim) recs)))
          (T
            (setq i 1 n (strlen line))
            (while (<= i n)
              (setq ch (substr line i 1))
              (cond
                (inq
                  (if (= ch "\"")
                    (if (and (< i n) (= (substr line (1+ i) 1) "\""))
                      (setq field (strcat field "\"") i (1+ i))
                      (setq inq nil))
                    (setq field (strcat field ch))))
                ((= ch "\"") (setq inq T))
                ((= ch delim) (setq fields (cons field fields) field ""))
                (T (setq field (strcat field ch)))
              )
              (setq i (1+ i))
            )
            (if inq
              (setq field (strcat field "\n"))
              (setq recs (cons (reverse (cons field fields)) recs) fields '() field ""))
          )
        )
      )
      (close f)
      (if (or inq (> (strlen field) 0) fields)
        (setq recs (cons (reverse (cons field fields)) recs)))
      (setq recs (reverse recs))
      (setq recs (mapcar '(lambda (r) (mapcar 'AS4:tbl-trim1 r)) recs))
      (AS4:tbl-decode-all recs utf8)
    )
  )
)

;; ---- keys, templates ------------------------------------------------------
;; upper-cases and strips leading zeros from every digit run: 04 -> 4
(defun AS4:tbl-norm-key (s / out i n ch run)
  (setq s (strcase (AS4:trim s)) out "" run "" i 1 n (strlen s))
  (while (<= i (1+ n))
    (setq ch (if (<= i n) (substr s i 1) ""))
    (if (and (/= ch "") (>= (ascii ch) 48) (<= (ascii ch) 57))
      (setq run (strcat run ch))
      (progn
        (if (> (strlen run) 0)
          (progn
            (while (and (> (strlen run) 1) (= (substr run 1 1) "0"))
              (setq run (substr run 2)))
            (setq out (strcat out run) run "")
          )
        )
        (setq out (strcat out ch))
      )
    )
    (setq i (1+ i))
  )
  out
)

;; templates used to be written with braces ({ID}_{ID}_*_*); braces are
;; simply dropped, so old stored templates keep working
(defun AS4:tbl-strip-braces (tpl / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen tpl))
    (setq ch (substr tpl i 1))
    (if (not (member ch '("{" "}"))) (setq out (strcat out ch)))
    (setq i (1+ i))
  )
  out
)

;; the template's separator = first of _ - . / space | : ;
(defun AS4:tbl-tpl-sep (tpl / i ch res)
  (setq i 1 res nil)
  (while (and (not res) (<= i (strlen tpl)))
    (setq ch (substr tpl i 1))
    (if (vl-string-search ch "_-. /|:;") (setq res ch))
    (setq i (1+ i))
  )
  res
)

;; normalized key of a layer name / cell value according to tpl, or nil
;; if it doesn't fit. tpl nil or "" = the whole value is the key.
(defun AS4:tbl-extract-key (name tpl / sep ttoks ntoks i tt nt parts ok)
  (if tpl (setq tpl (AS4:tbl-strip-braces tpl)))
  (cond
    ((or (not tpl) (= tpl ""))
      (if (> (strlen (AS4:trim name)) 0) (AS4:tbl-norm-key name) nil))
    (T
      (setq sep (AS4:tbl-tpl-sep tpl))
      (if (not sep)
        (if (= (strcase tpl) "ID") (AS4:tbl-norm-key name) nil)
        (progn
          (setq ttoks (AS4:split tpl sep) ntoks (AS4:split name sep))
          (if (or (/= (length ttoks) (length ntoks)) (not (member "ID" (mapcar 'strcase ttoks))))
            nil
            (progn
              (setq ok T parts '() i 0)
              (foreach tt ttoks
                (setq nt (nth i ntoks))
                (cond
                  ((= (strcase tt) "ID") (setq parts (cons nt parts)))
                  ((= tt "*"))
                  ((not (wcmatch (strcase nt) (strcase tt))) (setq ok nil))
                )
                (setq i (1+ i))
              )
              (if (and ok parts (not (member "" parts)))
                (AS4:tbl-norm-key (AS4:tbl-join (reverse parts) sep))
                nil)
            )
          )
        )
      )
    )
  )
)

;; ---- layers ---------------------------------------------------------------
(defun AS4:tbl-layers ( / rec out nm)
  (setq out '() rec (tblnext "LAYER" T))
  (while rec
    (setq nm (cdr (assoc 2 rec)))
    (if (not (or (vl-string-search "|" nm) (member (strcase nm) '("0" "DEFPOINTS")))) (setq out (cons nm out)))
    (setq rec (tblnext "LAYER"))
  )
  (reverse out)
)

;; list of (layername . key) for every layer whose name fits the template
(defun AS4:tbl-layer-keys (ltpl / out nm k)
  (setq out '())
  (foreach nm (AS4:tbl-layers)
    (setq k (AS4:tbl-extract-key nm ltpl))
    (if k (setq out (cons (cons nm k) out)))
  )
  (reverse out)
)

(defun AS4:tbl-layers-for-key (ltpl key / out lk)
  (setq out '())
  (foreach lk (AS4:tbl-layer-keys ltpl)
    (if (= (cdr lk) key) (setq out (cons (car lk) out)))
  )
  (reverse out)
)

;; ---- link storage (next to the drawing) -------------------------------------
(defun AS4:tbl-file ( / d)
  (setq d (getvar "DWGPREFIX"))
  (if (and d (> (strlen d) 0)) (strcat d "as4cad_tables.dat") nil)
)

(defun AS4:tbl-slash (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (setq out (strcat out (if (= ch "\\") "/" ch)))
    (setq i (1+ i))
  )
  out
)

;; paths inside the drawing's folder are stored relative to it, so the
;; whole project folder can be moved or shared
(defun AS4:tbl-relpath (p / d)
  (setq p (AS4:tbl-slash p) d (AS4:tbl-slash (getvar "DWGPREFIX")))
  (if (and (> (strlen d) 0) (>= (strlen p) (strlen d))
           (= (strcase (substr p 1 (strlen d))) (strcase d)))
    (substr p (1+ (strlen d)))
    p)
)

(defun AS4:tbl-resolve (p / d)
  (setq p (AS4:tbl-slash p) d (AS4:tbl-slash (getvar "DWGPREFIX")))
  (if (or (and (>= (strlen p) 2) (= (substr p 2 1) ":")) (= (substr p 1 1) "/"))
    p
    (strcat d p))
)

;; a link = (csvpath keycolumn-name layer-template table-template)
(defun AS4:tbl-links-load ( / path f line parts out)
  (setq out '() path (AS4:tbl-file))
  (if (and path (findfile path))
    (progn
      (setq f (open path "r"))
      (if f
        (progn
          (while (setq line (read-line f))
            (setq parts (AS4:split line (chr 9)))
            (if (and (= (car parts) "LINK") (>= (length parts) 5))
              (setq out (cons (list (nth 1 parts) (nth 2 parts) (AS4:tbl-strip-braces (nth 3 parts)) (AS4:tbl-strip-braces (nth 4 parts))) out)))
          )
          (close f)
        )
      )
    )
  )
  (reverse out)
)

(defun AS4:tbl-links-save (links / path f l)
  (setq path (AS4:tbl-file))
  (if path
    (progn
      (setq f (open path "w"))
      (if f
        (progn
          (foreach l links
            (write-line (strcat "LINK" (chr 9) (nth 0 l) (chr 9) (nth 1 l) (chr 9) (nth 2 l) (chr 9) (nth 3 l)) f))
          (close f)
          T
        )
      )
    )
  )
)

;; ---- opening a linked table ---------------------------------------------------
;; returns (headers rows keycol-index index duplicate-keys rows-without-key)
;; where index = list of (normalized-key . row-number)
(defun AS4:tbl-open (link / full recs hdrs data kidx i h idx dups rowi row raw k nokey)
  (setq full (findfile (AS4:tbl-resolve (nth 0 link))))
  (cond
    ((not full)
      (princ (strcat "\nTable file not found: " (nth 0 link))) nil)
    (T
      (setq recs (AS4:tbl-read-records full))
      (if (or (not recs) (< (length recs) 2))
        (progn (princ (strcat "\nTable file is empty or unreadable: " (nth 0 link))) nil)
        (progn
          (setq hdrs (car recs) data (cdr recs) kidx nil i 0)
          (foreach h hdrs
            (if (and (not kidx) (= (strcase h) (strcase (nth 1 link)))) (setq kidx i))
            (setq i (1+ i))
          )
          (if (not kidx)
            (progn
              (princ (strcat "\nKey column \"" (nth 1 link) "\" not found in " (nth 0 link) " - relink the table."))
              nil)
            (progn
              (setq idx '() dups '() nokey 0 rowi 0)
              (foreach row data
                (setq raw (AS4:tbl-cell row kidx))
                (setq k (AS4:tbl-extract-key raw (nth 3 link)))
                (cond
                  ((not k) (setq nokey (1+ nokey)))
                  ((assoc k idx) (setq dups (cons k dups)))
                  (T (setq idx (cons (cons k rowi) idx)))
                )
                (setq rowi (1+ rowi))
              )
              (list hdrs data kidx (reverse idx) (reverse dups) nokey)
            )
          )
        )
      )
    )
  )
)

;; ---- column profile ------------------------------------------------------------
;; one entry per column: (index name filled uniq type allunique samples)
;; uniq counting stops at 41 ("many"); type = number / category / text
(defun AS4:tbl-profile (hdrs data / i m vals seen many num v out row rgb)
  (setq m (length hdrs) i 0 out '())
  (while (< i m)
    (setq vals '() seen '() many nil num T rgb T)
    (foreach row data
      (setq v (AS4:tbl-cell row i))
      (if (> (strlen v) 0)
        (progn
          (setq vals (cons v vals))
          (if (not (AS4:tbl-numeric-p v)) (setq num nil))
          (if (and rgb (not (AS4:tbl-parse-rgb v))) (setq rgb nil))
          (if (and (not many) (not (member v seen)))
            (progn
              (setq seen (cons v seen))
              (if (> (length seen) 40) (setq many T))))
        )
      )
    )
    (setq out
      (cons
        (list i (nth i hdrs) (length vals) (if many 41 (length seen))
              (cond ((= (length vals) 0) "empty")
                    (rgb "color")
                    (num "number")
                    ((not many) "category")
                    (T "text"))
              (and (> (length data) 0) (= (length vals) (length data)) (AS4:tbl-all-unique vals))
              (reverse seen))
        out))
    (setq i (1+ i))
  )
  (reverse out)
)

;; true if (almost) every comma-separated token in the column is a value
;; of the key column - i.e. the column lists other units (stratigraphic
;; relations such as "lies under", "cuts")
(defun AS4:tbl-relation-p (data i keyvals / hits tot row v tok n)
  (setq hits 0 tot 0 n 0)
  (foreach row data
    (setq v (AS4:tbl-cell row i))
    (if (and (> (strlen v) 0) (< n 40))
      (progn
        (setq n (1+ n))
        (foreach tok (AS4:split v ",")
          (setq tok (AS4:trim tok))
          (if (> (strlen tok) 0)
            (progn (setq tot (1+ tot)) (if (member tok keyvals) (setq hits (1+ hits)))))
        )
      )
    )
  )
  (and (> tot 0) (>= (* 10 hits) (* 9 tot)))
)

;; ---- AS4TABLE steps -------------------------------------------------------------
(defun AS4:tbl-report (link ask / tb idx lkeys used nolay rowlay lk e matched yn)
  (setq tb (AS4:tbl-open link))
  (if tb
    (progn
      (setq idx (nth 3 tb) lkeys (AS4:tbl-layer-keys (nth 2 link)) used '() nolay '() matched 0)
      (foreach lk lkeys
        (if (assoc (cdr lk) idx)
          (progn
            (setq matched (1+ matched))
            (if (not (member (cdr lk) used)) (setq used (cons (cdr lk) used))))
          (setq nolay (cons (car lk) nolay))
        )
      )
      (setq nolay (reverse nolay) rowlay '())
      (foreach e idx
        (if (not (member (car e) used))
          (setq rowlay (cons (AS4:tbl-cell (nth (cdr e) (nth 1 tb)) (nth 2 tb)) rowlay))))
      (setq rowlay (reverse rowlay))
      (princ (strcat "\n=== " (nth 0 link) " ==="))
      (princ (strcat "\n" (itoa (length (nth 1 tb))) " table row(s), " (itoa (length (nth 0 tb))) " column(s)."))
      (princ (strcat "\nKey column: " (nth 1 link)
                     "   table template: " (if (= (nth 3 link) "") "(whole value)" (nth 3 link))
                     "   layer template: " (if (= (nth 2 link) "") "(whole name)" (nth 2 link))))
      (if (> (nth 5 tb) 0)
        (princ (strcat "\n" (itoa (nth 5 tb)) " row(s) have no usable key (empty or not fitting the table template).")))
      (if (nth 4 tb)
        (AS4:tbl-print-list "Duplicate keys in the table (only the first row is used)" (nth 4 tb) 15))
      (princ (strcat "\nLayers fitting the layer template: " (itoa (length lkeys))
                     "   assigned to a table row: " (itoa matched)
                     "   table rows with at least one layer: " (itoa (length used)) " of " (itoa (length idx))))
      (if nolay (AS4:tbl-print-list "Layers fitting the template but with no table row" nolay 25))
      (if rowlay (AS4:tbl-print-list "Table rows without any layer" rowlay 25))
      (if (and (= matched 0) (> (length idx) 0))
        (princ "\nNo layer matched a table row - check the key column and both templates (Link)."))
      (if ask
        (progn
          (initget "No Yes")
          (setq yn (getkword "\nWrite the list of layers and table rows to a CSV file? [No/Yes] <No>: "))
          (if (= yn "Yes") (AS4:tbl-report-csv tb lkeys idx used))))
    )
  )
)

(defun AS4:tbl-columns (link / tb)
  (setq tb (AS4:tbl-open link))
  (if tb (progn (princ (strcat "\n=== Columns of " (nth 0 link) " ===")) (AS4:tbl-columns-print tb)))
)

;; numbered overview of every column that has data: number, name,
;; filled rows, type and a few example values - the numbers are what
;; Filter / Name refer to
(defun AS4:tbl-columns-print (tb / prof keyvals row p label nempty)
  (setq keyvals '() nempty 0)
  (foreach row (nth 1 tb) (setq keyvals (cons (AS4:tbl-cell row (nth 2 tb)) keyvals)))
  (setq prof (AS4:tbl-profile (nth 0 tb) (nth 1 tb)))
  (foreach p prof
    (if (= (nth 2 p) 0)
      (setq nempty (1+ nempty))
      (progn
        (setq label (nth 4 p))
        (if (and (/= (nth 0 p) (nth 2 tb)) (member label '("text" "category"))
                 (AS4:tbl-relation-p (nth 1 tb) (nth 0 p) keyvals))
          (setq label "relation"))
        (princ (strcat "\n" (AS4:tbl-pad (itoa (1+ (nth 0 p))) 4)
                       (AS4:tbl-pad (nth 1 p) 36)
                       (AS4:tbl-pad (itoa (nth 2 p)) 5)
                       (AS4:tbl-pad (if (= label "category") (strcat "category (" (itoa (nth 3 p)) ")") label) 15)
                       (cond
                         ((= label "category")
                           (AS4:tbl-oneline (AS4:tbl-join (mapcar '(lambda (s) (AS4:tbl-oneline s 22)) (AS4:tbl-firstn (nth 6 p) 6)) " | ") 100))
                         ((= label "text")
                           (AS4:tbl-oneline (car (nth 6 p)) 40))
                         ((= label "relation") "-> key column")
                         (T "")
                       )))
      )
    )
  )
  (princ (strcat "\n" (itoa nempty) " column(s) without any data not shown."))
)

;; asks for a column: its number, or part of its name (e.g. "Skel"
;; lists the columns containing it). Returns the 0-based column index,
;; 'DONE for a plain Enter, 'AGAIN if the user should be asked again.
(defun AS4:tbl-ask-column (link tb prof prompt / ans ms p m n)
  (setq ans (getstring T prompt))
  (cond
    ((= ans "") 'DONE)
    ((= (strcase ans) "L") (AS4:tbl-columns link) 'AGAIN)
    ((and (AS4:tbl-numeric-p ans) (>= (atoi ans) 1) (<= (atoi ans) (length (nth 0 tb))))
      (setq n (1- (atoi ans)))
      (if (= (nth 2 (nth n prof)) 0)
        (progn (princ "\nThat column has no data.") 'AGAIN)
        n))
    (T
      (setq ms '())
      (foreach p prof
        (if (and (> (nth 2 p) 0) (vl-string-search (strcase ans) (strcase (nth 1 p))))
          (setq ms (cons (nth 0 p) ms))))
      (setq ms (reverse ms))
      (cond
        ((not ms) (princ (strcat "\nNo column name contains \"" ans "\".")) 'AGAIN)
        ((= (length ms) 1) (car ms))
        (T
          (princ (strcat "\n" (itoa (length ms)) " columns contain \"" ans "\" - enter the number of the one you want:"))
          (foreach m ms (princ (strcat "\n  " (AS4:tbl-pad (itoa (1+ m)) 4) (nth 1 (nth m prof)))))
          'AGAIN)
      )
    )
  )
)

(defun AS4:tbl-firstn (lst n / out)
  (setq out '())
  (while (and lst (> n 0))
    (setq out (cons (car lst) out) lst (cdr lst) n (1- n)))
  (reverse out)
)

(defun AS4:tbl-show-row (tb rowi / row i h v)
  (setq row (nth rowi (nth 1 tb)) i 0)
  (princ (strcat "\n--- Table row: " (AS4:tbl-cell row (nth 2 tb)) " ---"))
  (foreach h (nth 0 tb)
    (setq v (AS4:tbl-cell row i))
    (if (> (strlen v) 0) (princ (strcat "\n  " h ": " (AS4:tbl-oneline v 110))))
    (setq i (1+ i))
  )
)

;; shows a table row and the layers assigned to it; sel = also zoom to
;; and select everything on those layers
(defun AS4:tbl-show-hit (link tb key rowi sel / names ss n total pat nm)
  (AS4:tbl-show-row tb rowi)
  (setq names (AS4:tbl-layers-for-key (nth 2 link) key) total 0)
  (if (not names)
    (princ "\nNo layer is assigned to this row.")
    (progn
      (princ (strcat "\nLayer(s) assigned to this row (" (itoa (length names)) "):"))
      (foreach nm names
        (setq ss (ssget "X" (list (cons 8 (AS4:wc-escape nm)))))
        (setq n (if ss (sslength ss) 0) total (+ total n))
        (princ (strcat "\n  " nm "  (" (itoa n) " object(s))"))
      )
      (if (and sel (> total 0))
        (progn
          (setq pat (AS4:tbl-join (mapcar 'AS4:wc-escape names) ","))
          (setq ss (ssget "X" (list (cons 8 pat))))
          (if ss
            (progn
              (AS4:zoom-to-selection ss)
              (sssetfirst nil ss)
              (princ (strcat "\nZoomed to and selected " (itoa (sslength ss)) " object(s).")))
          )
        )
      )
    )
  )
)

;; click an object (its layer -> key -> table row), type a key, or
;; Enter for the current layer
(defun AS4:tbl-info (links / inp lay l tb k hit key s)
  (setq inp (AS4:pick-or-text "\nClick an object (its table row), Enter = current layer, or type a key (e.g. 202616_1): "))
  (cond
    ((not inp) (princ "\nCancelled."))
    ((or (= (type inp) 'ENAME) (= inp ""))
      (setq lay (if (= (type inp) 'ENAME) (cdr (assoc 8 (entget inp))) (getvar "CLAYER")) hit nil)
      (foreach l links
        (if (not hit)
          (progn
            (setq tb (AS4:tbl-open l) k (AS4:tbl-extract-key lay (nth 2 l)))
            (if (and tb k (assoc k (nth 3 tb)))
              (progn (setq hit T) (AS4:tbl-show-hit l tb k (cdr (assoc k (nth 3 tb))) nil))))
        )
      )
      (if (not hit)
        (princ (strcat "\nLayer \"" lay "\" has no row in the linked table(s)."))))
    (T
      (setq hit nil)
      (foreach l links
        (if (not hit)
          (progn
            (setq tb (AS4:tbl-open l) key nil)
            (if tb
              (foreach s (list (AS4:tbl-extract-key inp (nth 2 l)) (AS4:tbl-extract-key inp (nth 3 l)) (AS4:tbl-norm-key inp))
                (if (and s (not key) (assoc s (nth 3 tb))) (setq key s))))
            (if key
              (progn (setq hit T) (AS4:tbl-show-hit l tb key (cdr (assoc key (nth 3 tb))) T))))
        )
      )
      (if (not hit) (princ (strcat "\nNo table row found for \"" inp "\".")))
    )
  )
)

;; ---- remembered defaults (key column + templates) ---------------------------
;; stored next to the drawing AND in the home directory, so the next Link
;; (also after Unlink, or in another project) starts from the last choices
(defun AS4:tbl-defaults-paths ( / d h)
  (setq d (getvar "DWGPREFIX") h (AS4:home-dir))
  (list (if (and d (> (strlen d) 0)) (strcat d "as4cad_tabledefaults.dat") nil)
        (if h (strcat h ".as4cad_tabledefaults.dat") nil))
)

(defun AS4:tbl-defaults-load ( / p f line parts res)
  (setq res nil)
  (foreach p (AS4:tbl-defaults-paths)
    (if (and p (not res) (findfile p))
      (progn
        (setq f (open p "r"))
        (if f
          (progn
            (setq line (read-line f))
            (close f)
            (if line
              (progn
                (setq parts (AS4:split line (chr 9)))
                (if (and (= (car parts) "DEFAULT") (>= (length parts) 4))
                  (setq res (list (nth 1 parts) (AS4:tbl-strip-braces (nth 2 parts)) (AS4:tbl-strip-braces (nth 3 parts)))))))
          )
        )
      )
    )
  )
  res
)

(defun AS4:tbl-defaults-save (key ltpl ttpl / p f)
  (foreach p (AS4:tbl-defaults-paths)
    (if p
      (progn
        (setq f (open p "w"))
        (if f
          (progn
            (write-line (strcat "DEFAULT" (chr 9) key (chr 9) ltpl (chr 9) ttpl) f)
            (close f))))))
)

;; ---- Link ---------------------------------------------------------------------
(defun AS4:tbl-link ( / path recs hdrs data prof cands p ans keyname ltpl ttpl sugg k1 kidx links newl shown nm dflt dk dl dt l)
  (setq path (getfiled "Select the table (CSV)" (getvar "DWGPREFIX") "csv;txt;tsv" 4))
  (if (not path)
    (princ "\nCancelled.")
    (progn
      (setq recs (AS4:tbl-read-records path))
      (if (or (not recs) (< (length recs) 2))
        (princ "\nThe file is empty or could not be read.")
        (progn
          (setq hdrs (car recs) data (cdr recs))
          (setq prof (AS4:tbl-profile hdrs data) cands '())
          (foreach p prof (if (nth 5 p) (setq cands (cons p cands))))
          (setq cands (reverse cands))
          (setq dflt (AS4:tbl-defaults-load) dk nil)
          (if dflt
            (foreach nm hdrs
              (if (and (not dk) (= (strcase nm) (strcase (nth 0 dflt)))) (setq dk nm))))
          (if (and (not dk) cands) (setq dk (nth 1 (car cands))))
          (princ (strcat "\n" (itoa (length data)) " row(s), " (itoa (length hdrs)) " column(s) read."))
          (if cands
            (progn
              (princ "\nColumns where every row has a different value (key candidates):")
              (foreach p cands
                (princ (strcat "\n  " (AS4:tbl-pad (itoa (1+ (nth 0 p))) 4) (AS4:tbl-pad (nth 1 p) 30)
                               "e.g. " (AS4:tbl-oneline (car (nth 6 p)) 40)))))
            (princ "\nNo column has a different value in every row - pick the closest one; duplicates will be reported."))
          (setq ans (getstring T (strcat "\nKey column - number or name" (if dk (strcat " <" dk ">") "") ": ")))
          (setq keyname nil)
          (cond
            ((and (= ans "") dk) (setq keyname dk))
            ((and (> (strlen ans) 0) (AS4:tbl-numeric-p ans) (>= (atoi ans) 1) (<= (atoi ans) (length hdrs)))
              (setq keyname (nth (1- (atoi ans)) hdrs)))
            (T (foreach nm hdrs (if (and (not keyname) (= (strcase nm) (strcase ans))) (setq keyname nm))))
          )
          (if (not keyname)
            (princ "\nNo such column - cancelled.")
            (progn
              (setq kidx (vl-position keyname hdrs))
              (setq k1 (AS4:tbl-cell (car data) kidx))
              (princ (strcat "\nFirst value of the key column: " k1))
              (setq shown 0)
              (princ "\nSome layer names of this drawing:")
              (foreach nm (AS4:tbl-layers)
                (if (and (< shown 8) (/= nm "0") (/= (strcase nm) "DEFPOINTS")
                         (/= (strcase (substr nm 1 (min 4 (strlen nm)))) "AS4_"))
                  (progn (princ (strcat "\n  " nm)) (setq shown (1+ shown)))))
              (setq dl (if dflt (nth 1 dflt) ""))
              (setq ans (getstring T (strcat "\nLayer name template - ID marks the key part(s), * any part, e.g. ID_ID_*_* "
                                             (if (/= dl "") (strcat "<" dl "> ") "")
                                             "(- = whole layer name is the key): ")))
              (setq ltpl (cond ((= ans "") dl) ((= ans "-") "") (T (AS4:trim ans))))
              (setq dt (if dflt (nth 2 dflt) ""))
              (setq sugg (cond
                           ((and (/= dt "") (AS4:tbl-extract-key k1 dt)) dt)
                           ((and (/= ltpl "") (AS4:tbl-extract-key k1 ltpl)) ltpl)
                           (T "")))
              (cond
                ((/= sugg "")
                  (setq ans (getstring T (strcat "\nTemplate for the key column's values <" sugg "> (- = use the whole value): ")))
                  (setq ttpl (cond ((= ans "") sugg) ((= ans "-") "") (T (AS4:trim ans)))))
                (T
                  (setq ttpl "")
                  (princ "\nThe key column's values are used as they are."))
              )
              (setq newl (list (AS4:tbl-relpath path) keyname ltpl ttpl))
              (setq links '())
              (foreach l (AS4:tbl-links-load)
                (if (not (and (= (strcase (car l) T) (strcase (car newl) T)) (= (cadr l) (cadr newl))))
                  (setq links (cons l links))))
              (setq links (reverse (cons newl links)))
              (if (AS4:tbl-links-save links)
                (princ "\nLink saved next to the drawing (as4cad_tables.dat).")
                (princ "\nNote: the drawing has not been saved yet - the link could not be stored. Save the drawing and run Link again."))
              (AS4:tbl-defaults-save keyname ltpl ttpl)
              (AS4:tbl-report newl nil)
            )
          )
        )
      )
    )
  )
)

;; ---- Report export (layers <-> table rows as a CSV file) --------------------------
(defun AS4:tbl-q (s / out i ch)
  (setq out "\"" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (setq out (strcat out (if (= ch "\"") "\"\"" ch)))
    (setq i (1+ i))
  )
  (strcat out "\"")
)

(defun AS4:tbl-report-csv (tb lkeys idx used / path f lk e r)
  (setq path (strcat (getvar "DWGPREFIX") "as4cad_tablereport.csv"))
  (setq f (open path "w"))
  (if (not f)
    (princ "\nCould not write the report file.")
    (progn
      (write-line "layer,key,status,table_row" f)
      (foreach lk lkeys
        (setq r (assoc (cdr lk) idx))
        (write-line
          (strcat (AS4:tbl-q (car lk)) "," (AS4:tbl-q (cdr lk)) ","
                  (AS4:tbl-q (if r "assigned" "no table row")) ","
                  (AS4:tbl-q (if r (AS4:tbl-cell (nth (cdr r) (nth 1 tb)) (nth 2 tb)) "")))
          f))
      (foreach e idx
        (if (not (member (car e) used))
          (write-line
            (strcat "\"\"," (AS4:tbl-q (car e)) ",\"row without layer\","
                    (AS4:tbl-q (AS4:tbl-cell (nth (cdr e) (nth 1 tb)) (nth 2 tb))))
            f)))
      (close f)
      (princ (strcat "\nWritten: " path))
    )
  )
)

;; ---- shared helpers for Filter / Name ---------------------------------------

(defun AS4:tbl-pick-link (links / i l n)
  (if (= (length links) 1)
    (car links)
    (progn
      (setq i 1)
      (foreach l links
        (princ (strcat "\n  " (itoa i) "  " (car l)))
        (setq i (1+ i)))
      (setq n (getint "\nWhich table <1>: "))
      (if (not n) (setq n 1))
      (if (and (>= n 1) (<= n (length links))) (nth (1- n) links) nil)
    )
  )
)

;; list of (row-number layername ...) for every table row that has layers
(defun AS4:tbl-rowlayers (link tb / out lk r cell)
  (setq out '())
  (foreach lk (AS4:tbl-layer-keys (nth 2 link))
    (setq r (assoc (cdr lk) (nth 3 tb)))
    (if r
      (progn
        (setq cell (assoc (cdr r) out))
        (if cell
          (setq out (subst (append cell (list (car lk))) cell out))
          (setq out (append out (list (list (cdr r) (car lk))))))
      )
    )
  )
  out
)

(defun AS4:tbl-value-counts (data i / out v c row)
  (setq out '())
  (foreach row data
    (setq v (AS4:tbl-cell row i))
    (setq c (assoc v out))
    (if c
      (setq out (subst (cons v (1+ (cdr c))) c out))
      (setq out (append out (list (cons v 1)))))
  )
  out
)

;; selects (and optionally only zooms to) everything on the given layers
(defun AS4:tbl-select-layers (names zoomonly / ss)
  (if (not names)
    (princ "\nNo layers to select.")
    (progn
      (setq ss (ssget "X" (list (cons 8 (AS4:tbl-join (mapcar 'AS4:wc-escape names) ",")))))
      (if (not ss)
        (princ "\nThe layers contain no objects.")
        (progn
          (AS4:zoom-to-selection ss)
          (if (not zoomonly) (sssetfirst nil ss))
          (princ (strcat "\n" (if zoomonly "Zoomed to " "Zoomed to and selected ") (itoa (sslength ss))
                         " object(s) on " (itoa (length names)) " layer(s)."))
        )
      )
    )
  )
)

(defun AS4:tbl-all-layers ( / out nm rec)
  (setq out '() rec (tblnext "LAYER" T))
  (while rec
    (setq nm (cdr (assoc 2 rec)))
    (if (not (vl-string-search "|" nm)) (setq out (cons nm out)))
    (setq rec (tblnext "LAYER")))
  (reverse out)
)

;; ---- Isolate ---------------------------------------------------------------------------------
;; objects of the given layers in the current space (selection set or nil)
(defun AS4:tbl-objects-of (names / res chunk n nm)
  (setq res (ssadd) chunk '() n 0)
  (foreach nm names
    (setq chunk (cons (AS4:wc-escape nm) chunk) n (1+ n))
    (if (>= n 20)
      (progn (AS4:tbl-ss-merge res chunk) (setq chunk '() n 0))))
  (if chunk (AS4:tbl-ss-merge res chunk))
  (if (> (sslength res) 0) res nil)
)

(defun AS4:tbl-ss-merge (res chunk / ss i)
  (setq ss (ssget "X" (list (cons 8 (AS4:tbl-join chunk ",")) (cons 410 (getvar "CTAB")))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (ssadd (ssname ss i) res)
        (setq i (1+ i)))))
  res
)

;; Isolate = the program's own ISOLATEOBJECTS on the objects of the matching
;; layers (all other objects of the current space are hidden); UNISOLATEOBJECTS
;; brings everything back, also outside AS4TABLE. Matching layers that are
;; switched off are switched on first (Back restores them).
;; Returns nil if ISOLATEOBJECTS is not available.
(defun AS4:tbl-isolate-objects (names / ops nm st ss err)
  (setq ops '())
  (foreach nm names
    (setq st (AS4:tbl-layer-get nm))
    (if (and st (not (nth 1 st))) (setq ops (cons (list nm nil "on" nil) ops))))
  (if ops (AS4:tbl-layer-apply2 ops nil))
  (setq ss (AS4:tbl-objects-of names))
  (cond
    ((not ss) (princ "\nThe layers contain no objects in the current space.") T)
    (T
      (setq err (vl-catch-all-apply '(lambda () (command "_.ISOLATEOBJECTS" ss ""))))
      (if (vl-catch-all-error-p err)
        nil
        (progn
          (setq *AS4:tbl-objiso* T)
          (AS4:tbl-select-layers names T)
          (princ (strcat "\n" (itoa (sslength ss)) " object(s) isolated (ISOLATEOBJECTS). Bring everything back with UNISOLATEOBJECTS or Back."))
          T)))
  )
)

;; the old way: every other layer is switched off
(defun AS4:tbl-isolate-layers (names / ops cur nm)
  (setq ops '() cur (getvar "CLAYER"))
  (foreach nm (AS4:tbl-all-layers)
    (setq ops (cons (list nm nil (if (member nm names) "on" "off") nil) ops)))
  (AS4:tbl-layer-apply2 ops (if (member cur names) nil (car names)))
  (AS4:tbl-select-layers names T)
  (princ (strcat "\nOnly the " (itoa (length names)) " matching layer(s) are on now (Back restores)."))
)

;; ---- original layer state (so Isolate can always be undone) ------------------------
(defun AS4:tbl-state-file ( / d)
  (setq d (getvar "DWGPREFIX"))
  (if (and d (> (strlen d) 0)) (strcat d "as4cad_tablestate.dat") nil)
)

;; entries: (name aci on tc)
(defun AS4:tbl-state-load ( / path f line parts out)
  (setq out '() path (AS4:tbl-state-file))
  (if (and path (findfile path))
    (progn
      (setq f (open path "r"))
      (if f
        (progn
          (while (setq line (read-line f))
            (setq parts (AS4:split line (chr 9)))
            (if (and (= (car parts) "L") (>= (length parts) 5))
              (setq out (cons (list (nth 1 parts) (atoi (nth 2 parts)) (= (nth 3 parts) "1")
                                    (if (= (nth 4 parts) "-") nil (atoi (nth 4 parts)))) out)))
          )
          (close f)
        )
      )
    )
  )
  (reverse out)
)

(defun AS4:tbl-state-clayer ( / path f line parts out)
  (setq out nil path (AS4:tbl-state-file))
  (if (and path (findfile path))
    (progn
      (setq f (open path "r"))
      (if f
        (progn
          (while (setq line (read-line f))
            (setq parts (AS4:split line (chr 9)))
            (if (and (= (car parts) "C") (>= (length parts) 2)) (setq out (nth 1 parts))))
          (close f)))))
  out
)

(defun AS4:tbl-state-write (entries clayer / path f e)
  (setq path (AS4:tbl-state-file))
  (if path
    (if (and (not entries) (not clayer))
      (if (findfile path) (vl-file-delete path))
      (progn
        (setq f (open path "w"))
        (if f
          (progn
            (if clayer (write-line (strcat "C" (chr 9) clayer) f))
            (foreach e entries
              (write-line (strcat "L" (chr 9) (nth 0 e) (chr 9) (itoa (nth 1 e)) (chr 9)
                                  (if (nth 2 e) "1" "0") (chr 9) (if (nth 3 e) (itoa (nth 3 e)) "-")) f))
            (close f)))))
  )
)

(defun AS4:tbl-layer-get (nm / e d c)
  (setq e (tblobjname "LAYER" nm))
  (if e
    (progn
      (setq d (entget e) c (cdr (assoc 62 d)))
      (list (abs c) (>= c 0) (cdr (assoc 420 d))))
    nil)
)

(defun AS4:tbl-layer-put (nm aci on tc / e d)
  (setq e (tblobjname "LAYER" nm))
  (if e
    (progn
      (setq d (entget e))
      (setq d (subst (cons 62 (if on aci (- aci))) (assoc 62 d) d))
      (if (assoc 420 d) (setq d (vl-remove (assoc 420 d) d)))
      (if tc (setq d (append d (list (cons 420 tc)))))
      (entmod d)
    )
  )
)

;; ops = list of (layername new-aci-or-nil "on"/"off"/nil true-color-or-nil);
;; remembers the first-seen original of each layer in
;; as4cad_tablestate.dat. newclayer = a layer to make current first (the
;; original current layer is remembered too), or nil.
(defun AS4:tbl-layer-apply2 (ops newclayer / st op nm cur on cl)
  (setq st (AS4:tbl-state-load) cl (AS4:tbl-state-clayer))
  (if newclayer
    (progn
      (if (not cl) (setq cl (getvar "CLAYER")))
      (vl-catch-all-apply 'setvar (list "CLAYER" newclayer))))
  (foreach op ops
    (setq nm (car op) cur (AS4:tbl-layer-get nm))
    (if cur
      (progn
        (if (not (assoc nm st))
          (setq st (append st (list (list nm (nth 0 cur) (nth 1 cur) (nth 2 cur))))))
        (setq on (cond ((= (nth 2 op) "off") nil) ((= (nth 2 op) "on") T) (T (nth 1 cur))))
        (AS4:tbl-layer-put nm (if (nth 1 op) (nth 1 op) (nth 0 cur)) on
                           (cond ((nth 3 op) (nth 3 op)) ((nth 1 op) nil) (T (nth 2 cur))))
      )
    )
  )
  (AS4:tbl-state-write st cl)
)

(defun AS4:tbl-restore ( / st e cl wasiso)
  (setq wasiso *AS4:tbl-objiso*)
  (if wasiso
    (progn
      (vl-catch-all-apply '(lambda () (command "_.UNISOLATEOBJECTS")))
      (setq *AS4:tbl-objiso* nil)
      (princ "\nObjects shown again (UNISOLATEOBJECTS).")))
  (setq st (AS4:tbl-state-load) cl (AS4:tbl-state-clayer))
  (if st
    (foreach e st
      (if (tblsearch "LAYER" (car e))
        (AS4:tbl-layer-put (nth 0 e) (nth 1 e) (nth 2 e) (nth 3 e)))))
  (if (and cl (tblsearch "LAYER" cl))
    (vl-catch-all-apply 'setvar (list "CLAYER" cl)))
  (AS4:tbl-state-write nil nil)
  (if st (princ (strcat "\nRestored the original visibility of " (itoa (length st)) " layer(s).")))
  (if (and (not st) (not wasiso)) (princ "\nNothing to restore."))
)

;; ---- Filter -------------------------------------------------------------------------------
(defun AS4:tbl-ask-crit (link tb prof ncrit / n p vals i pick parts tok w lo hi v ans)
  (setq n (AS4:tbl-ask-column link tb prof
            (if (= ncrit 0)
              "\nCriterion 1 - column number or part of its name (L = list columns, Enter = cancel): "
              (strcat "\nCriterion " (itoa (1+ ncrit)) " (must match as well) - column number or part of its name (L = list columns, Enter = finish): "))))
  (cond
    ((eq n 'DONE) 'DONE)
    ((eq n 'AGAIN) 'AGAIN)
    (T
      (setq p (nth n prof))
      (princ (strcat "\nColumn: " (nth 1 p)))
      (cond
        ((= (nth 4 p) "category")
          (setq vals (AS4:tbl-value-counts (nth 1 tb) n) i 1)
          (foreach v vals
            (princ (strcat "\n  " (itoa i) "  " (if (= (car v) "") "(empty)" (AS4:tbl-oneline (car v) 60))
                           "  (" (itoa (cdr v)) ")"))
            (setq i (1+ i)))
          (setq ans (getstring T "\nNumber(s) comma-separated, * = any value, - = empty: "))
          (setq pick '())
          (foreach tok (AS4:split ans ",")
            (setq tok (AS4:trim tok))
            (cond
              ((= tok "*") (setq pick (cons "*" pick)))
              ((= tok "-") (setq pick (cons "-" pick)))
              ((and (AS4:tbl-numeric-p tok) (>= (atoi tok) 1) (<= (atoi tok) (length vals)))
                (setq pick (cons (car (nth (1- (atoi tok)) vals)) pick)))
            )
          )
          (if pick (list n "in" pick) (progn (princ "\nNo valid choice.") 'AGAIN)))
        ((= (nth 4 p) "number")
          (setq ans (getstring T "\nRange min,max (either may be left empty, decimal point): "))
          (setq parts (AS4:split ans ","))
          (setq lo (if (and (nth 0 parts) (> (strlen (AS4:trim (nth 0 parts))) 0)) (AS4:safe-atof (AS4:trim (nth 0 parts))) nil))
          (setq hi (if (and (nth 1 parts) (> (strlen (AS4:trim (nth 1 parts))) 0)) (AS4:safe-atof (AS4:trim (nth 1 parts))) nil))
          (if (or lo hi) (list n "range" (list lo hi)) (progn (princ "\nNo range entered.") 'AGAIN)))
        (T
          (setq ans (getstring T "\nWord(s) contained in the cell, comma-separated (any of them): "))
          (setq pick '())
          (foreach w (AS4:split ans ",")
            (setq w (AS4:trim w))
            (if (> (strlen w) 0) (setq pick (cons (strcase w) pick))))
          (if pick (list n "has" pick) (progn (princ "\nNothing entered.") 'AGAIN)))
      )
    )
  )
)

;; one criterion in words, e.g.  Befundtyp = Mauer | Grube
(defun AS4:tbl-crit-text (prof c / p tt lo hi)
  (setq p (nth (nth 0 c) prof) tt (nth 1 c))
  (strcat (nth 1 p)
    (cond
      ((= tt "in")
        (strcat " = " (AS4:tbl-join (mapcar '(lambda (v) (cond ((= v "*") "(any value)") ((= v "-") "(empty)") (T (AS4:tbl-oneline v 30))))
                                            (reverse (nth 2 c))) " | ")))
      ((= tt "range")
        (setq lo (car (nth 2 c)) hi (cadr (nth 2 c)))
        (strcat ": " (if lo (rtos lo 2 4) "...") " to " (if hi (rtos hi 2 4) "...")))
      (T (strcat " contains " (AS4:tbl-join (reverse (nth 2 c)) " | ")))
    )
  )
)

(defun AS4:tbl-crit-ok (row c / v tt w ok num)
  (setq v (AS4:tbl-cell row (nth 0 c)) tt (nth 1 c))
  (cond
    ((= tt "in")
      (or (and (member v (nth 2 c)) T)
          (and (member "*" (nth 2 c)) (> (strlen v) 0))
          (and (member "-" (nth 2 c)) (= v ""))))
    ((= tt "has")
      (setq ok nil)
      (foreach w (nth 2 c) (if (vl-string-search w (strcase v)) (setq ok T)))
      ok)
    ((= tt "range")
      (if (= v "")
        nil
        (progn
          (setq num (AS4:safe-atof v))
          (and (or (not (car (nth 2 c))) (>= num (car (nth 2 c))))
               (or (not (cadr (nth 2 c))) (<= num (cadr (nth 2 c))))))))
  )
)

;; -> (matching-row-count layer-names)
(defun AS4:tbl-filter-result (tb rl crit / rows ri row ok c names e)
  (setq rows 0 names '() ri 0)
  (foreach row (nth 1 tb)
    (setq ok T)
    (foreach c crit (if (not (AS4:tbl-crit-ok row c)) (setq ok nil)))
    (if ok
      (progn
        (setq rows (1+ rows))
        (setq e (assoc ri rl))
        (if e (setq names (append names (cdr e))))))
    (setq ri (1+ ri))
  )
  (list rows names)
)

(defun AS4:tbl-filter (links / link tb prof rl crit r res act done names i c)
  (setq link (AS4:tbl-pick-link links))
  (setq tb (if link (AS4:tbl-open link) nil))
  (if tb
    (progn
      (setq prof (AS4:tbl-profile (nth 0 tb) (nth 1 tb)) rl (AS4:tbl-rowlayers link tb) crit '() r nil)
      (princ "\nColumns available for filtering (number, name, rows filled, type, example values):")
      (AS4:tbl-columns-print tb)
      (princ "\n\nPick one column after the other: every criterion narrows the result (all criteria must match). Enter finishes.")
      (while (not (eq r 'DONE))
        (setq r (AS4:tbl-ask-crit link tb prof (length crit)))
        (if (and r (listp r))
          (progn
            (setq crit (append crit (list r)))
            (setq res (AS4:tbl-filter-result tb rl crit) i 0)
            (princ "\nCriteria so far (all must match):")
            (foreach c crit (setq i (1+ i)) (princ (strcat "\n  " (itoa i) "  " (AS4:tbl-crit-text prof c))))
            (princ (strcat "\n=> " (itoa (car res)) " row(s), " (itoa (length (cadr res))) " layer(s) match. Add another criterion to narrow further, or Enter to finish."))
          )
        )
      )
      (if (not crit)
        (princ "\nNo criteria - cancelled.")
        (progn
          (setq res (AS4:tbl-filter-result tb rl crit) names (cadr res) done nil)
          (princ (strcat "\nFilter finished: " (itoa (length crit)) " criteria, " (itoa (car res)) " row(s), " (itoa (length names)) " layer(s)."))
          (while (not done)
            (initget "Select Zoom Isolate Offlayers Back eXit S Z I O B X")
            (setq act (getkword (strcat "\nWhat to do with the " (itoa (length names)) " layer(s) [Select/Zoom/Isolate/Offlayers/Back/eXit] <eXit>: ")))
            (if (not act) (setq act "eXit"))
            (cond
              ((member act (list "Select" "S")) (AS4:tbl-select-layers names nil))
              ((member act (list "Zoom" "Z")) (AS4:tbl-select-layers names T))
              ((member act (list "Isolate" "I"))
                (if (not names)
                  (princ "\nNo layers match.")
                  (if (not (AS4:tbl-isolate-objects names))
                    (progn
                      (princ "\nISOLATEOBJECTS is not available here - switching the other layers off instead.")
                      (AS4:tbl-isolate-layers names)))))
              ((member act (list "Offlayers" "O"))
                (if (not names) (princ "\nNo layers match.") (AS4:tbl-isolate-layers names)))
              ((member act (list "Back" "B")) (AS4:tbl-restore))
              ((member act (list "eXit" "X")) (setq done T))
            )
          )
        )
      )
    )
  )
)

;; ---- RGB-via-column: color the layers with the colors stored in a table column ---------------
;; every column whose cells are all colors (r,g,b / #RRGGBB / 0xRRGGBB ...)
;; is offered; the layer of each table row takes the color of that row,
;; an empty cell = white. Back restores the original colors.
(defun AS4:tbl-rgb (links / link tb prof rl cols c ans ms cn row tc ops e nm seen s n)
  (setq link (AS4:tbl-pick-link links))
  (setq tb (if link (AS4:tbl-open link) nil))
  (if tb
    (progn
      (setq prof (AS4:tbl-profile (nth 0 tb) (nth 1 tb)) cols '())
      (foreach c prof (if (= (nth 4 c) "color") (setq cols (cons c cols))))
      (setq cols (reverse cols))
      (if (not cols)
        (princ "\nNo column in this table holds color values (r,g,b / #RRGGBB / 0xRRGGBB).")
        (progn
          (setq rl (AS4:tbl-rowlayers link tb) cn nil)
          (princ "\nColumns that hold colors (number, name, rows filled, example):")
          (foreach c cols
            (princ (strcat "\n  " (AS4:tbl-pad (itoa (1+ (nth 0 c))) 4) (AS4:tbl-pad (nth 1 c) 36)
                           (AS4:tbl-pad (itoa (nth 2 c)) 5) (AS4:tbl-oneline (car (nth 6 c)) 30))))
          (while (not cn)
            (setq ans (getstring T "\nColor by column - number or part of its name (Enter = cancel): "))
            (cond
              ((= ans "") (setq cn -1))
              ((and (AS4:tbl-numeric-p ans) (= (nth 4 (if (and (>= (atoi ans) 1) (<= (atoi ans) (length prof))) (nth (1- (atoi ans)) prof) '(0 "" 0 0 ""))) "color"))
                (setq cn (1- (atoi ans))))
              (T
                (setq ms '())
                (foreach c cols (if (vl-string-search (strcase ans) (strcase (nth 1 c))) (setq ms (cons (nth 0 c) ms))))
                (cond
                  ((= (length ms) 1) (setq cn (car ms)))
                  ((> (length ms) 1) (princ "\nSeveral columns match - enter the number."))
                  (T (princ "\nNo such color column."))
                )
              )
            )
          )
          (if (>= cn 0)
            (progn
              (setq ops '() seen '() n 0)
              (foreach e rl
                (setq row (nth (car e) (nth 1 tb)) s (AS4:tbl-cell row cn))
                (setq tc (if (= s "") 16777215 (AS4:tbl-parse-rgb s)))
                (setq s (if (= s "") "(empty) = white" s))
                (if (not (assoc s seen)) (setq seen (append seen (list (cons s 0)))))
                (setq seen (subst (cons s (1+ (cdr (assoc s seen)))) (assoc s seen) seen))
                (foreach nm (cdr e) (setq ops (cons (list nm 7 nil tc) ops) n (1+ n)))
              )
              (AS4:tbl-layer-apply2 ops nil)
              (princ (strcat "\nColors from column \"" (nth 1 (nth cn prof)) "\":"))
              (foreach c seen (princ (strcat "\n  " (AS4:tbl-pad (car c) 20) (itoa (cdr c)) " table row(s)")))
              (princ (strcat "\nColored " (itoa n) " layer(s) (Back restores the original colors)."))
            )
          )
        )
      )
    )
  )
)

;; ---- Name: rename layers from the table -------------------------------------------------------
;; splits a rename template into (separator parts). Text between two
;; asterisks is fixed text and may itself contain separators: *my test*_2_6
(defun AS4:tbl-name-parse (tpl / i n ch inq sep tok toks)
  (setq tpl (AS4:tbl-strip-braces tpl) n (strlen tpl) i 1 inq nil sep nil)
  (while (<= i n)
    (setq ch (substr tpl i 1))
    (cond
      (inq (if (= ch "*") (setq inq nil)))
      ((and (= ch "*") (vl-string-search "*" tpl i)) (setq inq T))
      ((and (not sep) (vl-string-search ch "_-. /|:;")) (setq sep ch))
    )
    (setq i (1+ i))
  )
  (setq i 1 inq nil tok "" toks '())
  (while (<= i n)
    (setq ch (substr tpl i 1))
    (cond
      (inq (setq tok (strcat tok ch)) (if (= ch "*") (setq inq nil)))
      ((and (= ch "*") (vl-string-search "*" tpl i)) (setq inq T tok (strcat tok ch)))
      ((and sep (= ch sep)) (setq toks (cons tok toks) tok ""))
      (T (setq tok (strcat tok ch)))
    )
    (setq i (1+ i))
  )
  (list sep (reverse (cons tok toks)))
)

;; fixed text of a *text* part, or nil
(defun AS4:tbl-quoted (p)
  (if (and (>= (strlen p) 3) (= (substr p 1 1) "*") (= (substr p (strlen p) 1) "*"))
    (substr p 2 (- (strlen p) 2))
    nil)
)

;; expands a name template for one layer. The template is a list of parts
;; separated by one separator character (default: the layer name's own):
;;   7      = value of table column 7 (numbers as shown by Columns)
;;   L2     = 2nd part of the old layer name
;;   *text* = fixed text (may contain separators), also =text, and any
;;            other word is taken literally, too
;; e.g. L1_L2_7_9 -> old parts 1 and 2, then columns 7 and 9, joined with _.
;; Returns nil if a part cannot be filled (e.g. the table cell is empty).
(defun AS4:tbl-expand (tpl old sep row / tsep toks old-toks out p v num ok first pr)
  (setq pr (AS4:tbl-name-parse tpl) tsep (car pr) toks (cadr pr))
  (if (not tsep) (setq tsep sep))
  (setq old-toks (AS4:split old sep) out "" ok T first T)
  (foreach p toks
    (cond
      ((not ok))
      ((AS4:tbl-quoted p) (setq v (AS4:tbl-quoted p)))
      ((and (> (strlen p) 0) (= (substr p 1 1) "=")) (setq v (substr p 2)))
      ((and (> (strlen p) 1) (= (strcase (substr p 1 1)) "L") (AS4:is-integer-str (substr p 2)))
        (setq num (atoi (substr p 2)) v (if (>= num 1) (nth (1- num) old-toks) nil))
        (if (not v) (setq ok nil)))
      ((AS4:is-integer-str p)
        (setq num (atoi p) v (if (>= num 1) (nth (1- num) row) nil))
        (if (not (and v (> (strlen v) 0))) (setq ok nil)))
      (T (setq v p))
    )
    (if ok
      (progn
        (setq out (if first v (strcat out tsep v)) first nil))))
  (if ok out nil)
)

;; replaces characters that are not allowed in layer names
(defun AS4:tbl-clean-name (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (setq out (strcat out (if (vl-string-search ch "<>/\\\":;?*|,=`") "-" ch)))
    (setq i (1+ i))
  )
  (AS4:trim out)
)

;; moves every object (all layouts) from one layer to another; returns the count
(defun AS4:tbl-move-layer (from to / ss i e d n)
  (setq ss (ssget "X" (list (cons 8 (AS4:wc-escape from)))) n 0)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i) d (entget e))
        (if (not (vl-catch-all-error-p (vl-catch-all-apply 'entmod (list (subst (cons 8 to) (assoc 8 d) d)))))
          (setq n (1+ n)))
        (setq i (1+ i))
      )
    )
  )
  n
)

(defun AS4:tbl-rename-layer (old new)
  (vl-catch-all-apply '(lambda () (command "_.-RENAME" "_LA" old new)))
  (and (tblsearch "LAYER" new) (not (tblsearch "LAYER" old)))
)

;; singles = list of (old new); groups = list of (new (old1 old2 ...) target-exists)
;; a group is several layers that get the same new name: they are merged
;; (one is renamed, or all are moved into the already existing layer; the
;; emptied layers are purged if nothing else uses them)
(defun AS4:tbl-name-apply (singles groups extra / logpath f p g ok fail merged gone left cmdecho rest tgt m x)
  (setq logpath (strcat (getvar "DWGPREFIX") "as4cad_layerrename_" (vl-string-subst "" "." (rtos (getvar "CDATE") 2 6)) ".csv"))
  (setq f (open logpath "w"))
  (if f
    (progn
      (write-line "old,new,action" f)
      (foreach p singles (write-line (strcat (AS4:tbl-q (car p)) "," (AS4:tbl-q (cadr p)) ",\"rename\"") f))
      (foreach g groups
        (foreach m (cadr g)
          (write-line (strcat (AS4:tbl-q m) "," (AS4:tbl-q (car g)) ",\"merge\"") f)))
      (foreach x extra (write-line x f))
      (close f)
      (princ (strcat "\nLog written (Name > Revert undoes the renames, not the merges): " logpath))
    )
    (princ "\nWarning: the log file could not be written.")
  )
  (setq cmdecho (getvar "CMDECHO") ok 0 fail 0 merged 0 gone 0 left 0)
  (setvar "CMDECHO" 0)
  (foreach p singles
    (if (AS4:tbl-rename-layer (car p) (cadr p)) (setq ok (1+ ok)) (setq fail (1+ fail))))
  (foreach g groups
    (setq tgt (car g) rest (cadr g))
    (if (not (tblsearch "LAYER" tgt))
      (if (AS4:tbl-rename-layer (car rest) tgt)
        (setq ok (1+ ok) rest (cdr rest))
        (setq fail (1+ fail) rest nil)))
    (foreach m rest
      (setq merged (+ merged (AS4:tbl-move-layer m tgt)))
      (vl-catch-all-apply '(lambda () (command "_.-PURGE" "_LA" (AS4:wc-escape m) "_N")))
      (if (tblsearch "LAYER" m) (setq left (1+ left)) (setq gone (1+ gone))))
  )
  (setvar "CMDECHO" cmdecho)
  (princ (strcat "\n" (itoa ok) " layer(s) renamed"
                 (if (> fail 0) (strcat ", " (itoa fail) " could not be renamed") "")
                 (if (> (+ gone left) 0) (strcat "; merged " (itoa (+ gone left)) " layer(s) into others (" (itoa merged) " object(s) moved)") "")
                 (if (> left 0) (strcat "; " (itoa left) " emptied layer(s) could not be deleted - remove them with PURGE") "")
                 "."))
  (list ok fail)
)

;; After Rename the layer names have a new structure, so the link's layer
;; template must follow - otherwise no layer would be found for a table
;; row any more. Builds the template that fits the names produced by the
;; rename template tpl (ID stays ID, Ln takes the n-th part of the old
;; template, other columns and fixed text become *). Returns a new link
;; (path key-column layer-template table-template) or nil.
(defun AS4:tbl-derive-link (link tb tpl / tsep toks oldl oldsep oldtoks ttpl kcol out p num k vals row ok pr q)
  (setq oldl (nth 2 link) ttpl (nth 3 link) kcol (1+ (nth 2 tb)))
  (setq pr (AS4:tbl-name-parse tpl) tsep (car pr) toks (cadr pr))
  (setq oldsep (AS4:tbl-tpl-sep oldl))
  (setq oldtoks (cond ((= oldl "") nil) (oldsep (AS4:split oldl oldsep)) (T (list oldl))))
  (cond
    ((and (= (length toks) 1) (AS4:is-integer-str (car toks)))
      (setq num (atoi (car toks)))
      (cond
        ((= num kcol) (list (nth 0 link) (nth 1 link) ttpl ttpl))
        ((and (>= num 1) (<= num (length (nth 0 tb))))
          ;; the names are now the values of another column: it becomes the key column
          (setq vals '() ok T)
          (foreach row (nth 1 tb)
            (setq k (AS4:tbl-cell row (1- num)))
            (if (= k "") (setq ok nil) (setq vals (cons k vals))))
          (if (and ok vals (AS4:tbl-all-unique vals))
            (list (nth 0 link) (nth (1- num) (nth 0 tb)) "" "")
            nil))
        (T nil))
    )
    (T
      (setq out '())
      (foreach p toks
        (setq out
          (cons
            (cond
              ((setq q (AS4:tbl-quoted p))
                ;; fixed text: as many * as the text has parts
                (AS4:tbl-join (mapcar '(lambda (x) "*") (if tsep (AS4:split q tsep) (list q))) (if tsep tsep "_")))
              ((and (> (strlen p) 1) (= (strcase (substr p 1 1)) "L") (AS4:is-integer-str (substr p 2)))
                (setq num (atoi (substr p 2)))
                (if (and (>= num 1) (<= num (length oldtoks))) (nth (1- num) oldtoks) "*"))
              ((and (AS4:is-integer-str p) (= (atoi p) kcol))
                (if (= ttpl "") "ID" ttpl))
              (T "*"))
            out)))
      (list (nth 0 link) (nth 1 link) (AS4:tbl-join (reverse out) (if tsep tsep "_")) ttpl)
    )
  )
)

;; how many of the names do NOT find their table row with the (new) link
(defun AS4:tbl-names-misfit (newlink names / tb2 n nm k)
  (setq tb2 (AS4:tbl-open newlink) n 0)
  (if (not tb2)
    (length names)
    (progn
      (foreach nm names
        (setq k (AS4:tbl-extract-key nm (nth 2 newlink)))
        (if (not (and k (assoc k (nth 3 tb2)))) (setq n (1+ n))))
      n
    )
  )
)

;; replaces one stored link by another; T if the old one was found
(defun AS4:tbl-link-replace (oldl newl / out l done)
  (setq out '() done nil)
  (foreach l (AS4:tbl-links-load)
    (if (and (not done) (equal l oldl))
      (setq out (cons newl out) done T)
      (setq out (cons l out))))
  (if done (AS4:tbl-links-save (reverse out)))
  done
)

;; log line that lets Revert restore the link
(defun AS4:tbl-link-logrow (oldl newl)
  (strcat (AS4:tbl-q (nth 0 oldl)) "," (AS4:tbl-q (nth 1 oldl)) ",\"link\","
          (AS4:tbl-q (nth 2 oldl)) "," (AS4:tbl-q (nth 3 oldl)) ","
          (AS4:tbl-q (nth 1 newl)) "," (AS4:tbl-q (nth 2 newl)) "," (AS4:tbl-q (nth 3 newl)))
)

;; Which table column do the layer names look like? (whole layer name = cell
;; value). -> (column-index number-of-layers) of the best column, or nil.
(defun AS4:tbl-detect-key (tb / keys i n best bestn cells row k m)
  (setq keys (mapcar 'AS4:tbl-norm-key (AS4:tbl-layers)) best nil bestn 0 i 0 m (length (nth 0 tb)))
  (while (< i m)
    (setq cells '())
    (foreach row (nth 1 tb)
      (setq k (AS4:tbl-cell row i))
      (if (> (strlen k) 0) (setq cells (cons (AS4:tbl-norm-key k) cells))))
    (setq n 0)
    (foreach k keys (if (member k cells) (setq n (1+ n))))
    (if (> n bestn) (setq best i bestn n))
    (setq i (1+ i))
  )
  (if best (list best bestn) nil)
)

;; the link finds (almost) no layers: show what the layer names look like and
;; let the user give the layer template right here; returns the (new) link
(defun AS4:tbl-fix-template (link tb / names ans newlink rl m done e)
  (setq names (AS4:tbl-layers) done nil)
  (princ "\nLayer names in the drawing (first ones):")
  (princ (strcat "\n  " (AS4:tbl-join (AS4:tbl-firstn names 8) ", ")))
  (princ (strcat "\nCurrent layer template of the link: " (AS4:tbl-tplshow (nth 2 link)) "  (key column " (nth 1 link) ")"))
  (while (not done)
    (setq ans (getstring T "\nLayer name template for this link (e.g. ID_ID_*_*, - = whole name, Enter = keep): "))
    (if (= ans "")
      (setq done T)
      (progn
        (setq ans (if (= ans "-") "" (AS4:tbl-strip-braces ans)))
        (setq newlink (list (nth 0 link) (nth 1 link) ans (nth 3 link)))
        (setq rl (AS4:tbl-rowlayers newlink tb) m 0)
        (foreach e rl (setq m (+ m (length (cdr e)))))
        (princ (strcat "\n" (itoa m) " layer(s) find their table row with this template."))
        (if (> m 0)
          (progn
            (initget "Yes No")
            (if (/= (getkword "\nKeep this template for the link? [Yes/No] <Yes>: ") "No")
              (progn (AS4:tbl-link-replace link newlink) (setq link newlink done T)))))
      )
    )
  )
  link
)

(defun AS4:tbl-tplshow (x)
  (if (= x "") "(whole name)" x)
)

(defun AS4:tbl-name (links / link tb rl sep ans tpl kidx kind pairs singles groups unchanged bad e row new old c yn recs r done key members ex c2 allnew newlink mis res lrows x det matched total)
  (initget "Rename reVert")
  (setq kind (getkword "\nLayer names [Rename/reVert] <Rename>: "))
  (if (not kind) (setq kind "Rename"))
  (cond
    ((member kind (list "reVert" "Revert" "V"))
      (setq ans (getfiled "Select a rename log" (getvar "DWGPREFIX") "csv" 4))
      (if ans
        (progn
          (setq recs (AS4:tbl-read-records ans) pairs '() lrows '())
          (foreach r (cdr recs)
            (if (= (nth 2 r) "link") (setq lrows (cons r lrows))))
          (foreach r (cdr recs)
            (if (and (nth 0 r) (nth 1 r) (not (member (nth 2 r) '("merge" "link")))
                     (tblsearch "LAYER" (nth 1 r)) (not (tblsearch "LAYER" (nth 0 r))))
              (setq pairs (cons (list (nth 1 r) (nth 0 r)) pairs))))
          (if pairs
            (progn
              (setq pairs (reverse pairs))
              (AS4:tbl-print-list "Revert (current name -> name before)" (mapcar '(lambda (c) (strcat (car c) " -> " (cadr c))) pairs) 40)
              (initget "No Yes")
              (setq yn (getkword (strcat "\nRevert " (itoa (length pairs)) " layer name(s)? [No/Yes] <No>: ")))
              (if (/= yn "Yes")
                (princ "\nNothing changed.")
                (progn
              (setq res (AS4:tbl-name-apply pairs nil nil))
              (if (and lrows (= (cadr res) 0))
                (foreach r lrows
                  (while (< (length r) 8) (setq r (append r (list ""))))
                  (setq r (mapcar '(lambda (x) (if x x "")) r))
                  (if (AS4:tbl-link-replace (list (nth 0 r) (nth 5 r) (nth 6 r) (nth 7 r))
                                            (list (nth 0 r) (nth 1 r) (nth 3 r) (nth 4 r)))
                    (princ (strcat "\nLink restored: layer template " (AS4:tbl-tplshow (nth 3 r)) " (key column " (nth 1 r) ")."))))
              )
                ))
            )
            (princ "\nNothing to revert (the new names no longer exist, or the old names are taken)."))
        )
      )
    )
    (T
      (setq link (AS4:tbl-pick-link links))
      (setq tb (if link (AS4:tbl-open link) nil))
      (if tb
        (progn
          (setq rl (AS4:tbl-rowlayers link tb))
          (setq total (length (AS4:tbl-layers)) matched 0)
          (foreach e rl (setq matched (+ matched (length (cdr e)))))
          (princ (strcat "\n" (itoa matched) " of " (itoa total) " layers belong to table rows via the current link."))
          ;; layer names that no longer fit the link (renamed elsewhere, link made before) -> offer a better one
          (if (< (* 2 matched) total)
            (progn
              (setq det (AS4:tbl-detect-key tb))
              (if (and det (>= (cadr det) 2) (> (cadr det) matched))
                (progn
                  (initget "No Yes")
                  (setq yn (getkword (strcat "\nMost layer names look like values of column \"" (nth (car det) (nth 0 tb)) "\" (" (itoa (cadr det)) " layers). Use that column as key with the whole layer name for this link? [No/Yes] <No>: ")))
                  (if (= yn "Yes")
                    (progn
                      (setq newlink (list (nth 0 link) (nth (car det) (nth 0 tb)) "" ""))
                      (AS4:tbl-link-replace link newlink)
                      (setq link newlink tb (AS4:tbl-open link) rl (AS4:tbl-rowlayers link tb))
                      (princ "\nLink updated.")))
                )
              )
            )
          )
          (setq matched 0)
          (foreach e rl (setq matched (+ matched (length (cdr e)))))
          (if (< (* 2 matched) total)
            (setq link (AS4:tbl-fix-template link tb) rl (AS4:tbl-rowlayers link tb)))
          (setq sep (AS4:tbl-tpl-sep (nth 2 link)))
          (if (not sep) (setq sep "_"))
          (setq kidx (nth 2 tb) tpl nil)
          (princ "\nColumns of the table (number, name, ...):")
          (AS4:tbl-columns-print tb)
          (while (not tpl)
            (setq ans (getstring T (strcat "\nNew layer name: a column number, or parts joined with _ : a number = table column, L1 L2 ... = parts of the old name, *text* = fixed text"
                                           "\n  e.g. " (itoa (1+ kidx)) "  or  L1_L2_9  or  *test*_2_6   (L = list columns, Enter = key column) : ")))
            (cond
              ((= ans "") (setq tpl (itoa (1+ kidx))))
              ((= (strcase ans) "L") (AS4:tbl-columns link))
              ((AS4:is-integer-str ans) (setq tpl ans))
              (T (setq tpl ans))
            )
          )
          (setq pairs '() unchanged 0 bad '() allnew '())
          (foreach e rl
            (setq row (nth (car e) (nth 1 tb)))
            (foreach old (cdr e)
              (setq new (AS4:tbl-expand tpl old sep row))
              (if new (setq new (AS4:tbl-clean-name new)))
              (if (and new (/= new "")) (setq allnew (cons new allnew)))
              (cond
                ((or (not new) (= new "")) (setq bad (cons (strcat old "  (a placeholder is empty/unknown)") bad)))
                ((= (strcase new) (strcase old)) (setq unchanged (1+ unchanged)))
                (T (setq pairs (cons (list old new) pairs)))
              )
            )
          )
          (setq pairs (reverse pairs) singles '() groups '() done '())
          ;; layers that get the same new name (or a name that already exists) are merged
          (foreach c pairs
            (setq key (strcase (cadr c)))
            (if (not (member key done))
              (progn
                (setq done (cons key done) members '())
                (foreach c2 pairs (if (= (strcase (cadr c2)) key) (setq members (cons (car c2) members))))
                (setq members (reverse members) ex (if (tblsearch "LAYER" (cadr c)) T nil))
                (if (and (= (length members) 1) (not ex))
                  (setq singles (cons c singles))
                  (setq groups (cons (list (cadr c) members ex) groups)))
              )
            )
          )
          (setq singles (reverse singles) groups (reverse groups))
          (princ (strcat "\n" (itoa (length singles)) " layer(s) will be renamed, " (itoa unchanged) " already match."))
          (if singles (AS4:tbl-print-list "Rename (old -> new)" (mapcar '(lambda (c) (strcat (car c) " -> " (cadr c))) singles) 40))
          (if groups
            (AS4:tbl-print-list
              "Merge (several layers -> one layer; objects are moved, emptied layers deleted, merging cannot be reverted)"
              (mapcar '(lambda (g) (strcat (AS4:tbl-join (cadr g) ", ") " -> " (car g) (if (nth 2 g) "  (existing layer)" ""))) groups)
              25))
          (if bad (AS4:tbl-print-list "Skipped, new name could not be built" (reverse bad) 20))
          ;; the link has to follow the new naming, otherwise the table would find no layers
          (setq newlink nil)
          (if (and allnew (or singles groups))
            (progn
              (setq newlink (AS4:tbl-derive-link link tb tpl))
              (cond
                ((not newlink)
                  (princ "\nNote: the link cannot follow this naming - afterwards use Link again with a matching layer template."))
                ((equal newlink link) (setq newlink nil))
                ((> (setq mis (AS4:tbl-names-misfit newlink allnew)) 0)
                  (princ (strcat "\nNote: " (itoa mis) " of the new names would not find their table row with an adapted template - the link stays as it is, use Link again afterwards."))
                  (setq newlink nil))
                (T
                  (princ (strcat "\nThe link follows the rename: layer template " (AS4:tbl-tplshow (nth 2 link)) " -> " (AS4:tbl-tplshow (nth 2 newlink))
                                 (if (/= (nth 1 link) (nth 1 newlink)) (strcat ", key column " (nth 1 link) " -> " (nth 1 newlink)) "")
                                 " (Revert restores it).")))
              )
            )
          )
          (if (or singles groups)
            (progn
              (initget "No Yes")
              (setq yn (getkword (strcat "\nApply " (itoa (length singles)) " rename(s) and " (itoa (length groups)) " merge(s)? [No/Yes] <No>: ")))
              (if (= yn "Yes")
                (progn
                  (setq res (AS4:tbl-name-apply singles groups (if newlink (list (AS4:tbl-link-logrow link newlink)) nil)))
                  (if newlink
                    (if (= (cadr res) 0)
                      (if (AS4:tbl-link-replace link newlink)
                        (princ "\nLink updated - the table works with the new layer names."))
                      (princ "\nSome renames failed - the link was not changed; check the names and use Link again if needed.")))
                )
                (princ "\nNothing changed."))
            )
          )
        )
      )
    )
  )
)

(defun c:AS4TABLE ( / kw done links n i l x keep)
  (if (not (AS4:tbl-file))
    (princ "\nSave the drawing first - table links are stored next to it.")
    (progn
      (setq done nil)
      (while (not done)
        (initget "Link Report Columns Filter RGB-via-column Name Info Back Unlink eXit L R C F G N I B U X")
        (setq kw (getkword "\nAS4CAD table [Link/Report/Columns/Filter/RGB-via-column/Name/Info/Back/Unlink/eXit] <eXit>: "))
        (if (not kw) (setq kw "eXit"))
        (setq links (AS4:tbl-links-load))
        (cond
          ((member kw (list "Link" "L")) (AS4:tbl-link))
          ((member kw (list "eXit" "X")) (setq done T))
          ((member kw (list "Back" "B")) (AS4:tbl-restore))
          ((not links) (princ "\nNo table linked yet - use Link first."))
          ((member kw (list "Report" "R")) (foreach l links (AS4:tbl-report l T)))
          ((member kw (list "Columns" "C")) (foreach l links (AS4:tbl-columns l)))
          ((member kw (list "Filter" "F")) (AS4:tbl-filter links))
          ((member kw (list "RGB-via-column" "G")) (AS4:tbl-rgb links))
          ((member kw (list "Name" "N")) (AS4:tbl-name links))
          ((member kw (list "Info" "I")) (AS4:tbl-info links))
          ((member kw (list "Unlink" "U"))
            (setq i 1)
            (foreach l links (princ (strcat "\n  " (itoa i) "  " (car l) "  (key: " (cadr l) ")")) (setq i (1+ i)))
            (setq n (getint "\nNumber of the link to remove <cancel>: "))
            (if (and n (>= n 1) (<= n (length links)))
              (progn
                (setq i 0 keep '())
                (foreach x links (setq i (1+ i)) (if (/= i n) (setq keep (cons x keep))))
                (AS4:tbl-links-save (reverse keep))
                (princ "\nLink removed (the table file itself is untouched; the templates stay remembered for the next Link).")))
          )
        )
      )
    )
  )
  (princ)
)

;; =========================================================================
;; AS4INFO: lists every AS4CAD command with a letter, then prints a short
;; description for the letter entered. Uses getstring rather than
;; getkword/initget deliberately - AutoCAD has many single-letter command
;; ALIASES of its own (L=LINE, C=CIRCLE, M=MOVE, E=ERASE, A=ARC, ...), and
;; a getkword keyword list of bare letters A-Q would risk exactly the
;; same autocomplete-dropdown collision problem documented elsewhere in
;; this file for whole-word keywords - getstring has no such dropdown.
;; =========================================================================
(defun c:AS4INFO ( / cmds descs choice idx c)
  (setq cmds (list
    "AS4IMPORT" "AS4NET" "AS4SELECTLAYER" "AS4SELECTXDATA"
    "AS4SETTINGS" "AS4STATUS" "AS4TABLE" "AS4TAGFROMLAYER"
    "AS4XPORT" "AS4ZOOM"
  ))
  (setq descs (list
    "Reads an ArchSurv delimited text file and builds the classified drawing - point symbols, lines/polygons, posthole circles, all attributed. Usage: run it, select the text file, review the command-line summary."
    "The only entry point for the reference survey grid - a menu with 2 steps: Grid (draws crosses at round coordinates over a picked window) and Label (labels selected points with their X/Y coordinates). Usage: run it, type the first letter of the step you want (G/L), repeat as needed, X to exit."
    "Zooms to and selects every object, of any type, on a layer matching a wildcard pattern (* = any characters, ? = one character; comma-separated for several layers). Usage: run it, then click an object (its layer), press Enter (current layer), or type pattern(s) (e.g. *193* or *193*,AS4_*)."
    "Zooms to and selects every object belonging to one or several (comma-separated) feature IDs/codes, across all layers, via block attribute/Xdata - not layer name. Usage: run it, then click an object (its ID, or its code if it has no ID), press Enter (all AS4 objects on the current layer), or type ID(s)/code(s), comma-separated (e.g. 40 or 4,12,VF,FUND)."
    "The only entry point for configuration - a menu with 6 steps: Layerstructure, Vector, Symbol, Text, Export (defaults), Default (factory reset). Usage: run it, type the first letter of the step you want (L/V/S/T/E/D), repeat as needed, X to exit."
    "Prints the AS4CAD version and every current setting to the command line. Usage: just run it, no prompts."
    "Links an external table (e.g. a CSV exported from the excavation database; delimiter auto-detected) to the layers via an ID read out of the layer names; the file is re-read on every use, so overwriting it updates everything. A menu with 9 steps: Link (file, key column, layer-name template such as ID_ID_*_*; remembered for next time), Report (matching, optional CSV list), Columns (overview), Filter (several criteria, then Select/Zoom/Isolate = ISOLATEOBJECTS on the matching layers, or Offlayers = all other layers off), RGB-via-column (colors the layers with the color values stored in a table column, empty = white), Name (rename layers from table columns; layers that get the same name are merged; with preview, log and reVert), Info (click an object or type a key: shows the table row and its layers), Back (UNISOLATEOBJECTS, restore visibility and colors), Unlink. Usage: run it, type the first letter of the step (L/R/C/F/G/N/I/B/U), X to exit."
    "Bulk-scans lines/polygons with no AS4CAD attributes and derives ID/code from their layer name (e.g. lines traced over a photogrammetry mesh). Usage: run it, select objects or Enter for the whole drawing, review the summary, confirm."
    "The only entry point for exporting - a menu with 2 steps: Csv (point symbols, Raw or full Schema) and GeoJson (points and lines/polygons together, geometry and attributes in one; optionally mirrors polygons as an additional polyline feature, like AS4QGIS's own mirror option). Usage: run it, type the first letter of the step you want (C/G), repeat as needed, X to exit."
    "Zooms to every object matching a search term, without selecting them - a term containing * or ? is matched as a layer name pattern (any entity type); anything else as a feature ID or code (block attribute/Xdata). Usage: run it, then click an object (its ID/code, or its layer if it has none), press Enter (current layer), or type ID(s)/code(s) (e.g. 40, VF) or layer pattern(s) with * or ? (e.g. *193*)."
  ))

  (princ "\nAS4CAD Commands:")
  (setq idx 0)
  (foreach c cmds
    (princ (strcat "\n" (chr (+ 65 idx)) " - " c))
    (setq idx (1+ idx))
  )

  (setq choice (getstring "\nEnter a letter for details: "))
  (setq choice (if choice (strcase choice) ""))
  (if (and (= (strlen choice) 1) (>= (ascii choice) 65) (< (ascii choice) (+ 65 (length cmds))))
    (progn
      (setq idx (- (ascii choice) 65))
      (princ (strcat "\n" (nth idx cmds) ": " (nth idx descs)))
    )
    (princ "\nNo command selected.")
  )
  (princ)
)

(princ (strcat "\nAS4CAD v" *AS4:VERSION* " loaded. Commands: AS4IMPORT, AS4NET, AS4SELECTLAYER, AS4SELECTXDATA, AS4SETTINGS, AS4STATUS, AS4TABLE, AS4TAGFROMLAYER, AS4XPORT, AS4ZOOM, AS4INFO. Type AS4INFO for a full command list with descriptions."))
(princ)
