# Explorer UI / data-model / graph cohesion review

Date: 2026-09-03
Scope: `output/<slug>/workspace_explorer.html` (all five workspaces), `output/global/global-explorer.html`, per-form briefs, `docs/index.html`, and the data model the graphs are built from.
Method: every explorer was rendered in headless Edge at 1600x950 and the live Cytoscape state was inspected (node positions, edge counts, filter state). Graph density numbers come from `parser.Workspace.discover()` directly.
Files changed: none. This folder holds the report and the screenshots it cites.

## Verdict

The side panel, the per-form briefs, and the Excel workbooks are cohesive and strong. The graph layer is not. The "mind map" is currently the weakest way the project exposes linkages, and two of the five per-workspace graphs are broken on first open.

## What was observed on load

| View | On load | Nodes / edges | Screenshot |
|---|---|---|---|
| socal-whp | 10 forms placed by the preset; the other 131 nodes stacked at (0,0) | 140 / 107 | `socal.png` |
| liwp | blank after a 6 s virtual-time budget; all 153 nodes still at (0,0) waiting on force layout | 153 / 120 | `liwp.png` |
| sdge-whp | force-layout hairball; labels unreadable at fit zoom | 72 / 88 (29 parallel-bundled) | `sdge.png` |
| global | five tidy clusters, zero edges drawn | 60 / 0 | `global.png` |
| brief (300 - Account Management) | clean, readable, consistent with the explorer panel | n/a | `brief.png` |
| form brief index (socal-whp) | clean; 86 grids listed, most badged "Featured" | n/a | `briefindex.png` |
| landing page | clean; featured chips dominated by grids | n/a | `landing.png` |

## Graph density per workspace

Computed from discovery output. `relEdges` counts distinct source->target pairs (the explorer aggregates parallel relationships into one edge). `grid` is the subset of those that are "(embedded grid)" containment edges.

| Workspace | Forms | Subforms | Hub/Spoke/Lookup | Workflows | relEdges (grid) | wfEdges | Degree-0 nodes |
|---|---|---|---|---|---|---|---|
| socal-whp | 97 | 86 | 1 / 6 / 4 | 43 | 62 (48) | 45 | 39 |
| liwp | 125 | 107 | 2 / 12 / 4 | 28 | 92 (71) | 28 | 39 |
| sdge-whp | 46 | 37 | 1 / 5 / 3 | 26 | 48 (37) | 40 | 0 |
| sce-be | 36 | 28 | 1 / 3 / 4 | 22 | 36 (27) | 33 | 1 |
| nve-qar | 10 | 1 | 0 / 8 / 1 | 1 | 4 (1) | 1 | 5 |

Only 2 to 4 form pairs per workspace are truly bidirectional. The structure is a tree of grids hanging off a handful of real forms, with a thin layer of form-to-form and workflow edges on top.

## Findings, most important first

### 1. Preset layout drops every unpositioned node at the origin

`scripts/explorer_template.html` line 468 runs the `preset` layout whenever `manual/explorer_layout.json` exists. socal-whp's file names 10 of 140 nodes. The remaining 131 (86 grids, 43 workflows, 2 forms) are drawn on top of each other at the top-left corner, under the first workflow node. This is the flagship workspace and it looks broken on first open.

Fix: run preset for positioned nodes, then a second layout (dagre or cose) for the rest; or nest grids as compound children of their parent and only position top-level forms.

### 2. The data is a tree, but it is drawn as a network

259 of 314 forms across all workspaces are Subforms whose only edge is "(embedded grid)" to a parent. A force-directed or hub-and-spoke graph spends most of its pixels on grid rows that carry no linkage information. That is why sdge-whp reads as spaghetti even though it has only 72 nodes.

A compound-node view (grids nested inside their parent, collapsed by default) or a plain tree/outline would show the same information in a fraction of the space and make the real form-to-form and workflow edges legible.

### 3. The global "mind map" has no links at all

`scripts/global_template.html` line 193 onward builds workspace and form nodes only. No edge elements are ever added, even though the stylesheet defines `dup-edge`, and CLAUDE.md, README.md, and the landing page all describe "duplicate form names linked across clusters."

Compounding this, the graph excludes Subforms (`_ATLAS_ROLES` in `scripts/build_global.py`) while the collision list includes them. 24 of the 27 collisions in the sidebar point at nodes that do not exist on the canvas, so clicking them highlights nothing. Only Measures, Program, and Invoice are actually on the graph.

The global view today is a cluster diagram plus a sidebar list. The list is doing all the work.

### 4. Duplicate-flow signatures are degenerate

90 of 120 workflows collapse into one bucket, `Update -> (no target)`, because email-only workflows have no target form. The "Duplicate flows" sidebar section conveys nothing. The registry's pattern key (`WorkflowReuse`) already solves this and is shown in the adjacent section.

### 5. "Featured" has lost its meaning

No workspace has a `manual/featured_forms.json`, so the `FEATURED_KEYWORDS` default applies everywhere. It substring-matches the parent qualifier in grid names, so `ExistingCeilingFanDetails (325 - SoCal Installation)` is featured because its name contains "installation." Result: 41 featured forms in liwp, 40 in socal-whp, gold rings on grids, and landing-page chips dominated by grids.

### 6. Orphans are a data gap surfaced as a UI problem

socal-whp and liwp each have 39 degree-0 nodes, almost all unparented grids whose parent was not in the export. They float on the canvas rather than being reported as "parent not in export" next to the form they belong to.

## What is cohesive

- The side panel is the real product. Form-detail, edge-detail, field-detail, and workflow-detail share one visual language, one selection model, and the same narration the briefs use. The forward "changing this field affects" model is the best answer to "what breaks if I rename X" in the repo.
- Briefs and explorer agree. The brief page, the "What this form does" block, and the form index render the same deterministic prose. Role vocabulary, colors, and badges are consistent across explorer, brief, landing page, and Excel.
- The cross-view deep link from the global explorer into the per-workspace explorer works (verified by tapping `300 - Account Management` and reading the panel sections).
- Keyboard navigation, theme toggle, panel resize, and filter persistence all work as documented.

## Recommendations

Treat the graph as a navigation aid for the roughly 10 real forms and 40 workflows per workspace, not as the primary view of linkages.

1. Fix the preset bug (finding 1). Smallest change: after the preset layout, run dagre on the nodes that had no preset position.
2. Default the workspace graph to a deterministic hierarchical layout with Subforms collapsed into their parent. Expose grids in the panel, not on the canvas. This removes 80 to 85 percent of nodes from the default view without losing any information.
3. In the global view, either draw the collision edges for forms that are on the graph, or drop the canvas and make the sidebar tables the view. Show subform collisions as table rows, never as phantom nodes.
4. Replace the `Update -> (no target)` duplicate-flow signature with the registry pattern key, or remove the section.
5. Ship a `featured_forms.json` per workspace, or restrict the keyword default to non-Subform roles.
6. Report unparented grids in the parent form's panel (or the brief) as "grid whose parent is not in the export," and hide them from the canvas by default.
