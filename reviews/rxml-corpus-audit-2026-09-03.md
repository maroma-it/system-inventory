# RXML corpus audit, 2026-09-03

Static findings from decoding the eleven distinct `.rxml` layouts in `docs/reporting/` against the
platform field index (`docs/field-index.json`) and the workspace exports under `data/`. Nothing here was
run against the database; the one data check used `SDGE-Production-Report (16).xlsx`. Method and format
notes are in `xtrareports-reference.md` at the repo root.

The source files stay local: `docs/reporting/` is gitignored because it holds customer-data exports and
the production connection string, and `docs/` is the GitHub Pages publish target. This audit is the
tracked record of what is in them.

`(CPUC) Customer Demographics (1).rxml` and `(2).rxml` are byte-identical (same SHA-1); one can go.

## Corpus-wide

- **Column-to-field mapping holds everywhere.** Every `reporting.*` view column used by any query
  matches a form field API name in the field index, apart from platform system columns (`Id`,
  `CreationTime`, `LastModificationTime`, `TenantId`, `ParentId`, `TopLevelId`) and four view-side
  columns (`ProjectName_5`, `ProjectNumber`, `Auto_ProjectNumber`, `MeasureExternalId_Text`). The
  inventory can therefore resolve any report column to its form field offline.
- **Every data source embeds the full production connection string** (server and database, AD auth,
  no password). Keep this folder untracked.
- **Every date column the views expose is `Type="Unknown"` in the cached schema.** That is the
  `datetimeoffset` signature. Expressions that compare those columns to `Today()`/`AddDays()` inline
  are at risk; the SoCal Weekly report is the one that does it (see below).
- **Option Key/Value drift is real and present in the data.** The platform stores the option `Key` on
  older rows and the `Value` on newer rows for the same field. From the SDGE export:

  | Column | strings present (rows) |
  |---|---|
  | Submission Status (415) | `Bid Proposed` 181 (Key) · `Ready for Review` 13 (Value) · `Draft` 49 (Key) · `Draft Pending` 5 (Value) |
  | Submission Status (410) | `Ready for Review` 179 · `Completed & Ready for Review` 26 |

  Any report condition that tests one string and not the other under-counts. Affected literals are
  listed per report below. This also matters for workflows: `workflow-engine-reference.md` says the
  engine matches `Value`, which is about *new* conditions; historical rows still carry the `Key`.

## Per report

### (00) Program Dashboard
- `CountCorrectionsRequired_315` references `[ReviewStatus]`; the 315 query exposes the column as
  `Review Status (315)`. Null in every row, count is always 0.
- `SoCal_Pending_Review` tests `[Submission Status (310)] = 'Ready for Review'`. That is the Key; the
  Value is `Completed & Ready for Review`. Both exist in data (see above). Under-counts.
- `count_415_pending` tests `[Submission Status] In ('Ready for Review', 'Bid Proposed')`, which
  correctly covers both sides, but then `[Review Status] In ('Bid Approved', 'Bid Approved—Pending
  Savings')`. `Bid Approved—Pending Savings` is not an option on 415 (the real one is `Bid
  Approved—Verify Savings`). Branch never fires.
- `[Review Status] = ''` on 415 and `Enrollment Approved` on 425: neither is an option value.
- Zero master-detail relations are defined; all 34 calc fields are whole-table totals on detail
  queries read from the header as `[query.field]`. Works, but the root `DataMember` (SoCal 300) is
  decorative and the Detail band is hidden. Nine queries, four of which are SDGE and one BEP, so this
  is a cross-program dashboard fed by one data source.
- Literal encoding: the em dash in `Bid Approved—…` is U+2014 in the file, matching the option set.
  Not a mismatch on its own.

### (01) SDGE Weekly
- Two malformed format strings on date cells: `{{0:MM/dd/yy}` and `{0{0:MM/dd/yy}`.
- `LeadStatusSortOrder` declares `FieldType="Int32"` but returns `'01'`..`'99'` strings.
- The Invoice master-detail relation is defined and never referenced.
- One `SortFields` entry, `_enrolled`, with no `SortOrder` (defaults ascending).
- All literals match option values. `Ready for Review` on 400 Enrollment Status is a same-Key-and-Value
  option there, so no drift.

### (01) SoCal Weekly
- `Aging_Start`, `Aging_End`, `Aging_Days`, `Project_within_12_Months` wrap offset columns
  (`Canceled Date`, `Installation Status Date`, `Project: Lead Assigned Date`, `Job Completed Date`,
  signature dates) in `GetDate(...)` before `DateDiffDay`. This is the field-to-field pattern that works;
  no inline `Today()` comparison found. Keep it that way.
- `Project_Status_c` and `Assessment_Status_c` have **empty expressions**. Any binding to them shows
  blank.
- `SortFields` lists `Expenditure Report Period` twice. The second entry is dead.
- Root `FilterString` `[Lead Status] <> 'Unassigned'` drops rows where Lead Status is null. If null
  leads should show, guard it as the BE Weekly report does.

### (01) BE Weekly
- Clean. Root filter is null-guarded (`[Lead Status] <> 'Unassigned' Or Not IsNullOrEmpty([Submission
  Status (255)])`). Query joins 200/210/255 at SQL level and also defines master-detail relations to
  210 and 255 detail queries; both are used.
- Single calc field `TotalStatus = Sum([Status])` on the joined query; `Status` is a Boolean column, so
  this counts trues. Fine, but name it.

### (CPUC) Customer Demographics
- `Count_of_Projects = ToInt([Id])` on a Guid column. That does not produce a count; it fails the
  conversion (null) or, if the engine coerces, produces garbage. If the intent is a row count, use
  `[][].Count()`.
- `Marketing_Group` is a 145-city `Upper([Service City]) In (...)` ladder. Correct as written; brittle.
  A city lookup view would remove it.
- Three master-detail relations are defined for queries that are not in the data source (copied from
  the SoCal Weekly source). Harmless, dead.

### (02) Bi-weekly Report (GF) and (GGRF)
- **`[Clone Project]` does not exist.** The query exposes the column as `ClonedProjectCheckbox` (no
  alias). 109 and 111 calc fields respectively test `[Clone Project] <> True`. In SQL-style three-valued
  logic that predicate is unknown, every `Iif` falls to 0, and every county metric reads 0. If the
  published reports show non-zero numbers, the in-memory evaluator is treating `null <> True` as true;
  either way the clone exclusion is not happening. Add `Alias="Clone Project"` to the column, or
  rename the references. This is the highest-value fix in the corpus.
- `Total_Allocated_Region_B_SPV` is referenced by five fields and defined nowhere (the defined name is
  `Total_Allocated_Region_B_SPV_category`). Null propagates into the Region B totals.
- `[Assessment Status] = 'Ready for Review'`: Key only; Value is `Completed & Submitted`. Test both.
- `= ''` comparisons on picklists (Lead, Enrollment, Assessment, Installation Status) are dead
  branches; use `IsNullOrEmpty`.
- The query filter pins `LeadProgram = 'Low-income Weatherization Program - 2022'` and `GGRF =
  'False'`/`'True'`. The program-year literal is the hard-coded constant the handoff notes flagged.
- `OpenLeads_AllocatedTotal = [calculatedField119] * 13428` (GF) and `* 14000` (CARB): per-lead
  allocation rates as literals.
- 90+ fields are named `calculatedFieldNN`. Not a defect, but the footer bindings are unreadable
  without a rename pass.

### CARB General Funds (2) and CARB Reporting (2)
- **Twelve calc fields are bound to `DataMember="reporting_LIWP_FWHC_00_Account"`, which is not a
  query in this data source** (the queries are `reporting_LIWP_00_Accounts`, `_00_Measures`,
  `_99_Measures`, `_02_Assessment`). All twelve are null. This is the defect the handoff notes record as
  fixed in `CARB-General-Funds_B`; these `(2)` exports predate or lack that fix.
- `OpenLeads_AllocatedTotal` references `[calculatedField119]`, which is not defined in this file.
- `Priority_population` is correctly bound to the relation path
  `reporting_LIWP_00_Measures.reporting_LIWP_00_Measuresreporting_LIWP_00_Accounts`, the one place in
  the corpus that uses that form.
- Root filter is the exists-over-relation form with `[GGRF] <> True` inside the bracket. Null GGRF rows
  are excluded by that predicate; the handoff notes say that was the exact population the report
  exists to capture. Guard it: `(IsNull([GGRF]) Or [GGRF] <> True)`.
- `SerializerVersion` differs between the two files (`25.2.5.0` vs `25.2.7.0`); content is otherwise
  the same report.

### SDGE PO Report
- `Total_Budget_Allocation_f` and `full_install` have empty expressions.
- `_Budget_Per_Project_Workaround = [Budget Allocation] / [][[Contractor] == [^.Contractor]].Count()`
  spreads a contractor budget evenly across its invoice rows so the cross-tab can sum it back. It works
  only if every contractor has at least one invoice row (the join is LeftOuter from Program, so a
  contractor with no invoices gets one null row and a count of 1; fine). Document the trick.
- Column 3 (`Budget Allocation` row field) is hidden via `ColumnDefinitions/Item3 Visible="false"`.

### BE PO Report
- Six `BudgetAllocation_*` fields are bound to relation path
  `Reporting_99_Invoice.Reporting_99_Invoiceprogram_overview_query`. No such master-detail relation
  exists in the data source (the two queries are joined at SQL level instead). Four of the six also have
  empty expressions. All six are null; none is used by the cross-tab.
- `Program_Budget_c = 32727480`, `Admin_Costs = 3927298`, `Subcontractor_Cost = 28800182`: hard-coded.
- `IsPostAverageDate` compares `GetDate(ToStr([InstallationDate_c])) > #2025-10-1#`. The
  `AverageCutoffDate` parameter (`ValueInfo="2025-10-01"`) exists for exactly this and is unreferenced.
  Bind it: `> ?AverageCutoffDate`. The `ToStr` round-trip is an offset workaround; a field-to-field
  compare against a calc field holding the cutoff would be cleaner.
- `PostAvgDateAvg` is a per-row ratio; the cross-tab sets `SummaryType="Average"` on it, which is
  right. `Percent_Contract_Complete` and `_Project_differential` are also ratios and are not in the
  cross-tab, so no issue today.

### SoCal WHP Report (PO)
- Same unreferenced `AverageCutoffDate` parameter as BE PO.
- `budget_per_project_workaround_enroll` is now `[Budget Allocation] / [][...].Count()` (the recursive
  self-reference the handoff notes fixed is gone in this export).
- The two queries split contractors by name: one filters `Not [Contractor] In ('ApexEnergy Audits',
  'Elite Desert Plumbing', 'The Ortiz Group')`, the other the inverse. A roster change breaks both
  silently. Move the split to a column on the Program view.
- `Total_Unpaid_EDP` from the handoff notes is not in this export; `total_unpaid` is, and it sums
  enrollment and assessment amounts with proper null guards.

## Suggested order of fixes

1. Bi-weekly GF/GGRF: alias `ClonedProjectCheckbox` as `Clone Project` (one line in the data source
   blob, or 220 expression edits).
2. CARB (2): rebind the twelve dead-member fields to `reporting_LIWP_00_Accounts` (or take the `_B`
   file as canonical and retire these).
3. Program Dashboard: fix `[ReviewStatus]`, `Bid Approved—Pending Savings`, and add the Value-side
   strings next to every Key-side literal.
4. Everywhere: for each status literal, test both Key and Value until the stored data is migrated.
5. PO reports: bind `?AverageCutoffDate`; move budget constants and contractor rosters out of the layout.
6. SDGE Weekly: the two broken format strings.
