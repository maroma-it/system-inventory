# DevExpress XtraReports Reference (for decoding `.rxml` / `.repx` layouts)

Companion to `workflow-engine-reference.md`. That file documents the platform's workflow engine; this one
documents DevExpress XtraReports v25.2 as it is used by the reporting layer on top of the same workspaces.
It is written for the job this repo will do with report files: open a layout, decode what it queries,
how it joins, which fields each column reads, which expressions transform them, and where the file can be
wrong.

Sources: the DevExpress XtraReports documentation (class reference and feature guide, v25/26), the
DevExpress criteria-language reference, and direct inspection of the eleven distinct `.rxml` layouts
under `docs/reporting/` (first pass 2026-09-03 on one file; corpus pass the same day on all eleven).
Where the docs are silent and the files are the only evidence, the sentence says "observed". Part VII
lists the corpus and what each file contributed.

Not covered: designer UI, printing/exporting API, web viewer integration.

---

## Part I. The object model in one page

An **XtraReport** is a banded report. It has:

| Property | Role |
|---|---|
| `DataSource` | The data component. In a layout file it is a `#Ref-N` pointer into `ComponentStorage`. |
| `DataMember` | Which query/table of that source drives the row loop. For a nested `DetailReportBand` it is a relation path. |
| `FilterString` | Client-side row filter in criteria-language syntax, applied **after** the data is fetched. |
| `CalculatedFields` | Named expressions evaluated per row of their `DataMember`. Usable anywhere a field is. |
| `Parameters` | Report parameters, referenced as `?Name`. Can feed query parameters. |
| `Bands` | The band tree: margins, report/page header+footer, group header+footer, detail, nested detail reports. |
| `StyleSheet` | Named `XRControlStyle` entries; controls reference them by `StyleName`. |
| `FormattingRuleSheet` | Conditional formatting rules (legacy binding mode only). |
| `ComponentStorage` | The serialized data source(s), each stored as one Base64 blob. |
| `ScriptsSource` / `ScriptLanguage` | Report scripts (disabled by default for security; not present in the observed file). |
| `Version` / `SerializerVersion` | Product version the layout was written with. Newer runtimes read older files; not the reverse. |

Row loop: the engine iterates the rows of `DataSource.DataMember` (after `FilterString`, sorted by
`DetailBand.SortFields`, grouped by `GroupHeaderBand.GroupFields`), and for each row prints the Detail band.
Group bands print at group boundaries; report/page bands print once per report/page. A
`DetailReportBand` nested inside repeats its own band tree for the detail rows related to the current
master row.

Controls (`XRLabel`, `XRTableCell`, `XRCheckBox`, `XRPictureBox`, `XRChart`, `XRSubreport`, ...) live in
bands. A control's value comes from an **expression binding**: `ExpressionBindings` = list of
`(EventName, PropertyName, Expression)`; the usual one is `("BeforePrint", "Text", "[Field]")`. Any
bindable property can be driven this way (`Visible`, `BackColor`, `Font.Bold`, `NavigateUrl`...).

Three ways to compute a number across rows, and they do not mix:

| Mechanism | Where | Scope decided by | Notes |
|---|---|---|---|
| Summary functions `sumSum()`, `sumCount()`, `sumAvg()`, `sumRunningSum()`, `sumPercentage()`... | Only the `Text` of `XRLabel`/`XRTableCell` | `Summary.Running` = Report / Group / Page **plus** which band the control sits in | Evaluated after rendering; affected by report `FilterString`. Cannot be used in calculated fields. |
| Aggregate operators `[Collection][Condition].Sum(expr)` | Any expression, including calculated fields and `Visible` | The collection named in the first bracket; `[]` = the current data member; `^.Field` reaches the parent row | Evaluated against the data source, so **not** affected by report-level `FilterString`. |
| Legacy `XRSummary` (`Func` + `Running`) attached to a label | `Bindings` data-binding mode only | `Running` | Serializes as `<Summary Ref=.. Running=.. Func=.. />`. Absent in Expressions mode. |

Observed across the corpus: no report uses `sum*` or `XRSummary`. Every total is a **calculated field**,
and the dominant form is a **bare aggregate call**, `Sum(Iif(cond, 1, 0))`, `Min(Iif(...))`, `Count()`,
with no `[][]` prefix (roughly 300 of them across the two bi-weekly reports and the dashboard). A bare
aggregate in a calculated field aggregates over **every row of the field's `DataMember`** after the
query-level filter. The `[][cond]` form appears where a per-group denominator is needed
(`[Budget Allocation] / [][[Contractor] == [^.Contractor]].Count()`), and `[][].Sum(x)` for grand
totals. The docs' statement that inline `.Sum()` "does not work" refers to the `[Member.Field].Sum()`
spelling, not to bare `Sum(expr)`.

---

## Part II. The layout file (`.rxml` / `.repx`)

`.rxml` and `.repx` are the same XML serialization. Written by `XtraReport.SaveLayoutToXml`, read by
`LoadLayoutFromXml` / `XtraReport.FromXmlFile`. There is no published schema.

### II.1 Envelope

```xml
<?xml version="1.0" encoding="utf-8"?>
<XtraReportsLayoutSerializer SerializerVersion="25.2.7.0" Ref="1"
    ControlType="TOG.Reporting.DevExpressReporting.Samples.DefaultReport, TOG.Domain, ..."
    Name="Report" Dpi="96" DisplayName="SDGE-Production-Report"
    ReportUnit="Pixels" Landscape="true" PaperKind="Custom" PageWidthF="1920" PageHeightF="1080"
    Margins="0.833333, 0, 0.835598, 7.499996" SnapGridSize="12.5"
    Version="25.2" DataMember="SDGE_400_Accounts" DataSource="#Ref-0">
  <CalculatedFields> ... </CalculatedFields>
  <Bands> ... </Bands>
  <StyleSheet> ... </StyleSheet>
  <ComponentStorage> ... </ComponentStorage>
</XtraReportsLayoutSerializer>
```

- File is UTF-8 **with BOM**. Read as `utf-8-sig` (observed; the first tag mis-parses otherwise).
- `ControlType` on the root is the .NET type of the report class. A custom base class (as here) means the
  consuming application must be able to construct that type; it does not affect decoding.
- `ReportUnit` decides whether `HeightF`/`WidthF`/`LocationFloat` values are pixels (Dpi 96), hundredths
  of an inch, or tenths of a millimetre. Observed: ten reports use `Pixels`; the CPUC demographics
  report uses `Inches` with `Dpi="1"` on its controls and sizes like `SizeF="6.345,0.0208"`. Convert
  before comparing geometry across files.
- Properties at default value are omitted. Absence means default, not "unset". A root without
  `DataMember` is legal (observed on the SoCal PO report, whose two cross-tabs each carry their own).
- Other top-level sections seen: `ExportOptions` (`<Mht RasterizationResolution="100"/>`),
  `Parameters`, `ParameterPanelLayoutItems`, `ObjectStorage` (II.10). `SerializerVersion` varies
  within one product version (`25.2.5.0` and `25.2.7.0` both present); it is a build stamp, not a format
  version.

### II.2 `Ref` numbering

Every serialized object carries `Ref="N"`. `Ref` values are **document-global and unique** (observed: 142
refs, 142 distinct, 0..141). Pointers use `#Ref-N` (`DataSource="#Ref-0"` on the root points at the
`ComponentStorage` item with `Ref="0"`). Consequences for editing:

- New objects must take `max(Ref)+1`.
- A duplicate `Ref` makes the loader resolve pointers to the wrong object. Scan after every insert.
- `Ref` is not the same as collection position.

### II.3 Collections: `ItemN`

Every collection serializes its members as `<Item1>`, `<Item2>`, ... in order. `ItemN` is the **position
within that collection**; `Ref` is global. After deleting a member, renumber the siblings so they stay
contiguous from `Item1` (the loader relies on the sequence). Collections seen: `CalculatedFields`,
`Bands`, `Controls`, `Rows`, `Cells`, `ExpressionBindings`, `SortFields`, `GroupFields`, `StyleSheet`,
`ComponentStorage`, `Parameters`, `FormattingRuleSheet`, `Series`.

### II.4 Bands

```xml
<Bands>
  <Item1 Ref="6"  ControlType="TopMarginBand"   Name="TopMargin"    Dpi="96" HeightF="0.835598" />
  <Item2 Ref="7"  ControlType="GroupHeaderBand" Name="GroupHeader1" Dpi="96" GroupUnion="WithFirstDetail" HeightF="28.8">
    <Controls> ... </Controls>
  </Item2>
  <Item3 Ref="52" ControlType="DetailBand" Name="Detail" Dpi="96" HeightF="24.3">
    <HierarchyPrintOptions Ref="53" Indent="19.2" />
    <SortFields><Item1 Ref="54" FieldName="_enrolled" /></SortFields>
    <Controls> ... </Controls>
  </Item3>
  <Item4 Ref="136" ControlType="BottomMarginBand" Name="BottomMargin" Dpi="96" HeightF="7.5" Visible="false" />
</Bands>
```

Band types: `TopMarginBand`, `ReportHeaderBand`, `PageHeaderBand`, `GroupHeaderBand`, `DetailBand`,
`DetailReportBand`, `SubBand`, `GroupFooterBand`, `PageFooterBand`, `ReportFooterBand`,
`BottomMarginBand`, plus the vertical trio (`VerticalHeaderBand`/`VerticalDetailBand`/`VerticalTotalBand`).

- `GroupHeaderBand.GroupFields` = `<GroupFields><ItemN Ref= FieldName= SortOrder=/></GroupFields>`.
  A `GroupHeaderBand` **without** `GroupFields` (observed) is just a header that prints once before the
  first detail row and is used as a column-caption row. `GroupUnion="WithFirstDetail"` keeps it on the same
  page as the first detail row.
- `DetailBand.SortFields` uses the same `GroupField` shape. `SortOrder` defaults to `Ascending` when
  omitted. Sort fields may name calculated fields (observed: `_enrolled`) and column aliases. A field name
  that resolves to nothing sorts silently as if absent.
- Matching `GroupHeaderBand`/`GroupFooterBand` pairs share the same `Level`.
- `DetailReportBand` carries its own `DataSource`/`DataMember`/`FilterString` and its own `Bands`. Its
  `DataMember` is a relation path (II.7). Not used by any report in the corpus.
- **Dashboard shape** (observed on the Program Dashboard, both bi-weekly reports, and the PO reports):
  the Detail band is empty or `Visible="false"` and every number lives in the `ReportHeaderBand` /
  `ReportFooterBand` as a table of calculated-field bindings. The row loop still runs (it drives the
  aggregates); it just prints nothing per row. Band heights of `1.5` px are the tell.
- Root `FilterString` observed in two forms: a plain predicate (`[Lead Status] <> 'Unassigned'`) and an
  **exists-over-relation** predicate with no trailing function,
  `[MasterDetail][Not IsNullOrEmpty([X]) And [GGRF] <> True] And Contains([Measure Type], 'Installation')`,
  which keeps a master row when at least one related detail row satisfies the bracketed condition.
- `XRPageBreak` may appear as a control inside a band; `PageFooterBand` may be present but
  `Visible="false"`.

### II.5 Controls, tables, cells

Controls nest under `<Controls>`. An `XRTable` has `<Rows>` of `XRTableRow`, each with `<Cells>` of
`XRTableCell`. Observed table cell:

```xml
<Item1 Ref="57" ControlType="XRTableCell" Name="tableCell21" Dpi="96"
       Weight="0.03617720235428438" WordWrap="false" StyleName="DetailData1" Borders="None">
  <ExpressionBindings>
    <Item1 Ref="58" EventName="BeforePrint" PropertyName="Text" Expression="[Enrollment #]" />
  </ExpressionBindings>
  <StylePriority Ref="59" UseBorders="false" />
</Item1>
```

- `Weight` is the cell's share of the table width (proportional, not absolute). Cell widths are
  `table.WidthF * Weight / sum(Weights in the row)`. Every cell in the observed file has the same weight,
  so all 38 columns are equal width.
- `XRTableCell` inherits from `XRLabel`: `Text`, `TextFormatString`, `Multiline`, `WordWrap`,
  `CanGrow`/`CanShrink`, `Padding`, `Borders`, `TextAlignment`, `TextTrimming`, `AllowMarkupText`,
  `Summary`. A cell that contains child controls cannot show text.
- `Text` is the static/design-time text. When an `ExpressionBindings` entry targets `Text`, the expression
  result replaces it at print time. Observed: caption cells in the header band carry only `Text`; detail
  cells carry both (the `Text` is a leftover label such as "Enrolled Status") or only the binding.
- Positions: `LocationFloat="x,y"`, `SizeF="w,h"` on free controls; table cells have neither (row/weight
  driven).
- `StyleName` references an entry in `StyleSheet`. `StylePriority` lists the `Use*` flags that are
  **false**, i.e. the properties where the control's own value overrides the style. All flags default
  to true (style wins). So `<StylePriority UseBorders="false"/>` plus `Borders="None"` means "this cell has
  no borders even though its style says left border".

### II.5a Cross-tabs (`XRCrossTab`)

Three PO reports are cross-tabs rather than tables. The control carries its own `DataSource="#Ref-0"`
and `DataMember` (which may differ from the root's), and four collections:

```xml
<Item3 Ref="18" ControlType="XRCrossTab" Name="crossTab1" DataSource="#Ref-0" DataMember="program_query"
       GeneralStyleName="crossTabGeneralStyle1" DataAreaStyleName=... HeaderAreaStyleName=... TotalAreaStyleName=...
       SizeF="1043.98,248.1" LocationFloat="37.5,60.83">
  <RowFields>  <Item1 Ref="19" FieldName="Contractor"/> <Item2 FieldName="DBE Status"/> ... </RowFields>
  <ColumnFields> ... optional ... </ColumnFields>
  <DataFields> <Item1 Ref="22" FieldName="_Budget_Per_Project_Workaround"/> <Item8 SummaryType="Average" FieldName="PostAvgDateAvg"/> ... </DataFields>
  <ColumnDefinitions> <Item1 Ref="27" Width="221.67"/> <Item3 Width="110.8" Visible="false"/> ... </ColumnDefinitions>
  <RowDefinitions>    <Item1 Ref="35" Height="35.77" Visible="false"/> ... </RowDefinitions>
  <Cells>
    <Item1 ControlType="XRCrossTabCell" Name="crossTabHeaderCell1" ColumnIndex="0" RowIndex="0" RowSpan="2" Text="Contractor" .../>
    <Item9 ControlType="XRCrossTabCell" Name="crossTabDataCell5" ColumnIndex="3" RowIndex="2" TextFormatString="{0:n2}" Borders="All"/>
    <Item18 ControlType="XRCrossTabCell" Name="crossTabHeaderCell10" ColumnIndex="1" RowIndex="3" ColumnSpan="2" TextFormatString="Total {0}"/>
    ...
  </Cells>
</Item3>
```

- **Cells carry no expression bindings.** Which field a data cell shows is positional: data columns
  follow the row-field columns in `DataFields` order, and `RowIndex` selects data row vs. subtotal vs.
  grand-total row. To recover "column N shows field X" you pair `ColumnIndex - len(RowFields)` with
  `DataFields[i]`. Header cells carry `Text`; total-header cells carry `TextFormatString="Total {0}"`
  where `{0}` is the row-field value.
- `SummaryType` on a data field defaults to `Sum`; `Average`, `Count`, `Min`, `Max` are the alternatives.
  A data field that is already a per-row ratio (`PostAvgDateAvg = paid / flag`) summed by default is a
  classic wrong-total; the BE PO report sets `Average` on that one.
- `ColumnDefinitions`/`RowDefinitions` with `Visible="false"` hide a computed column or a subtotal row
  without removing the field. Hidden columns are still evaluated.
- Field names in `RowFields`/`DataFields` resolve exactly like `[Field]` references (aliases and
  calculated fields), so the same dead-reference check applies.

### II.6 Expression bindings

```xml
<ExpressionBindings>
  <Item1 Ref="58" EventName="BeforePrint" PropertyName="Text" Expression="[Enrollment #]" />
</ExpressionBindings>
```

- `EventName`: `BeforePrint` (default; row data available) or `PrintOnPage` (page data available;
  only in the ExpressionsAdvanced binding mode, exposes `[Arguments.PageIndex]`, `[Arguments.PageCount]`).
- `PropertyName`: any bindable property; nested with a dot (`Font.Bold`).
- `Expression`: XML-attribute-escaped (`&lt;`, `&gt;`, `&quot;`, `&amp;`, `&#xA;` for newlines). Unescape
  before parsing.
- Legacy alternative `<DataBindings><ItemN PropertyName="Text" DataMember="Query.Field" FormatString=.../></DataBindings>`
  appears only in reports built in the `Bindings` data-binding mode. Absent in the observed file.
- `TextFormatString="{0:M/d/yyyy}"` on the control formats the bound value. Standard .NET format
  specifiers. A malformed pattern is **not** rejected at load time; it renders literally or garbles the
  value. Observed defects: `{{0:MM/dd/yy}` and `{0{0:MM/dd/yy}` on two date cells.

### II.7 Data source (`ComponentStorage`)

```xml
<ComponentStorage>
  <Item1 Ref="0" ObjectType="DevExpress.DataAccess.Sql.SqlDataSource,DevExpress.DataAccess.v25.2"
         Name="Reporting_Data1" Base64="PFNxbERhdGFTb3VyY2Ug..." />
</ComponentStorage>
```

Decode `Base64` (UTF-8, may itself carry a BOM) and you get the `SqlDataSource` XML:

```xml
<SqlDataSource Name="Reporting_Data1">
  <Connection Name="DefaultTestReporting" ConnectionString="XpoProvider=...;Server=tcp:...;Initial Catalog=...;Authentication=&quot;Active Directory Default&quot;;" />
  <Query Type="SelectQuery" Name="SDGE_400_Accounts">
    <Tables><Table Name="reporting.SDGE_Whole_Home_400_Account" /></Tables>
    <Columns>
      <Column Table="reporting.SDGE_Whole_Home_400_Account" Name="AccountFullName" Alias="Account Full Name" />
      ...
    </Columns>
    <Sorting><Column ... /></Sorting>
  </Query>
  ... four more Query elements ...
  <Relation Master="SDGE_400_Accounts" Detail="SDGE_410_Enrollments">
    <KeyColumn Master="Enrollment #" Detail="Enrollment Number (410)" />
  </Relation>
  ...
  <ResultSchema>
    <DataSet Name="Reporting_Data1">
      <View Name="SDGE_400_Accounts">
        <Field Name="Account Full Name" Type="String" />
        <Field Name="Canceled Date" Type="Unknown" />
        <Field Name="Id" Type="Guid" />
        ...
      </View>
    </DataSet>
  </ResultSchema>
  <ConnectionOptions ... />
</SqlDataSource>
```

What each part means:

- **`Connection`**. By DevExpress default only the connection `Name` is stored and the application
  resolves it from its own config (`StoreConnectionNameOnly=true`). Observed: the full
  `ConnectionString` with server and database **is** embedded. Credentials are not (Active Directory
  auth), but the file still names the production host. Treat the decoded blob as sensitive.
- **`Query`**. `Type` is `SelectQuery`, `CustomSqlQuery` (raw `<Sql>` text; SELECT-only by default
  unless `DisableCustomQueryValidation`), `StoredProcQuery`, or `TableQuery`. A `SelectQuery` has
  `Tables`, `Columns` (each `Column` has `Table`, `Name`, optional `Alias`, or is an `ExpressionColumn`),
  optional joins between its own tables, `Filter` (translated to SQL `WHERE`), `GroupFilter`
  (`HAVING`), `Sorting`, `Top`/`Skip`/`Distinct`, and `Parameters` (`QueryParameter`, bindable to
  report parameters by expression). Every query in the corpus is a `SelectQuery`; none uses
  `ExpressionColumn`, `GroupFilter`, `Top`, or query parameters.
- **SQL-level joins live inside `Tables`**, not at the data-source level, and use a different element
  from master-detail relations:

  ```xml
  <Tables>
    <Table Name="reporting.Building_Electrification_Invoice" Alias="BE_Invoice_Query" />
    <Table Name="reporting.Building_Electrification_000_Program" />
    <Relation Type="RightOuter" Parent="BE_Invoice_Query" Nested="reporting.Building_Electrification_000_Program">
      <KeyColumn Parent="Contractor" Nested="Contractor" />
    </Relation>
  </Tables>
  ```

  `Type` is `Inner`, `LeftOuter`, or `RightOuter`. `Parent`/`Nested` name tables by `Alias` when one is
  set, else by full name, and `Column/@Table` uses the same qualifier. The same physical view can appear
  twice under two aliases (the SoCal PO report joins the Invoice view twice, once per contractor role).
  This becomes a real SQL `JOIN`; the master-detail `Relation` (below) does not.
- **Query `<Filter>`** is criteria syntax over **raw SQL column names qualified by table or alias**,
  never over report aliases:
  `[reporting.LIWP_FWHC_00_Account.LeadProgram] = 'Low-income Weatherization Program - 2022' And [reporting.LIWP_FWHC_00_Account.GGRF] = 'False'`.
  It is pushed to SQL, so it is the one filter that reduces rows before the aggregates see them.
  Comparing a Boolean column to the string `'False'` is accepted (observed) and relies on SQL coercion.
- **The name the report sees is the `Alias`** when present, else the column `Name`. Expressions and
  `ResultSchema` use that display name. This is the layer where `SQL column -> report field name`
  drifts (`AccountFullName` -> `Account Full Name`), and where a rename in the view silently breaks a
  binding.
- **`Relation`** (`MasterDetailInfo`). Master query, detail query, one or more `KeyColumn` pairs. The
  engine resolves it **client-side after fetching both result sets**, equivalent to a LEFT JOIN from
  master to detail. It is exposed to the report as a relation named `<Master><Detail>` (concatenated
  query names, no separator): `SDGE_400_AccountsSDGE_410_Enrollments`.
- **`ResultSchema`**. Cached column list and types per query, so the designer works offline. It is a
  snapshot; if the view changed since the last "Rebuild Result Schema" it is stale and the field list
  lies. `Type="Unknown"` is what the schema records for column types the data layer could not map.
  Observed: every date column in the SDGE views is `Unknown` (they are `datetimeoffset` in SQL). That is
  the origin of the offset-comparison failures in Part IV.

### II.8 Calculated fields

```xml
<CalculatedFields>
  <Item3 Ref="4" Name="_enrolled" DataMember="SDGE_400_Accounts"
         Expression="Iif(&#xD;&#xA;    (([Enrollment Status (400)] In ('Ready for Review', 'Enrolled', 'Invoiced') Or&#xD;&#xA;     Not(IsNullOrEmpty([SDGE_400_AccountsSDGE_410_Enrollments.Enrolled Date]))), 'Enrolled', 'Not Enrolled')" />
</CalculatedFields>
```

- `Name` is what expressions reference (`[_enrolled]`). `DisplayName` is designer-only.
- `DataMember` must name a query in the data source. A calc field bound to a nonexistent member
  evaluates to null everywhere and nothing warns. Two variants are also legal and observed: **no
  `DataMember` at all** (report-scope constants such as `ToFloat(32727480)` or
  `FormatString('{0:dddd, MMMM d, yyyy}', Today())`), and a **relation path**
  (`Master.MasterDetail`) that scopes the field to the detail rows. A relation-path `DataMember` whose
  relation no longer exists in the data source is the silent-null case in disguise (observed: six fields
  in the BE PO report).
- Calc fields on a **detail query** with no relation to the root (observed: the Program Dashboard binds
  fields to four detail queries and defines zero relations) work as whole-table totals and are read from
  the header as `[query.field]`. Nothing ties them to the current root row.
- `FieldType` is the declared result type. Omitted/`None` = infer. Forcing a type does a conversion at
  evaluation; the handoff notes record `Int32` producing wrong output on a field that returned strings
  (`LeadStatusSortOrder` above declares `Int32` while returning `'01'`..`'99'` strings, which is the same
  pattern).
- Calculated fields may reference other calculated fields but not themselves, directly or transitively.
  A cycle is a designer error ("recursive calculated property").
- They evaluate per row of their `DataMember`, before rendering, and can use aggregates and parameters.
  They cannot use `sum*` summary functions.
- A relation path in a calc field (`[SDGE_400_AccountsSDGE_410_Enrollments.Enrolled Date]`) reads the
  **first** detail row for the current master row. Multiple details collapse to one, silently.

### II.9 Styles

```xml
<StyleSheet>
  <Item2 Ref="138" Name="DetailCaption1" BorderStyle="Inset" Padding="6,6,0,0,96"
         Font="Arial, 8.25pt, style=Bold" ForeColor="White" BackColor="255,75,75,75"
         BorderColor="White" Sides="Left" StringFormat="Near;Center;0;None;Character;Default"
         TextAlignment="MiddleLeft" BorderWidthSerializable="2" />
</StyleSheet>
```

Colors are `A,R,G,B` or a named color. `Padding` is `left,right,top,bottom,dpi`. `Sides` lists which
borders draw. Styles are the source of "house style"; when auditing formatting drift, compare each
control's explicit attributes against its style and the `StylePriority` overrides.

### II.10 Other top-level sections that may appear

| Section | Shape | Present in corpus |
|---|---|---|
| `Parameters` | `<Item1 Ref="3" Visible="false" Description="..." ValueInfo="2025-10-01" Name="AverageCutoffDate" Type="#Ref-2"/>` where `Type` points at an `ObjectStorage` item `<Item1 ObjectType="...ObjectStorageInfo..." Ref="2" Content="System.DateOnly" Type="System.Type"/>`; `ParameterPanelLayoutItems` lists `<Item1 LayoutItemType="Parameter" Parameter="#Ref-3"/>`. `ValueInfo` is the invariant string form of the value. | two PO reports, and in both the parameter is referenced by nothing (the cutoff is hard-coded as `#2025-10-1#` instead) |
| `FormattingRuleSheet` | `<ItemN Ref= Name= Condition="[UnitPrice] >= 30" DataMember=...><Formatting .../></ItemN>`, referenced from controls via `FormattingRuleLinks` | no |
| `ScriptsSource`, `ScriptLanguage` | full script text, escaped; per-control `<Scripts OnBeforePrint="method"/>` | no |
| `XRChart` under a band | `Series` (`ArgumentDataMember`, `ValueDataMembersSerializable`, per-series `FilterString`) or `SeriesTemplate` + `SeriesDataMember` (one series per distinct value; **one shared filter**) | no |
| `XRSubreport` | `ReportSourceUrl` (path or provider name, takes precedence) or embedded `ReportSource`; `ParameterBindings` map master fields to sub-report parameters | no |
| `XRPageInfo` | `PageInfo="DateTime"` or `TextFormatString="Page {0} of {1}"` (page number is the default `PageInfo`) | CPUC demographics |

---

## Part III. The expression language

Used identically in `Expression` attributes, calculated fields, `FilterString`, formatting-rule
`Condition`, and query filters (the last is translated to SQL; the rest evaluate in memory).

### III.1 Operands

| Kind | Syntax | Notes |
|---|---|---|
| Field | `[Enrollment #]` | Display name (alias) from the data member. Spaces and punctuation allowed inside brackets. |
| Field on a relation | `[SDGE_400_AccountsSDGE_410_Enrollments.Enrolled Date]` | `<Master><Detail>.<Field>`. First matching detail row. |
| Field qualified by member | `[Query.Field]` | Explicit member; needed when a control sits in a band bound to a different member. Mixing `[Field]` and `[Member.Field]` for the same field in one report is legal but has been a defect source. |
| Calculated field | `[_enrolled]` | Same syntax as a data field. |
| Parameter | `?ParamName` | Legacy `[Parameters.ParamName]` still parses. Multi-value parameters go in `In (?p)`. |
| Report item | `[ReportItems.labelName.Text]` | Value of another control. Order of evaluation is not guaranteed. |
| String | `'text'`, `'O''Neil'` | Doubled apostrophe escapes. Byte-exact comparison: case, trailing space, em dash vs hyphen all matter. |
| Date/time | `#2026-09-03 13:18:51#` | `#!2026-09-03!#` for DateOnly. |
| Number | `1`, `1.5`, `25s`, `25b`, `1.0f`, `25.0m` | Suffix picks Int16/Byte/Single/Decimal. |
| Boolean | `True`, `False` | |
| Guid | `{513724e5-...}` | `=`/`<>` only. |
| Null | `null` or `?` as an operand | Prefer `IsNull([F])` / `IsNullOrEmpty([F])`. |
| Enum | `[Borders] = 'Left'` or `##Enum#Type,Member#` | Rare in report bodies. |
| Keyword as field | `[@Or]` | Escape with `@`. |
| Comment | `/* ... */` | |

### III.2 Operators, highest precedence first

1. `()` grouping, `[]` field
2. Unary: `Not`/`!`, unary `-`/`+`
3. `*`, `/`, `%`
4. `+`, `-`
5. `<`, `>`, `<=`, `>=`, `=`/`==`, `<>`/`!=`, `In (...)`, `Between (a, b)`, `Like`, `Is Null`, `Is Not Null`
6. `And`/`&&`
7. `Or`/`||`
8. Bitwise `&`, `|`, `^`, `~`

`And` binds tighter than `Or`. `A Or B And C` means `A Or (B And C)`. Parenthesize every `Or` group
when rewriting a filter. Integer `/` truncates.

### III.3 Null semantics

The evaluator follows SQL three-valued logic. `[F] = 'x'`, `[F] <> 'x'`, `[F] < 5` all yield *unknown*
when `[F]` is null, and *unknown* is treated as false by `Iif`, `FilterString`, and `Visible`.

Practical rules:

- `[F] <> 'x'` **drops** null rows. Write `IsNullOrEmpty([F]) Or [F] <> 'x'` when nulls should pass.
- `Not([F] = 'x')` is the same trap; `Not(unknown)` is unknown.
- `IsNull([F])` returns true/false. `IsNull([F], fallback)` is coalesce. `IsNullOrEmpty([S])` also catches
  the empty string, which `IsNull` does not.
- Documented quirk: comparing `0` with null evaluates to true.
- A reference to a field that does not exist does not error. It evaluates to null, and every expression
  built on it goes null. This is the single most expensive failure mode: a one-character name drift
  (`[Aging_Start_c]` vs `[Aging_Start]`) produces blank columns with no diagnostic.

### III.4 Aggregates

`[<Collection>][<Condition>].<Func>(<Expression>)`

- `[]` as the collection = the current data member (all its rows, at data-source level).
- `[RelationName]` as the collection = the detail rows of the current master row.
- The condition is optional: `[][].Sum([Amount])`, `[][[Status] = 'Paid'].Count()`.
- Inside the condition, `^.Field` refers to the **outer** row: `[][[CategoryID] = ^.[CategoryID]].Sum([Revenue])`
  is a per-group total computed from the row level.
- Functions: `Sum`, `Count`, `Avg`, `Min`, `Max`, `Exists`, `Single`, `Join(expr[, sep])`.
- Aggregates are not affected by the report `FilterString` (they run on the source rows).
- The pattern that works for a grand total in a calculated field is a **separate** calc field
  `[][].Sum([Field])` bound to a cell; inline `[Member.Field].Sum()` inside another expression does not.

### III.5 Summary functions (`sum*`)

Only in the `Text` expression of a label/cell. Scope = `Summary.Running` (Report/Group/Page) crossed with
the band the control is in: a `sumSum` in a Group Footer with `Running=Group` is the group total; in the
Report Footer with `Running=Report` it is the grand total; anywhere else with `Running=Group` it renders
`?`. Functions: `sumSum`, `sumCount`, `sumAvg`, `sumMin`, `sumMax`, `sumRunningSum`, `sumCarryoverSum`,
`sumPercentage`, `sumRecordNumber`, `sumMedian`, `sumStdDev(P)`, `sumVar(P)`, `sumWAvg`, and the `sumD*`
distinct variants. Evaluated after rendering, so they see the filtered, sorted rows.

### III.6 Functions worth knowing for report audits

Date: `Today()`, `Now()`, `UtcNow()` return **DateTimeOffset**. `LocalDateTimeToday()`,
`LocalDateTimeThisWeek()`, `LocalDateTimeThisMonth()`, ... return plain `DateTime` at 00:00. `GetDate(d)`
strips time (offset preserved on offset values). `GetDayOfWeek(d)` returns the `DayOfWeek` enum value
(Sunday = 0). `AddDays/Months/Years`, `DateDiffDay/Month/Year` count **boundaries** crossed, not elapsed
spans. `InDateRange(d, from, to)` is `from <= d < to`. `IsThisWeek(d)`, `IsThisMonth(d)`, `IsLastMonth(d)`,
`IsYearToDate(d)`.

Logical: `Iif(c1, v1, c2, v2, ..., else)` (multi-branch form exists), `IsNull`, `IsNullOrEmpty`,
`InRange`.

String: `Upper`, `Lower`, `Trim`, `Len`, `Substring`, `Replace`, `Contains`, `StartsWith`, `EndsWith`,
`CharIndex`, `PadLeft/Right`, `Concat`, `ToStr`, `FormatString('{0:c2}', v)`.

Math: `Round`, `Floor`, `Ceiling`, `Abs`, `ToInt`, `ToDecimal`, `ToDouble`, `Max(a,b)`, `Min(a,b)`.

Reporting: `Rgb`, `Argb`, `CurrentRowIndexInGroup()`, `GroupIndex(level)`, `PrevRowColumnValue(col)`,
`NextRowColumnValue(col)`, `GetDisplayText(?p)`, `Join(?multiValueParam[, sep])`, `NewLine()`.

Unregistered custom functions evaluate to empty, not error.

---

## Part IV. Known failure patterns

Compiled from the DevExpress docs plus the reporting handoff notes. Each is something a static audit can
detect from the file alone.

| # | Pattern | Symptom | Detection | Fix |
|---|---|---|---|---|
| 1 | `datetimeoffset` column compared to an inline function (`[D] >= AddDays(Today(), -7)`, `IsThisWeek([D])`) | Whole comparison unknown; rows vanish | Column is `Type="Unknown"` in `ResultSchema` **and** appears in a comparison with `Today()`/`Now()`/`AddDays(...)` | Compute the boundary in its own calc field (`WeekStart = AddDays(Today(), -GetDayOfWeek(Today()))`) and compare field-to-field. `Min`/`Max` on the raw column work (they sort, not compare). |
| 2 | `[F] <> 'x'` or `Not([F] = 'x')` without a null guard | Null rows silently excluded | Regex on `FilterString` and `Condition`s | `IsNullOrEmpty([F]) Or [F] <> 'x'` |
| 3 | `Iif(cond, date, 0)` inside `Min`/`Max` | `0` becomes 1899-12-30 and wins the `Min` | `Iif(` with numeric else-branch inside an aggregate over dates | Else-branch must be `null` |
| 4 | `Or` group not parenthesized next to `And` | Filter admits unintended rows | Parse the expression tree | Add parentheses |
| 5 | Field name drift (`[Aging_Start_c]` vs `[Aging_Start]`) | Null column, no error | Every `[name]` must resolve to a `ResultSchema` field, a calc field `Name`, a relation path, or `?param` | Rename |
| 6 | Wrong `DataMember` on a calc field | Every use is null | `DataMember` not in the set of `Query/@Name` | Rebind |
| 7 | Relation path from a master band where the detail has several rows | Shows first row only; nothing duplicated or summed | Any `[MasterDetail.Field]` outside a `DetailReportBand` | Use a `DetailReportBand` or an aggregate `[MasterDetail][].Sum(...)` |
| 8 | Relation defined but never referenced | Dead join; harmless but misleading | Relation name absent from every expression and `DataMember` | Remove or document (observed: the Invoice relation) |
| 9 | Malformed `TextFormatString` (`{{0:...}`, `{0{0:...}`) | Literal braces or unformatted value in output | Brace balance / regex `^\{0(:[^}]*)?\}$` | Fix pattern (observed: two cells) |
| 10 | Duplicate `Ref` | Loader binds wrong object | Count refs | Renumber |
| 11 | Recursive calc field | Designer error | Dependency graph cycle over `[name]` refs among calc fields | Substitute the source column |
| 12 | Literal mismatch with stored values (`'Completed & Ready for Review'` vs `'Ready for Review'`, trailing period, em dash) | Condition never true | Compare every string literal against the platform's option `Value` list from `docs/field-index.json` | Correct the literal |
| 13 | `FieldType` forced on a calc field whose expression returns another type | Wrong or blank values | `FieldType` present and expression's literal branches disagree with it | Set to `None` or convert explicitly |
| 14 | `SeriesTemplate` chart with per-series filtering intended | All auto-series share one filter | `SeriesDataMember` set and more than one filter intended | Declare `Series` statically |
| 15 | Report-level `FilterString` on a large view | Whole view fetched then filtered client-side | `FilterString` on root or band while the query has no `Filter` | Push the predicate into the query `Filter` |
| 16 | Stale `ResultSchema` | Designer field list disagrees with the live view; bindings to removed columns go null | Compare schema field names against the platform form's field API names (they are one-to-one for the `reporting.*` views) | Rebuild result schema |
| 17 | **Option Key vs Value drift.** A picklist's `Key` and `Value` differ (`Bid Proposed` / `Ready for Review`; `Ready for Review` / `Completed & Ready for Review`; `Ready for Review` / `Completed & Submitted`) and the SQL view holds **both** strings, older rows under the Key and newer rows under the Value | A condition on one string silently drops the other population. Verified in the SDGE export: 181 rows `Bid Proposed` vs 13 rows `Ready for Review` in the same column | Literal matches a Key but not a Value (or vice versa) in the platform option set | Test both strings, or migrate the stored data |
| 18 | Literal matches neither Key nor Value (`Bid Approved—Pending Savings`, `Enrollment Approved`, `''` against a picklist) | Branch never fires | Literal not in Key set or Value set | Correct or delete |
| 19 | Calc field referenced but never defined (`[calculatedField119]`, `[Total_Allocated_Region_B_SPV]`) | Null, propagates | Bracket ref resolves to nothing | Define or rename |
| 20 | Column exposed under its API name but referenced by a friendly name (`[Clone Project]` vs `ClonedProjectCheckbox`, `[ReviewStatus]` vs `Review Status (315)`) | Null in every dependent expression | Same as 5; distinguish from 5 by whether an unaliased column with a similar API name exists | Add the alias or fix the reference |
| 21 | Hard-coded program constants in calc fields (`ToFloat(32727480)`, `[x] * 14000`, `#2025-10-1#`, contractor name lists in query filters) | Silently stale when the budget, rate, or roster changes | Numeric/date literal in a calc field with no `DataMember`; string list in a query `Filter` | Move to a parameter or a lookup view |
| 22 | Cross-tab `DataFields` entry summed when it is already a ratio | Wrong subtotal | `SummaryType` absent on a field whose expression divides | Set `SummaryType="Average"` or sum numerator and denominator separately |
| 23 | `SortFields` naming the same field twice, or a field that does not resolve | Second entry ignored; unresolved entry sorts as absent | Duplicate `FieldName` in the collection | Clean up |

Pattern 12 is where this repo's inventory earns its keep: the option-set values published in
`field-index.json` are the exact strings the SQL views carry, so every string literal in a report
expression can be checked against them offline.

---

## Part V. Reading a layout, step by step

1. Read the file as `utf-8-sig`. Parse with an XML parser for structure; keep the raw text for edits.
2. Root attributes: `DataMember` (driving query), `DataSource` (`#Ref-N`), `ReportUnit`, page size.
3. `ComponentStorage/ItemN[@Ref=N]/@Base64` → decode → `SqlDataSource` XML. Build:
   - queries: name → (table, [(column, alias)], filter, sorting)
   - relations: `<Master><Detail>` → key pairs
   - schema: query → {alias → type}
4. `CalculatedFields`: name → (DataMember, Expression, FieldType). Unescape expressions.
5. Walk `Bands` recursively. For each band note type, `DataMember` (relation path on detail reports),
   `GroupFields`, `SortFields`, `FilterString`.
6. Walk controls. For each `ExpressionBindings/ItemN` record (control name, band, property, expression).
   For table cells also record row, weight, `StyleName`, `TextFormatString`.
7. Tokenize every expression: bracket refs, `?params`, string literals, function names. Resolve each
   bracket ref against schema aliases, calc field names, relation paths. Unresolved = finding.
8. Cross-check literals against option sets; check pattern list in Part IV.
9. Produce the column map: for every detail-band cell, `column caption (from the header row cell at the
   same index) → expression → underlying SQL columns → platform form field(s)`.

Editing rule of thumb: patch the raw text anchored on `Ref="N"`, never round-trip through an XML
library (it reorders attributes and rewrites escapes, making the diff unreviewable). After a patch:
parse to confirm well-formedness, re-count refs, re-count `ItemN` contiguity per collection.

---

## Part VI. How this maps onto the platform inventory

For the SDGE report the mapping is direct: each `SelectQuery` reads one `reporting.SDGE_Whole_Home_*`
view, each view column name equals a form field API name, and the four relations are all
`Enrollment # (400) = EnrollmentNumber (410/415/425/Invoice)`. So:

- A report column is a **read** of a platform field, the same class of fact the inventory already records
  for workflow conditions and formulas. "Where is this field used?" should include "column 7 of the SDGE
  weekly report".
- A calc field like `_enrolled` encodes business logic (`Enrollment Status In ('Ready for Review',
  'Enrolled', 'Invoiced') Or Enrolled Date is set`) that may or may not agree with the platform's own
  Stage/Status formulas on form 400. Both sides are decodable; the diff is the audit.
- Option values in report literals must match `field-index.json` `options` (the `Value` side).

The natural home for the decoder is a new `scripts/parse_rxml.py` producing the same kind of normalized
dict `parser.py` produces for forms, so the explorer, the field index, and snapshot compare can consume
report facts without special-casing.

---

## Part VII. The corpus (as of 2026-09-03)

Eleven distinct layouts under `docs/reporting/` (a twelfth is a byte-identical duplicate). All share one
`SqlDataSource` named `Reporting_Data1` (`Reporting_Data2` in one), the same connection, and the same
`reporting.*` view family. Every view column name matched a platform form field API name except the
system columns (`Id`, `CreationTime`, `LastModificationTime`, `TenantId`, `ParentId`, `TopLevelId`) and
four view-side computed columns (`ProjectName_5`, `ProjectNumber`, `Auto_ProjectNumber`,
`MeasureExternalId_Text`).

| Report | Root member | Shape | Queries / joins / MD relations | Calc fields | What it taught |
|---|---|---|---|---|---|
| (01) SDGE Weekly | SDGE 400 | flat listing, 38 cols | 5 / 0 / 4 | 4 | baseline format |
| (01) SoCal Weekly | SoCal 300 | flat listing, 27 cols, root filter | 4 / 0 / 3 | 7 | `GetDate`/`DateDiffDay` aging pattern on offset columns; duplicate sort fields |
| (01) BE Weekly | BE joined | flat listing | 3 / 2 / 2 | 1 | SQL joins inside a query; root filter with null guard |
| (CPUC) Demographics | SoCal 300 | flat listing, Inches | 1 / 0 / 3 (unused) | 2 | `ReportUnit=Inches`, `XRPageInfo`, 145-city `In()` lists |
| (00) Program Dashboard | SoCal 300 | header-only dashboard | 9 / 0 / 0 | 34 | bare aggregates on unrelated detail queries; `[query.calc]` reads |
| (02) Bi-weekly GF / GGRF | LIWP 00 | header+footer dashboard | 1 / 0 / 0, query filter | 178 / 190 | the `Sum(Iif(...))` matrix pattern; query-level filter; dead `[Clone Project]` |
| CARB General Funds / CARB Reporting | LIWP measures | flat listing | 4 / 0 / 3 | 15 | relation-path `DataMember`; exists-form root filter; 12 fields on a dead member |
| SDGE PO / BE PO / SoCal WHP (PO) | program | cross-tab | 1–2 / 1–2 / 0 | 8 / 33 / 17 | `XRCrossTab`, `Parameters`+`ObjectStorage`, no-member constants, hard-coded cutoffs |

Per-file findings from the corpus pass are in `reviews/rxml-corpus-audit-2026-09-03.md`. The `.rxml`
files themselves stay in `docs/reporting/`, which is gitignored: they embed the production connection
string and sit alongside customer-data exports, and `docs/` is the Pages publish target.

## Appendix. Source pages consulted

- XtraReport class: https://docs.devexpress.com/XtraReports/DevExpress.XtraReports.UI.XtraReport
- Store report layouts: https://docs.devexpress.com/XtraReports/2592/
- XML serialization: https://docs.devexpress.com/XtraReports/10011/
- Security considerations: https://docs.devexpress.com/XtraReports/119146/
- ComponentStorage: https://docs.devexpress.com/XtraReports/DevExpress.XtraReports.UI.XtraReport.ComponentStorage
- Manage data sources at runtime: https://docs.devexpress.com/XtraReports/403989/
- SqlDataSource, SelectQuery, CustomSqlQuery, MasterDetailInfo, DBSchema:
  https://docs.devexpress.com/CoreLibraries/DevExpress.DataAccess.Sql.SqlDataSource (and siblings)
- Banded reports: https://docs.devexpress.com/XtraReports/2587/
- DetailReportBand / master-detail: https://docs.devexpress.com/XtraReports/4785/
- GroupHeaderBand, DetailBand.SortFields, XtraReportBase.DataMember, XtraReportBase.FilterString
- Filter at report level / data-source level: https://docs.devexpress.com/XtraReports/4803/ , /4804/
- CalculatedField, calculated fields overview, aggregate in calc field:
  https://docs.devexpress.com/XtraReports/4813/ , /12441/
- Expression language: https://docs.devexpress.com/XtraReports/120104/
- Functions in expressions: https://docs.devexpress.com/XtraReports/403363/
- Criteria language syntax: https://docs.devexpress.com/CoreLibraries/4928/
- Null handling (XPO, same evaluator): https://docs.devexpress.com/XPO/5459/
- Summaries overview / calculate a summary / running summary:
  https://docs.devexpress.com/XtraReports/403729/ , /119436/ , /4816/
- XRSummary, SummaryFunc, DataBindingMode, ExpressionBinding, XRBinding
- XRTable, XRTableCell, XRLabel, XRControl, StylePriority, XRPageInfo, XRChart (+ series template /4575/),
  XRSubreport, FormattingRule, Parameters (/4812/), scripts overview (/2615/), ScriptsSource
