;;; ============================================================================
;;; AS4CAD.lsp
;;; ArchSurv4QGIS - CAD port of the Synthesis workflow (AutoLISP / FLISP)
;;; Version 1.3.4
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
;;;   AS4ZOOM           - zooms to every object belonging to a given
;;;                       feature ID or code (e.g. "40" or "VF"; auto-
;;;                       detected - plain integers are IDs, anything
;;;                       else is matched as a code, case-insensitive),
;;;                       regardless of which layer they are on (matched
;;;                       via block attribute/Xdata, not by reconstructing
;;;                       a layer name)
;;;   AS4SELECT         - like AS4ZOOM, but also selects the found
;;;                       objects; accepts one or several comma-
;;;                       separated IDs/codes at once (e.g. "40" or
;;;                       "4,12,VF,FUND")
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
(setq *AS4:VERSION* "1.3.4")
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
(defun AS4:ensure-block (name entities)
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
(defun AS4:insert-symbol-labeled (blockname pt symlayer txtlayer labeltext colorgroup colorval height pid extra / ins)
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
(defun AS4:insert-symbol-labeled-centered (blockname pt symlayer txtlayer labeltext colorgroup colorval height gap pid extra / ins pos)
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
                        runlist runcount runidx run splitlog symlayer)

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
                  xv   (atof (nth 1 parts))
                  yv   (atof (nth 2 parts))
                  zv   (atof (nth 3 parts))
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
;; AS4ZOOM / AS4SELECT: locate objects by feature ID,
;; independent of layer naming/configuration (AS4SETLAYER's chosen field
;; and A/B/C/D placement mode change what a feature's layer is called, so
;; matching by layer name would be fragile). Instead, every entity in the
;; drawing is checked directly for its own ID - block attribute "ID" for
;; point symbols, Xdata "ID" for line/polygon POLYLINE headers - and the
;; view zooms to the combined bounding box of whatever matches.
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
;; for a full (empty) attribute walk on every AS4ZOOM/AS4SELECT search.
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
(defun AS4:find-by-criteria (idlist codelist / ss i ent idc id code bbox found etype)
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
;; lines/polygons (POLYLINE) - diagnostic breakdown for AS4ZOOM/AS4SELECT
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

(defun c:AS4ZOOM ( / instr crit result bbox)
  (setq instr (getstring "\nFeature ID or code to zoom to (e.g. 40 or VF): "))
  (if (or (not instr) (= (strlen instr) 0))
    (princ "\nCancelled.")
    (progn
      (setq crit (AS4:parse-criteria instr))
      (setq result (AS4:find-by-criteria (car crit) (cadr crit)))
      (setq bbox (cadr result))
      (if (not bbox)
        (princ (strcat "\nNo objects found for \"" instr "\"."))
        (progn
          (AS4:zoom-to-bbox bbox)
          (princ (strcat "\nZoomed to " (itoa (length (car result))) " object(s) for \"" instr
                         "\" (" (AS4:count-by-type (car result)) ")."))
        )
      )
    )
  )
  (princ)
)

(defun c:AS4SELECT ( / instr crit idlist codelist result found bbox ss2 e)
  (setq instr (getstring "\nFeature ID(s)/code(s) to select - one, or several comma-separated (e.g. 40, or 4,12,VF,FUND): "))
  (if (or (not instr) (= (strlen instr) 0))
    (princ "\nCancelled.")
    (progn
      (setq crit (AS4:parse-criteria instr))
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
  (if (and s (> (strlen s) 0)) (atof s) nil)
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
                    rows rowdata kind mx mn shptype geomtype pts ring
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
;; AS4INFO: lists every AS4CAD command with a letter, then prints a short
;; description for the letter entered. Uses getstring rather than
;; getkword/initget deliberately - AutoCAD has many single-letter command
;; ALIASES of its own (L=LINE, C=CIRCLE, M=MOVE, E=ERASE, A=ARC, ...), and
;; a getkword keyword list of bare letters A-Q would risk exactly the
;; same autocomplete-dropdown collision problem documented elsewhere in
;; this file for whole-word keywords - getstring has no such dropdown.
;; =========================================================================
(defun c:AS4INFO ( / cmds descs choice idx)
  (setq cmds (list
    "AS4IMPORT" "AS4NET" "AS4SELECT"
    "AS4SETTINGS" "AS4STATUS" "AS4TAGFROMLAYER"
    "AS4XPORT" "AS4ZOOM"
  ))
  (setq descs (list
    "Reads an ArchSurv delimited text file and builds the classified drawing - point symbols, lines/polygons, posthole circles, all attributed. Usage: run it, select the text file, review the command-line summary."
    "The only entry point for the reference survey grid - a menu with 2 steps: Grid (draws crosses at round coordinates over a picked window) and Label (labels selected points with their X/Y coordinates). Usage: run it, type the first letter of the step you want (G/L), repeat as needed, X to exit."
    "Zooms to and selects every object belonging to one or several (comma-separated) feature IDs/codes, across all layers. Usage: run it, type an ID (e.g. 40), a code (e.g. VF), or several separated by commas (e.g. 4,12,VF,FUND)."
    "The only entry point for configuration - a menu with 6 steps: Layerstructure, Vector, Symbol, Text, Export (defaults), Default (factory reset). Usage: run it, type the first letter of the step you want (L/V/S/T/E/D), repeat as needed, X to exit."
    "Prints the AS4CAD version and every current setting to the command line. Usage: just run it, no prompts."
    "Bulk-scans lines/polygons with no AS4CAD attributes and derives ID/code from their layer name (e.g. lines traced over a photogrammetry mesh). Usage: run it, select objects or Enter for the whole drawing, review the summary, confirm."
    "The only entry point for exporting - a menu with 2 steps: Csv (point symbols, Raw or full Schema) and GeoJson (points and lines/polygons together, geometry and attributes in one; optionally mirrors polygons as an additional polyline feature, like AS4QGIS's own mirror option). Usage: run it, type the first letter of the step you want (C/G), repeat as needed, X to exit."
    "Zooms to every object belonging to a given feature ID or code, without selecting them. Usage: run it, type an ID (e.g. 40) or a code (e.g. VF)."
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


(princ (strcat "\nAS4CAD v" *AS4:VERSION* " loaded. Commands: AS4IMPORT, AS4NET, AS4SELECT, AS4SETTINGS, AS4STATUS, AS4TAGFROMLAYER, AS4XPORT, AS4ZOOM, AS4INFO. Type AS4INFO for a full command list with descriptions."))
(princ)
