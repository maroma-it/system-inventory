# TODO

## Active

(none — plans/01–03 executed 2026-07-02, see Done below. The plan documents were
removed 2026-07-16 in the markdown consolidation; recover them from git history
if the design detail is ever needed.)

## Candidates

- **Preset layout strands unpositioned nodes at the origin.** `explorer_template.html` runs the
  `preset` layout whenever `manual/explorer_layout.json` exists, but `socal-whp`'s file names only 10 of
  140 nodes; the other 131 (86 grids, 43 workflows) render stacked at (0,0). Fix: run preset for
  positioned nodes, then a second layout for the rest — or nest grids as compound children and position
  only top-level forms. Evidence in `reviews/2026-09-03-explorer-ui-review/`.
- **The global explorer draws no edges.** `global_template.html` builds workspace and form nodes only;
  no edge elements are ever created, though the stylesheet defines `dup-edge` and CLAUDE.md, README.md,
  and the landing page all describe "duplicate form names linked across clusters". Compounding it, the
  graph excludes Subforms while the collision sidebar includes them, so 24 of 27 collisions point at
  nodes that do not exist and clicking them highlights nothing. Either draw the links for on-graph forms
  or drop the canvas and make the sidebar tables the view.
- **Subforms dominate the graph.** 259 of 314 forms are Subforms whose only edge is `(embedded grid)` to
  a parent, so a force-directed layout spends most of its pixels on rows that carry no linkage
  information. Collapsing grids into their parent by default would remove ~85% of nodes without losing
  anything the panel does not already show.
- **`Featured` has lost its meaning.** No workspace ships a `manual/featured_forms.json`, so the
  `FEATURED_KEYWORDS` default applies and substring-matches the parent qualifier in grid names —
  41 featured forms in `liwp`, 40 in `socal-whp`, gold rings on grids, landing-page chips full of them.
  Restrict the default to non-Subform roles, or ship the manual files.
- **Duplicate-flow signatures are degenerate.** 90 of 120 workflows collapse into one
  `Update -> (no target)` bucket because email-only workflows have no target form; the sidebar section
  conveys nothing. The registry's pattern key already solves this.
- **Report literals should be checked against option sets.** `docs/field-index.json` already publishes
  the legal `Value` strings per field, and report expressions compare against them — but the views also
  still hold the older `Key` strings (see the 2026-09-03 Done entry). A checker that flags a literal
  matching neither side, or only one side, would catch the defects listed in
  `reviews/rxml-corpus-audit-2026-09-03.md` automatically. Natural home: `scripts/parse_rxml.py`, the
  not-yet-written decoder described in `xtrareports-reference.md` Part V.
- `expand_field_assignments.py` still rejects Assignment Type `Clear/Set Null`. It is the fourth
  button in the designer's field-assignment control, but no exported workflow anywhere in `data/`
  uses it, so its literal `ValueType` string is unknown and a row using it is a hard error naming the
  row rather than a guessed string. Unblock by building one assignment with it in the designer and
  exporting that workflow; then extend `TYPE_ALIASES`/`build_assignments` the way `Expression` was.
  (`Expression` itself is **done** — see Done below.)

- **Decode condition operator codes 6, 7, 12, and 16.** `parser._expr_to_text` maps only the two
  codes whose designer label has actually been read (`1` Is, `2` Is Not); every other code renders
  `?`. Operand arity narrows them — `9`/`10` are the membership pair (they populate
  `ResponseFieldValueList`), `12`/`16` are the blank pair (27 of 32 and 24 of 27 nodes carry no
  operand at all) — but nothing distinguishes *within* a pair, and getting `12`/`16` backwards would
  invert the meaning of 59 conditions. Resolve with one designer lookup each; the exact workflow and
  condition for all four are listed in `workflow-engine-reference.md` §3. Do not re-introduce a
  guessed mapping: the previous one assumed the enum followed the help text's list order, mapped four
  codes that appear nowhere in `data/`, and rendered code 6 as "is at least" on a Text field.
- Render record-metadata `Comparison` guards (LastModifierId vs user GUIDs) compactly
  instead of dropping them — e.g. one "(plus N system-user rules)" suffix. They're
  currently filtered out of condition text deliberately (14 GUID clauses drown the
  readable part, and their operator enum is unverified).
- **Model Condition and Switch nodes.** The designer's `+` offers Action, Condition (True/False
  branches), and Switch (field or custom expression, one branch per case, plus a default). No
  workflow in `data/` uses either yet, so the parser models only Actions and ignores
  `Steps[].OutgoingTransitions` entirely. The first branching workflow anyone builds will import
  fine and appear in the inventory as a flat action list with the branch structure silently dropped.
- **Parse trigger `Dependencies`.** A trigger can declare `{PrerequisiteRootDefinitionId,
  OnFailureBehavior}` with a `Type: "Workflow"` external reference — workflow-to-workflow sequencing.
  It is ignored today, so `narrate.build_workflow_conflicts` can flag a write race that a dependency
  has already resolved.
- **Cross-workspace action targets.** A workflow can write into a different workspace (LIWP's
  `Create System Tracker Record` targets "MAROMA Test"); such exports carry two `Type: "Workspace"`
  references. The inventory has no model for this and shows the target as dangling.
- Workflow version numbers (the designer's `v15 · Latest version`) are not carried in the export, so
  the version-history machinery that works for forms has nothing to key on for workflows.
- Snapshot blobs in git history turned out to be a non-issue: measured 2026-07-16,
  all superseded snapshot blobs together pack to ~4.6 MB (git compresses the
  repetitive JSON ~20:1), so a history rewrite was evaluated and **skipped** — not
  worth a force-push + fresh clones for that saving. Revisit only if `git
  count-objects -vH` size-pack grows materially; GitHub's >50 MB per-file push
  warning on new snapshots is about raw file size and is expected/harmless (hard
  limit is 100 MB).
## Done

**XtraReports reference + explorer UI review (2026-09-03).** Two audits landed under `reviews/`, and
the reporting track gained its own reference doc.

`xtrareports-reference.md` (docs tab "XtraReports") decodes the DevExpress XtraReports v25.2 `.rxml`
layout format from the vendor docs plus eleven real layouts: the envelope and document-global `Ref`
numbering, positional `ItemN` collections, bands, tables, cross-tabs, expression bindings, and the
Base64-encoded `SqlDataSource` blob (queries, SQL-level joins, master-detail relations, cached
`ResultSchema`). It also captures the expression language — operands, precedence, three-valued null
semantics, aggregate scoping — and 23 detectable failure patterns. Corpus facts worth carrying: every
`reporting.*` view column maps one-to-one onto a form field API name (so report columns can be resolved
against `docs/field-index.json` offline); totals are bare `Sum(Iif(...))` calculated fields rather than
`sum*` summary functions; and every date column the views expose is `Type="Unknown"` in the cached
schema, the `datetimeoffset` signature.

`reviews/rxml-corpus-audit-2026-09-03.md` records the per-report defects, the largest being a field
reference (`[Clone Project]`) that resolves to nothing across ~220 expressions in both bi-weekly
reports, twelve calculated fields bound to a nonexistent data member in both CARB exports, and — checked
against a 4,826-row export — the fact that the SQL views hold **both** the option `Key` and the option
`Value` for the same field over time (415 Submission Status: 181 rows `Bid Proposed`, 13 rows `Ready for
Review`). Conditions testing one string under-count. That refines the "the engine matches `Value`" rule
in `workflow-engine-reference.md`: true for new writes, not for stored history.

`reviews/2026-09-03-explorer-ui-review/` assesses whether the graph layer is the most efficient way to
read the system. Verdict: the side panel, briefs, and Excel are cohesive; the graph is not. Open items
it names — a preset-layout bug that stacks 131 unpositioned nodes at the origin in `socal-whp`, a global
explorer that builds no edge elements at all, degenerate duplicate-flow signatures, and a `Featured`
keyword default that matches 40+ subform grids — are carried into Candidates below.

`docs/reporting/` (the `.rxml` layouts and their customer-data exports) is **gitignored**: the files
embed the production connection string, and `docs/` is the GitHub Pages publish target.

**sdge-whp re-baselined; SDGE reporting pipeline documented (2026-09-03).**
`data/sdge-whp/` now carries a fresh whole-workspace export (46 forms / 26 workflows, up from 23). The
six 2026-06 per-form design overrides (400, 410, 415, 425, 499 Measures, Invoice) were diffed against
the new baseline first — every one was a strict subset with older formulas, so they were deleted per
the documented re-baseline reset; sdge-whp is baseline-only and rebuilds with zero warnings and zero
orphans. Snapshot compare (previous → latest) shows seven forms modified (415 alone gained 117
fields), three new "Marked for Deletion" workflows, and 18 workflow signature changes. Alongside,
`docs/reporting/SDGE-Reporting-Pipeline.md` (local, untracked — the folder also holds customer-data
exports) documents the DevExpress XtraReports → Production export → Whole-Home workbook pipeline: the
RXML runs five single-table SELECTs against `reporting.SDGE_Whole_Home_*` views with four
master-detail relations on Enrollment # (the Invoice relation is unused), every export column is
mapped to its platform field, the 400 form's Stage/Status/Reason/Path formulas are decoded, and nine
workbook defects are listed (two reason literals with a stray trailing period that never match, two
hard-coded Plus/Deep constants, a double-count in the Unable-to-Proceed block, a renamed-header
dependency in `pivot!C5`, two malformed `TextFormatString`s in the RXML, and the dead Invoice query).

**Platform semantics captured; option sets, operators, and Expression (2026-08-24).**
`workflow-engine-reference.md` was rewritten from a read-only schema note into a two-part reference —
Part I (reading an export) and Part II (authoring an importable one) — and wired into the docs viewer
as its own "Workflow Engine" tab, with a pointer from CLAUDE.md. Six individual workflow exports plus
direct designer observation settled a lot that had been guessed at: the whole-workspace export uses
**integer** enums while the individual (importable) export uses **strings**, and `Update Existing
Measures` existing in both forms pins the mapping exactly; `RefId`s are synthetic per-export
identifiers, not platform GUIDs; the action palette contains API Call and WebHook (so
`WorkflowVariables.*` is reachable, correcting an earlier conclusion) while Human Approval, Assign
User, and Generate Report do not exist at all; email recipient modes 2/3/5 are confirmed rather than
inferred; `Expression` and `calc()` are layered rather than competing; and target resolution is a
three-way choice by direction of travel (`FilterBuilder` forward, `RelationshipField` backward,
`TriggerRecord` same-record).

Four code changes followed. (1) **Option sets are extracted** from `ExtraProperties.DataSourceValues`
into `field["options"]`/`optionDefault` and published in `docs/field-index.json` as an additive
`options` key — 1,947 fields across 314 forms. Only the `Value` side is published: `Key` and `Value`
differ on some fields and every disambiguating comparison in the corpus matches `Value`, so
publishing `Key` would hand authors the string the engine will not match. (2) **The operator map was
de-guessed** — codes 3/4/5/6 were mapped on a false assumption about enum ordering, appear nowhere in
`data/`, and code 6 rendered "is at least" on a Text field; and the real bug was that
`_expr_to_text` read only the scalar `ResponseFieldValue`, so membership operators lost their entire
operand list. 36 conditions now render operands that were previously discarded. (3) **`Expression` is
supported** in `expand_field_assignments.py`, with `{{Token}}` references validated against the
trigger form (engine `@`-tokens pass through; unknown plain tokens warn rather than error).
(4) **`TriggerRecord` targets resolve** to the trigger form, so the three self-updating workflows name
a form instead of narrating "Updates a record" and contributing no edge. Also added blockquote
support to `md_render.py` (rendered recursively, so quoted tables and lists work). 56 tests.


**UI, security, and reliability hardening (2026-08-13).** Explorers now run fully
offline from vendored, pinned graph libraries; use responsive mobile detail sheets;
provide keyboard-accessible DOM node navigation; preserve workflow-type colors through
theme changes; synchronize reset/search/filter state; report clipboard failures; and
cap/index bulk field expansion. Public pages redact notification recipients and safely
encode source-derived HTML, inline arguments, preset data, titles, and brief links.
Launchers now validate selection input and align branch behavior. Parser failures warn
instead of disappearing or aborting discovery. Snapshot IDs are collision-resistant and
snapshot/manifest updates are locked and atomic. Discovery results are cached across the
full rebuild, removing repeated parsing. Added repository-wide sensitive-data scanning,
responsive/accessibility regression contracts, and exact dependency pins.

**FieldAssignments generator (2026-07-16).** New `scripts/expand_field_assignments.py`, sibling to
`expand_subform_ops.py`, mass-generates a WFEngine workflow's top-level `FieldAssignments` parameter
(the "copy field X from the trigger form to field Y on the target form" pattern, e.g. sce-be's "Update
Existing Measures" workflow) from an Excel mapping (`Field Name (Current Form)` / `Field Assignment
Type` / `Resolution (Field Name)` — the three-column format staff already use, read via `openpyxl`,
already a repo dependency). Same `docs/field-index.json` validation, same dry-run/`--apply` convention
as the subform generator. Deliberately scoped to `Constant`/`FromTrigger` only — real data in `data/`
confirms those two plus `TriggerRecordId`/`CurrentOrganization`/`CurrentUser` as the only `ValueType`s
ever exported, with **no precedent for `Expression` or `Clear/Set Null`** anywhere in the repo, so
rows using either are a hard error rather than a guessed platform string (tracked under Candidates).
Verified against a real sce-be workflow (210 -> 255 measure copy): generated output parses through the
existing `_parse_field_assignments` path unmodified (no parser changes needed — this shape was already
supported) and narrates correctly ("Updates the matching 255 - BE Installation Form record, filling in
two fields automatically."). 11 new unit tests.

**Docs viewer + markdown consolidation (2026-07-16).** The landing page gained a
"Project documentation" card: `emit_project_docs()` renders the repo's markdown files
(README, CLAUDE.md as "Architecture", TODO.md as "Changelog", NOTICE) into
`docs/docs.html` — one page, one tab per file, `#hash` deep links — using the new
`scripts/md_render.py`, a stdlib-only deterministic Markdown-to-HTML converter (no
client-side JS markdown library, consistent with the repo's zero-dependency HTML
generation). Regenerated on every rebuild like the other views. Consolidation: the
executed `plans/01–03` documents were deleted (their outcomes are the Done entries
below; git history keeps the full text), leaving four markdown files — README.md,
CLAUDE.md, TODO.md, NOTICE.md — each with a distinct audience. Also evaluated and
**skipped** the snapshot history rewrite floated earlier: measured, all superseded
snapshot blobs pack to ~4.6 MB total, not worth a force-push (see Candidates).

**Snapshot pruning (2026-07-16).** Snapshots grew to ~70 MB each once `data/` became
git-tracked (GitHub warned on push), so `versioning.prune_snapshots(keep)` now deletes old
unlabeled snapshots — file + manifest entry, keeping `latest`/`previous` refs consistent —
while **labeled snapshots are never pruned** (a label = a deliberately pinned baseline).
Full rebuilds auto-prune down to the newest `DEFAULT_KEEP` (5) after each auto-snapshot;
`--prune-snapshots [N]` runs it standalone. Pruned the repo from 10 snapshots (222 MB) to
5 (178 MB) at ship. Unit tests in `tests/test_versioning.py`. Note: pruning shrinks the
working tree only — blobs of previously-committed snapshots stay in git history (a
history rewrite would be needed to reclaim that, tracked under Candidates).

**SubformOperations generator + parsing (2026-07-16).** New `scripts/expand_subform_ops.py`
mass-expands a WFEngine workflow's `SubformOperations` parameter (the escaped
JSON-array-in-a-string on `BuiltIn.UpdateFormResponse` actions; one `"Add"` op per subform
row) from a CSV — the repo's first tool that *generates* platform JSON instead of parsing
it. Takes an exported workflow as the template (first existing op is the prototype; its
scaffold keys and GUIDs are cloned verbatim), validates every CSV header against the
subform's fields and every `FromTrigger` source against the trigger form's fields via
`docs/field-index.json` (fail-loud with closest-match suggestions), infers
FromTrigger/Constant per cell (`=`/`@` prefix overrides), and writes a full import-ready
`.expanded.json`. Dry-run by default, `--apply` to write. Verified against a real
hand-expanded liwp workflow: generated ops matched the manual edit exactly.

The parser also learned the parameter: `_parse_subform_operations()` turns each op's
`FieldAssignments` into Write field-usage rows on the subform (FieldUsage sheet, explorer
W badges, write-conflict detection) and Read rows on the trigger form for `FromTrigger`
sources; actions carry an additive `subformAdds` key that narration renders as "…and adds
four rows to WorkOrderMeasures". Previously these subform writes were invisible to the
pipeline. No-op against current data (no export on disk carries the parameter yet).

**WFEngine workspace-export parsing + workflow write-conflict detection (2026-07-13).**
All five workspace baselines were re-exported by the platform's new workflow engine, which
carries workflows as a top-level `Workflows[]` array (`Triggers`/`Steps` shape) instead of
the old per-form embedded `WorkflowConfigs`. The parser only read the old shape, so every
workspace was silently reporting 0 workflows (111 dropped fleet-wide: liwp 28, nve-qar 1,
sce-be 16, sdge-whp 23, socal-whp 43). `parse_workspace_export` now parses both shapes
through a shared `_parse_wfengine()` helper (also used by individual workflow-file
exports, so the two paths can't drift), normalizes WFEngine's numeric enums
(`WorkflowEngineTriggerType`/`DatabaseActionType`/`...Timing`) to the plain strings the
rest of the pipeline expects, and summarizes `BuiltIn.SendEmail` actions into the same
`"To: … · Subject: …"` shape Legacy notifications use so narration covers both. Fixed a
real bug the one scheduled workflow surfaced: a leftover `databaseAction` value on cron
triggers was overriding the schedule phrasing in `workflow_story` — cron now wins.

Also added a field-write conflict check: the workflow-detail panel now shows a "⚠ Write
conflicts" block when a workflow writes a field another workflow in the same workspace
also writes — a real race with no guaranteed run order — linking to the other workflow.
Scoped to write collisions only, not shared triggers (two workflows firing on the same
event is common and usually intentional). `narrate.build_workflow_conflicts()`, injected
as `DATA.wfConflicts`. Zero conflicts exist in current data; the check guards against
future regressions. All 5 workspaces regenerated.

**Form version history (2026-07-10).** Multiple `_vNN` exports of one form are now
first-class history instead of warned-about duplicates: highest version wins as the
active design, every export on file lands in a per-form `versionHistory` (with
field-level deltas vs the previous version), and the rebuild prints one changelog line
per multi-version form (`395 - Inspection Work Order: v78 -> v79 active (+1 field)`).
Warnings only fire on same-version ties. Surfaces: `Version`/`PriorVersions` columns
(Forms sheet), `Version` (global AllForms), `v79 · 2 versions on file` in the explorer
form panel, newest-first "Version history" section in briefs, and `version` as a
compared meta key in snapshot diffs. `scripts/organize_forms.py` (dry-run/--apply)
swept all 33 loose root-level form exports into canonical `forms/<Form Name>/` folders
across the five workspaces (local-only; data/ is gitignored). Field-compare keys now
live in `parser.FIELD_COMPARE_KEYS` (versioning.py imports them). Tests:
`tests/test_parser_history.py` + two new snapshot-compare cases.

**Version snapshots and compare (2026-07-07).** `scripts/versioning.py` serializes
`discover_all()` output to `output/snapshots/` with a manifest index. Full rebuilds
auto-save when state changes; `--snapshot [LABEL]` captures on demand; `--compare OLD NEW`
reports form/field/workflow/relationship deltas (console + optional JSON). Reuses
`build_registry` fingerprints for design and workflow logic drift. Unit tests in
`tests/test_versioning.py`.

Plans 01–03 executed (2026-07-02) — one working session, all verified end-to-end:

**Drop-anywhere ingestion (plans/01).** Root-level JSONs are routed by detected content
(workspace export → baseline; form/workflow export → override), so file placement no
longer matters. Individual form exports match their baseline form by **field overlap**
(all 33 pending 2026-06 design files resolved correctly; Climate Zones via the
filename-token tiebreak) with `form_aliases.json` as the escape hatch; the filename
regex heuristic survives only for no-baseline workspaces. Same-form version dedup
(v79 beat v78, warned). Stale socal-whp filename aliases removed; unused-alias warning
added. Three stale-name phantom stubs (`Account Management (200)`, `499 - SDGE Fee
Schedule`, `QAR Measures`) fixed with `name_aliases` entries (local-only — data/ is
gitignored). start.bat README.txt/error text rewritten.

**Plain-English briefs (plans/02).** narrate.py rewritten for the program staffer:
platform Description leads each brief, workflow story cards ("Runs when a 310 -
Enrollment Intake record is updated, and only if Enrollment Status is 'Pending
Review'. → Sends an email to workflow-recipient@example.com — subject …"), labels over API
names, workflow names over callsigns, count_phrase (no "(s)"), plain conditions
(`condition_to_plain`), humanized schedules ("weekly on Monday"), de-braced template
tokens ("{the record's ESA Key}"). Fixed `_expr_to_text` empty-operand joins (the
" AND  AND …" garbage); unrenderable `Comparison` guards are filtered, not shown as
noise. Fixed narrative key-order nondeterminism (sorted set union). Brief page
restructured (What this form is for / What happens automatically / Filling it out /
What changes what + Filled-in-automatically). Explorer JS phrase mirror synced;
narrative wfCondition/writtenBy now carry `{callsign, name}`.

**General improvements (plans/03).** Rebuild summary block (totals + all warnings,
collected once per process in `parser.WARNINGS`); `--check` discovery-only mode;
workflow story panel ("What this does") atop the explorer's workflow detail via
`DATA.wfStories`; per-workspace `forms/index.html` brief indexes + "All form briefs"
landing chips; `TriggerPlain` column in Workflows/AllWorkflows sheets; Excel
WorkflowType fills unified to the graph palette (light red/olive); global sidebar
workflow-reuse panel (pattern/DriftFlag/LiteralTwin from the registry); action-index
precision on wf-edges (`actionIndex` → `data-action-idx`); `#wf=<callsign>` deep link;
brief print page-break rules; start.bat remembers the last-opened view
(`output/last-view.txt`, gitignored).

Graph search box — both explorers. Per-workspace: `runSearch()` (#search input) matches
forms, fields, and workflows by name, prints a match count, tiers results by hop distance
from the match set, and fits to the matches. Global: a `#search` box matches forms and
workspaces and fits to hits. Covers the "find and jump to a form/field on a large graph"
need (socal-whp is 97 forms / 54 workflows).

Workflow trigger/action edges clickable. The edge tap handler's `wf-edge` branch resolves
the workflow from the edge's `WF:<callsign>` endpoint, highlights it, and renders the
workflow-detail panel; action edges then call `scrollToWfAction(targetForm, actionIdx)` to
scroll the exact action card into view and flash its border. Trigger edges open the panel
without scrolling.

Export button copies form fields as markdown table to clipboard. Columns: API Name,
Label, Type, Required, WF (R/W/C). Respects active filter and sort. All 5 workspaces
regenerated.

Field-detail breadcrumb. Navigation trail above the form heading once two+ forms visited
(A › B › Current). Clicking ancestor back-navigates and truncates forward history. Capped
at 5 entries; clears on panel close. All 5 workspaces regenerated.

Pin a form to the side panel. 'Pin' button in form header locks the panel while clicking
nodes/edges/background updates graph highlights normally. Background tap while pinned
clears highlights only. × or 'Pinned' releases it. All 5 workspaces regenerated.

Copy-to-clipboard on field names. Hover any field row to reveal a ⧉ button next to the
name; click copies the API name and flashes ✓ for 1.5s. Always copies API name regardless
of Name/Label display toggle. navigator.clipboard with execCommand fallback. All 5
workspaces regenerated.

No results message with clear-filter action. Empty state names the query ("No fields
match 'zip'") and offers a 'Clear filter' button that resets the input, refocuses
#field-search, and re-renders the list. All 5 workspaces regenerated.

Persist field-list state across node clicks. formFieldState map keyed by form name;
save on every panel transition (renderForm/renderWorkflow/renderEdge/renderEmpty);
restore on form open. "Lock" button next to #field-search carries the active filter
into unvisited forms. Lock persists in localStorage. All 5 workspaces regenerated.

Dagre hierarchical layout. Added cytoscape-dagre plugin (rankDir:TB, nodeSep:50,
rankSep:100). New "Layout: Dagre" option in the toolbar dropdown alongside existing
layouts. All 5 workspaces regenerated.

Keyboard navigation for field list. Roving-tabindex: Tab from #field-search enters the
list (one tab stop), Tab again leaves. ArrowDown/Up move across group boundaries, clamping
at ends; Home/End jump to first/last. Enter/Space toggle inline detail; Esc collapses
expanded row or returns focus to search. restoreRoving() silently updates tabindexes after
every re-render without stealing focus during filtering. a11y: role=listbox / role=option.
All 5 workspaces regenerated.

Visual marker for intra-form field dependencies. Two badges on field rows: DEP (teal, this
field's formula/visibility/validation references other fields) and REF'D (lime, other fields
on this form reference this one). Precomputed per form render via buildUsedBySet(). Tooltip
text clarifies the direction. All 5 workspaces regenerated.

Sort options for field list. Second dropdown "Sort: Original / Required first / Hidden last /
By type" in the toolbar alongside the Name/Label display toggle. Sorts within each
section/page group; persisted per-browser via localStorage.

Node filter toolbar (scripts/explorer_template.html). Filters button after #theme-toggle,
checkbox dropdown: Workflows·Legacy, Workflows·WFEngine, Workflows·Disabled, Forms·Subforms,
Forms·Lookups, Orphaned. applyFilters() = 4 ordered passes: category → dangling-edge →
filter-hygiene (always-on, hides nodes left with zero visible edges) → Orphaned (degree-0 /
orphaned flag, toggle only). Per-slug localStorage, default all visible, no re-layout.
Regenerated + published across all 5 workspaces.

Circuit-board edge routing. Bezier → round-taxi (orthogonal right-angle) in both
explorer_template.html and global_template.html; field label sits on a horizontal jog.
Coexists with pair-fan logic — shared node-pairs fall back to bundled-bezier arcs so their
labels don't garble. Routes against the Hierarchy (breadthfirst) layout.

Name/Label toggle for field list display. Both name and label extracted; UI toggle picks
which is primary. Persisted per-browser.

Workflow-type colors. Legacy = red, WF Engine = olive (#9fae5a); nodes and trace edges
colored by type from shared --wf-legacy / --wf-engine vars; legend reads "WF Engine".

Cross-workspace reuse registry. WorkflowReuse (pattern-keyed, Invoice chain surfaced),
FormFamilies (design-fingerprint families, reference-replication tagged), FieldTemplates.
Global collision-link suppression: 21 of 47 dropped.

Group fields by section/page. ParentId-chain reconstruction (workspace-flat + nested walk);
fields carry page/section/sort_order. 325 collapses from an 814-field wall to 31 named
measure-groups (~806/808 design fields resolved).

Highlight workflow-touched fields, with direction. Binary .touched highlight plus R/W/C
badges from fieldUsage.

Field detail expands inline beneath the clicked field row. Multiple expand at once; sticky
control bar with Collapse all / Expand all (confirms above 20); chevron marks state; resets
on form change; filter hides non-matching rows without collapsing.
