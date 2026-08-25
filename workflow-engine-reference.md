# IMPACT Workflow Engine — Working Reference

**Purpose.** Two halves. **Part I (§1–§10) is for *reading*** — what an exported workflow means,
which is what `scripts/parser.py` decodes. **Part II (§11) is for *writing*** — how to author a
workflow JSON the platform will import. They are different formats and the difference is load-bearing;
see §1.

**Sources.** Platform help export (`workflow_engine_help.txt`); five whole-workspace exports under
`data/` (314 forms, 115 workflows); six individual workflow exports; form design exports; and direct
observation of the workflow designer UI (2026-08).

**Precedence rule.** Where the help text and a production export disagree, **the export wins**. Where
an export and the designer UI disagree, **the UI wins** — the export shows what one workspace happens
to use, the UI shows what the product supports. The original Action Help page was written against a
planned surface and never revised.

---

# Part I — Reading an export

## 1. The two export shapes

The same workflow serializes **two different ways** depending on how you exported it. Confusing them
is the single most common authoring mistake.

| | whole-workspace export | individual workflow export |
|---|---|---|
| where | `data/<slug>/*.json`, under each form or a top-level `Workflows[]` | one file per workflow |
| enums | **integers** | **strings** |
| GUIDs | real platform IDs, resolve within the file | synthetic `RefId`s + an `ExternalReferences` block |
| importable | no | **yes** |

`Update Existing Measures` exists in both forms in this repo, which pins the mapping exactly:

| field | integer (workspace) | string (individual) |
|---|---|---|
| `WorkflowEngineTriggerType` | `1` | `FormResponse` |
| `WorkflowEngineDatabaseActionType` | `2` | `Update` |
| `WorkflowEngineDatabaseActionTiming` | `2` | `PostProcessing` |
| `WorkflowEngineConditionMode` | `1` | `Basic` |
| `WorkflowEngineFieldChangeMatchMode` | `0` | `Any` |
| parameter `ValueType` | `1` | `Static` |

Note `ConditionMode: "Basic"` is what the UI labels **Filter Builder** — the API value and the UI
label differ.

> **Not confirmed:** `WorkflowEngineTriggerType: 4` (2 uses, both `Update Records` in sce-be) and
> `WorkflowEngineDatabaseActionType: 4` (1 use). The designer offers exactly three trigger types, so
> `4` is not a fourth type — the enum is non-contiguous, or `4` is legacy. No individual export of
> either workflow exists to read the string off.

### Schema tree

```
Workspace
├─ Id, Name, DisplayName, Description, IsVisible, IsSystem, IconClass, MenuName
├─ Forms[]
├─ SecurityPolicy{}
└─ Workflows[]
   ├─ SchemaVersion, Id, Name, Description, OwnerId, LayoutJson
   ├─ Permissions[]
   ├─ ExternalReferences[]        (individual exports only — see §11)
   ├─ Triggers[]
   │  └─ WorkflowEngineTriggerType, TargetEntityType,
   │     WorkflowEngineDatabaseActionType, WorkflowEngineDatabaseActionTiming,
   │     CronExpression, TimeZoneId, ExternalEventName,
   │     WorkflowEngineConditionMode, ConditionExpression,
   │     FormId, WorkspaceId, MonitoredFieldsJson,
   │     WorkflowEngineFieldChangeMatchMode, Dependencies[]
   └─ Steps[]
      ├─ Name, SortOrder, IsEntryStep, ExecutionMode,
      │  MaxRetries, RetryDelaySeconds, ConditionExpression
      ├─ OutgoingTransitions[]  → Id, SourceStepId, TargetStepId,
      │                           ConditionExpression, BranchName, SortOrder
      └─ Actions[]
         ├─ ActionType, DisplayName, SortOrder, ContinueOnError
         └─ Parameters[]
            └─ ParameterName, ValueType, StaticValue,
               DynamicSourceField, FormulaExpression,
               DataType, IsSecret, SortOrder
```

Workflows are **versioned** in the platform (the designer title bar shows `v15 · Enabled · Latest
version`), but the version number is **not carried in the export** — `SchemaVersion: 1` is the export
format version, not the workflow's. There is no way to tell from a file which revision it is.

---

## 2. Triggers

Three trigger types, matching the designer exactly: **Form Response**, **Scheduled**, **Manual**.
(The old Action Help page's EntityCreated / EntityUpdated / EntityDeleted / Webhook types do not
exist. Ignore them.)

### Form Response

**Event Type** — Create, Update, Create or Update, Delete. Serializes as
`WorkflowEngineDatabaseActionType`; `Update` = `2` is confirmed, the rest are inferred.

**Field-change scoping.** `MonitoredFieldsJson` restricts an Update trigger to named fields:

```json
["MAROMAReviewStatus","WorkflowTriggerCheckbox"]
```

The designer is explicit: *"Leave empty to trigger on any update to the form."* Set this on every
status-driven workflow — without it the workflow fires on every save. 15 of 20 sce-be triggers use it.

**Match Mode** — `WorkflowEngineFieldChangeMatchMode`: `Any` (`0`) = "Any field changes (OR)", trigger
if any monitored field is modified; the other option is "All fields change (AND)".

### Scheduled

The designer generates the cron for you. Observed panel:

```
Schedule Mode : Simple Builder          (implies a raw-cron mode as well)
Time Zone     : America/Los_Angeles (UTC-08:00)
                "wall-clock time is interpreted in this time zone.
                 DST transitions are handled automatically."
Frequency     : Daily
Time          : 09:00 AM
Generated Cron Expression : 0 9 * * *
```

So: **5-field cron**, `TimeZoneId` is an IANA zone, DST is handled by the platform. All three
condition modes (None / Filter Builder / Expression) remain available on a scheduled trigger.

> **Still unproven:** no scheduled workflow exists anywhere in `data/`. `CronExpression` is null in
> every export on file. The constraints in §13 (no trigger record ⇒ `FromTrigger` and `TriggerRecord`
> unavailable; Current User resolves empty) are reasoned, not observed. Prove the first one on a
> single form before rolling it out.

### Manual

Observed once (`Approved Measures`, LIWP). It still carries a vestigial
`WorkflowEngineDatabaseActionType` (`"Create"`) that is not semantically meaningful.

### Dependencies

A trigger can declare that another workflow must run first:

```json
"Dependencies": [
  { "PrerequisiteRootDefinitionId": "<RefId>", "OnFailureBehavior": "RunAnyway" }
]
```

with a matching `ExternalReferences` entry of `Type: "Workflow"` naming it. This is the mechanism for
sequencing two workflows that would otherwise race on the same field. **The inventory parser ignores
`Dependencies` entirely** — the explorer's write-conflict warning cannot see that a conflict has
already been resolved this way.

---

## 3. Conditions

`ConditionExpression` is **not** the text `FilterExpression` syntax the old Action Help page
advertises (`{{Priority}} == 'High' && ...`). That syntax does not exist. The real format is
serialized condition-builder JSON, **identical in both export shapes** (operators stay integers even
in the string-enum individual export).

```json
{
  "Operation": 1,
  "Expressions": [
    {
      "FormId": "...", "FormFieldId": "...",
      "FieldDataType": "Text", "Operation": 1, "Aggregation": 0,
      "ResponseFieldValue": { "Value": "Ready for Review", "type": "ConstantTermDto" },
      "ResponseFieldValueList": [],
      "type": "FormFieldComparisonExpressionDto"
    }
  ],
  "type": "GroupingDto"
}
```

**Node types:** `GroupingDto` (All/Any container), `FormFieldComparisonExpressionDto` (field vs value),
`ComparisonDto` (record member vs value, e.g. `LastModifierId`), `ConstantTermDto`, `MemberTermDto`,
`ContextTermDto` (an engine token such as `@FormResponseId`).

`FieldDataType: "Calculation"` is valid — **conditions can target computed fields.**

Groups nest, and each nested group carries its own All/Any. Step-level and transition-level
`ConditionExpression` use the same format. Grid-embedded conditions are base64-encoded in
`ExtraProperties` rather than plain JSON.

### Grouping operators — confirmed

| `Operation` | UI | meaning |
|---|---|---|
| `1` | All | AND |
| `2` | Any | OR |

### Comparison operators

The operator list is **per field type**. A Text field offers exactly: Is, Is Not, Is In, Not In,
Is Blank, Is Not Blank, Contains, Does Not Contain, Starts With, Ends With — **no ordering operators
at all**. Numeric and date fields offer a different set. The enum is therefore non-contiguous, and
dropdown position is *not* the enum value.

| code | n | operand shape | status |
|---|---|---|---|
| `1` | 106 | scalar | **Is** — confirmed in the designer |
| `2` | 2 | scalar | **Is Not** — confirmed |
| `6` | 7 | scalar, Text | ⚠ not decoded |
| `7` | 9 | scalar, Text | ⚠ not decoded |
| `9` | 3 | **list** (`ResponseFieldValueList`) | ⚠ not decoded — membership operator (Is In / Not In) |
| `10` | 1 | **list** | ⚠ not decoded — the other membership operator |
| `12` | 32 | **none** (27 of 32 carry no operand) | ⚠ not decoded — unary (Is Blank / Is Not Blank) |
| `15` | 1 | scalar, Date | ⚠ not decoded |
| `16` | 27 | **none** (24 of 27 carry no operand) | ⚠ not decoded — the other unary |

> **Note — four codes still need one designer lookup each.** The pairs are identified by operand
> arity but not distinguished within a pair, and guessing wrong on `12`/`16` would **invert the
> meaning of 59 conditions**. `parser.py` deliberately renders every undecoded code as `?` rather than
> a plausible symbol. To resolve one: open the workflow below, open that condition's operator
> dropdown, and read the highlighted row.
>
> | code | open | condition |
> |---|---|---|
> | `6` | liwp · *Desktop Review* | `ReviewStatus` = 'Enrollment Approved' |
> | `7` | sce-be · *Corrections Required - Final* | `InvoiceStatusSummary` = 'Pending Corrections' |
> | `12` | liwp · *Note Added by Inspector* | `NoteReply` |
> | `16` | liwp · *Review Notification (Operations)* | `ReviewerName_c` |
>
> A previous version of `parser.py` mapped `3/4/5/6` to `< <= > >=` on the assumption the enum
> followed the help text's list order. Those four appear **nowhere** in `data/`, while the six real
> codes were unmapped — and `6` rendered as `Review Status is at least 'Enrollment Approved'` on a
> Text field. Do not re-introduce a guess.

**Operand location matters.** Membership operators put their operands in `ResponseFieldValueList` and
leave the scalar `ResponseFieldValue` empty. Unary operators use neither — though a **stale value can
linger** from before the operator was switched (5 of 32 code-`12` nodes carry a leftover across
Text/Decimal/Date). Read the list first, then the scalar, and treat an absent scalar as unary.

### Choice values: use `Value`, never `Key`

A dropdown's `ExtraProperties.DataSourceValues` is a list of
`{Id, Key, Value, IsDefaultValue, SortOrder}`. **`Key` and `Value` can differ**, and everything that
matches a choice — trigger conditions, `TargetResolution` filters, Switch cases — matches **`Value`**.

```
ContractorSubmissionStatus:
   Key "Ready for Review"   →   Value "Completed & Ready for Review"     ← the engine matches this
```

Verified across the corpus: where the two differ, every disambiguating comparison matches `Value` and
none match `Key`. `Key` is never emitted anywhere. `docs/field-index.json` publishes the `Value` side
only, as an `options` array — 1,947 fields carry one. **Check it before writing any condition
literal.**

### Linked-record fields

From the filter dialog: *"This field stores a link. Use a record ID to match the linked record
itself, or a value to match the text displayed for it."* This is how forward target resolution works
(§6) — match the child's link field against `{{@FormResponseId}}`.

---

## 4. Node types: Action, Condition, Switch

The `+` between nodes offers three things, not one. Only **Action** appears anywhere in `data/`; the
other two are fully supported and simply unused so far.

### Action
A step that does something. See §5.

### Condition
A boolean gate with **True** and **False** branches, each accepting its own chain of steps. Card
shows `Expr — not set —` until configured.

### Switch
Multi-way branching.

```
Switch Source : ( ) Match on field        (•) Custom expression (advanced)
Switch Field  : Review Status
Cases         : MATCH WHEN VALUE EQUALS  |  BRANCH LABEL (OPTIONAL)
                [ Pending Review      ▾ ] [                        ]
                [ Corrections Required▾ ] [                        ]
                [ Enrollment Approved ▾ ] [                        ]
                + default branch (if no cases match)
```

Case values are drawn from the field's own option set — the `Value` side (§3). The card serializes
its source as a token (`{{MAROMAReviewStatus}}`). The schema's `OutgoingTransitions[].BranchName` is
this **Branch Label**.

> Earlier revisions of this document concluded from the data ("26 steps, 3 transitions, all
> unconditional") that branching effectively did not exist. That was a fact about *this corpus*, not
> about the product. **The parser models neither Condition nor Switch nodes and ignores
> `OutgoingTransitions` entirely** — the first branching workflow anyone builds will appear in the
> inventory as a flat list of actions with the branch structure silently dropped.

---

## 5. Actions

The full palette, read off the Action Type dropdown:

| group | action | in `data/`? |
|---|---|---|
| **Communication** | Send Email | 16 uses |
| | Send SMS | no |
| **Form Operations** | Create Form Response | yes |
| | Update Form Response | yes |
| | Upsert Form Response (Create or Update) | yes |
| | Delete Form Response | 2 uses |
| | Set Field(s) on Trigger | no |
| **Document Generation** | Generate PDF | 1 use |
| **Integration** | API Call | no |
| | WebHook | no |

**Genuinely absent from the product:** Human Approval, Assign User, Generate Report. Strike them.

> **Correction.** An earlier revision claimed `WorkflowVariables.*` was unreachable because
> `SwitchCondition` and `ApiCall` were absent. Both premises were wrong: **API Call is in the
> palette**, Switch is a node type rather than an action, and the PDF Attachments help states the
> email *"uses that generated output from workflow variables"* — so Generate PDF → Send Email already
> passes values through workflow variables.

`ContinueOnError` is per-action: *"the workflow will proceed to the next step even if this step fails.
When disabled, an error in this step will stop the workflow."*

### `BuiltIn.SendEmail`

| Parameter | DataType |
|---|---|
| `Recipients` | `recipients` |
| `CC` / `BCC` | `recipients` |
| `Subject` | `memo` |
| `Body` | `memo` (HTML) |
| `PdfAttachments` | `string` (JSON) |

```json
[{ "templateId": "<guid>", "fileName": "BEP-APPROVAL_{{UniqueIDNumber}}.PDF" }]
```

PDF attachments reference *"the same PDF type or template used by an earlier Generate PDF action."*
Filenames support token substitution.

### Form-operation actions

`FormId` (`form-picker`), `WorkspaceId`, `FieldAssignments` (JSON), `SubformOperations` (JSON),
`AutoMapMatchingFields` (boolean), and the `TargetResolution.*` family (§6).

**Match policy differs by action:**

| action | parameters |
|---|---|
| `UpdateFormResponse` | `MatchPolicy` — e.g. `Fail` ("Fail (error if multiple matches)") |
| `UpsertFormResponse` | `NoMatchPolicy` (`Create`) + `MultipleMatchPolicy` (`UpdateFirst`) |
| `CreateFormResponse` | `DuplicateMatchPolicy` (`Skip`) |

**Auto-map:** *"Automatically copy values from trigger form fields to target form fields when field
names match (case-insensitive). Manual field assignments below will override auto-mapped values."*

---

## 6. Target resolution — which record gets written

Three modes. Pick by **direction of travel**.

| direction | `TargetResolution.ResolutionType` | UI label | how the target is found | n |
|---|---|---|---|---|
| **forward** — trigger → a related record | `FilterBuilder` | Filter Query | filter the target's link field against the trigger's key or `{{@FormResponseId}}` | 6 |
| **backward** — child → its parent | `RelationshipField` | — | `TargetResolution.RelationshipFieldName` names the child's own link field | 5 |
| **same record** | `TriggerRecord` | Triggering Record | no `FormId`, no filter — acts on the record that fired | 3 |

Worked examples from `data/`:

```
forward     Update Existing Measures        210 → 255      filter: EnrollmentNumber = {{@FormResponseId}}
forward     Update Installation Contractor  300 → 315      filter: ESAKey = ESAKey
backward    Update Account Status from 415  415 → 400      RelationshipFieldName: EnrollmentNumber
same        Refresh Account                 400 → 400      (no target parameters at all)
```

`FilterBuilder` is the only option available on a scheduled trigger — there is no trigger record to
resolve from. (Reasoned, not observed; see §2.)

**Target Workspace is a first-class picker.** A workflow can write into a *different* workspace —
LIWP's `Create System Tracker Record` writes into "MAROMA Test". Such an export carries two
`Type: "Workspace"` references. The inventory has no model for cross-workspace targets and will show
the target as dangling.

---

## 7. ValueType and FieldAssignments

`FieldAssignments` is a JSON array on the action parameter of the same name:

```json
[
  { "FieldName": "UniqueIDNumber",    "ValueType": "TriggerRecordId", "Value": "" },
  { "FieldName": "PrimaryContractor", "ValueType": "FromTrigger",     "Value": "AssignedContractorOrganization" },
  { "FieldName": "EnrollmentStatus",  "ValueType": "Constant",        "Value": "Enrolled" },
  { "FieldName": "ReviewDate",        "ValueType": "Expression",      "Value": "{{@CurrentDateTime}}" },
  { "FieldName": "Reviewer",          "ValueType": "CurrentUser",     "Value": "" }
]
```

The designer offers four buttons per assignment: **Constant · Expression · From Trigger ·
Clear/Set Null**.

| ValueType | string | status |
|---|---|---|
| Constant | `Constant` | confirmed |
| From Trigger | `FromTrigger` | confirmed |
| Expression | `Expression` | confirmed — `Value` holds the expression text |
| Clear/Set Null | ? | ⚠ **unknown** — exists in the UI, used by no export on file |
| — | `TriggerRecordId` | confirmed |
| — | `CurrentUser` | confirmed |
| — | `CurrentOrganization` | observed |
| — | `FromSourceSubform` | confirmed (subform ops only) |

**Copying a computed field freezes it.** From the designer: *"Copying a computed (calculated) field
copies its value as it stands when this action runs — it won't update later if the calculation's
inputs change."* See §13 for why this matters.

`scripts/expand_field_assignments.py` generates this array from an Excel/CSV mapping, validating every
name against `docs/field-index.json`. It supports Constant, FromTrigger, and Expression; a
Clear/Set Null row is a hard error naming the row, because guessing the string would produce a
workflow that imports and then misbehaves silently.

### SubformOperations

```json
[{
  "SubformFieldName": "WorkOrderMeasures",
  "OperationType": "CopyRows",
  "SubformFormId": "<RefId>",
  "FieldAssignments": [
    { "FieldName": "MeasureType", "ValueType": "Constant",          "Value": "Installation" },
    { "FieldName": "MeasureQty",  "ValueType": "FromSourceSubform", "Value": "MIRQty" }
  ],
  "SourceSubformFieldName": "MeasureInstallationRequest",
  "SourceSubformFormId": "<RefId>",
  "AutoMapMatchingFields": false,
  "SourceFilter": "<double-escaped condition JSON>",
  "RowFilter": null,
  "MatchPolicy": "All"
}]
```

`OperationType` is `Add` (one op per row) or `CopyRows` (copy matching rows from a source subform).
`SourceFilter` is condition JSON **escaped twice** — it is a string inside a string.
`scripts/expand_subform_ops.py` generates `Add` ops from a CSV.

---

## 8. Email recipients

Mode is an **integer**, serialized into a `recipients`-typed `StaticValue`:

```json
[{ "mode": 1, "value": null, "organizationFilterId": null },
 { "mode": 4, "value": "ProjectContactEmail", "organizationFilterId": null }]
```

The designer enumerates the modes in enum order — *"Static (enter emails), Creator (form creator),
Current User, Role, Entity Field, or Specific Users"* — which confirms all six:

| Mode | Meaning | Value field | observed |
|---|---|---|---|
| `0` | Static Email | address, or `;`-separated list | 128 |
| `1` | Creator (form creator) | `null` | 17 |
| `2` | Current User | `null` | — |
| `3` | Role | role selector | — |
| `4` | Entity Field | field name **or bare system token** | 93 |
| `5` | Specific Users | user selector | — |

`organizationFilterId` is on every row, null in all observed cases.

**Entity Field accepts system tokens without braces** — `"value": "@LastModifier.Email"` is live in
production.

### Resolution behavior

- Each row resolves independently; a failed row is skipped with a warning, others still send.
- If no row produces a valid address, the send is skipped — the workflow does **not** fail.
- Addresses are deduplicated across rows and modes.
- Static Email does **not** resolve tokens — a `{{Token}}` there is sent literally and fails validation.
- `calc(...)` is not supported in recipient values.
- **Current User resolves empty on scheduled triggers.** Use Static, Entity Field, or Role.

---

## 9. Tokens

### Form fields

`{{FieldName}}` — case-insensitive. **Returns display text in Email and SMS bodies; returns the
underlying stored value everywhere else.** Use `.Text` explicitly whenever the label is what you want
outside a message body.

Typed accessors: `.Text` `.GuidValue` `.BooleanValue` `.DateTimeValue` `.IntValue` `.DecimalValue`
`.DateTimeOffsetValue` `.TimeSpanValue`

### Date and time

`{{@Today}}` `{{@Now}}` `{{@CurrentDate}}` `{{@CurrentDateTime}}` `{{@CurrentTime}}`
`{{@Year}}` `{{@Month}}` `{{@Day}}`
`{{@7DaysAgo}}` `{{@30DaysAgo}}` `{{@90DaysAgo}}` `{{@1YearAgo}}`
`{{@StartOfWeek}}` `{{@StartOfMonth}}` `{{@StartOfYear}}` `{{@TodayUtc}}` `{{@NowUtc}}`

Date math: `{{@Today±Nd}}` `{{@Today±Nw}}` `{{@Today±Nm}}` `{{@Today±Ny}}` `{{@Now±Nh}}`
`{{@Now±Nmin}}`, plus the `@CurrentDate` / `@CurrentDateTime` / `@TodayUtc` / `@NowUtc` variants.

Format: dates `MM/dd/yyyy`, times `h:mm tt`.

### Record and user

`{{@FormResponseId}}` `{{@FormId}}` `{{@FormName}}` `{{@WorkspaceId}}` `{{@WorkspaceName}}`

`{{@Creator.*}}` and `{{@LastModifier.*}}` — `.Id .Email .Name .UserName .FirstName .LastName .Phone
.OrganizationId`; Creator additionally has `.Title` and `.Department`. `{{@CurrentUser.*}}` — same set
as LastModifier. `{{@CreationTime}}` `{{@LastModificationTime}}`, each with `.Date` and `.Time`.

### System

`{{@TenantId}}` `{{@TenantName}}` `{{@ServerUrl}}` `{{@ResponseUrl}}` `{{@ResponseUrlLink}}`
`{{@ApplicationVersion}}` `{{@Environment}}` `{{@WorkflowInstanceId}}` `{{@ExecutionId}}`

### Lookup dot-notation

**Organization:** `.Name` `.Abbreviation` `.CustomerServiceNumber` `.Website` `.LicenseNumber`
`.Region` `.EmailAddress`
**Employee:** `.FullName` `.FirstName` `.LastName` `.Title` `.EmailAddress` `.PhoneNumber`
`.BadgeNumber` `.Organization.Name` `.ManagerEmployee.FullName`
**Program:** `.Name` `.ProgramStatus.Name`

### Null handling

An unresolvable token is replaced with an empty string. The workflow does not fail. Always give tokens
surrounding context so an empty value reads as blank rather than broken.

---

## 10. Expressions and `calc()`

These are **two layers**, not two competing syntaxes.

### The Expression layer

The outer language, used by `ValueType: "Expression"` and by Condition Mode → Expression. Per the
designer: *"Expressions support math (+,-,\*,/,%), logic (AND,OR,NOT,IN), and functions (ISNULL, LEN,
TRIM, CONVERT). Reference fields with `{{FieldName}}`."*

### `calc(...)` — the arithmetic marker inside it

Per the designer's Calc Expressions help:

> `calc(...)` lets you do arithmetic on token values inside any Expression parameter or field
> assignment. The marker tells the workflow engine to evaluate the contents as math instead of
> substituting them as text. Everything outside `calc(...)` is plain `{{Token}}` substitution. There
> is no function library — just operators (`+ - * / %`), parentheses for grouping, numeric literals,
> date math via DateTime ± days, and `{{Token}}` references that resolve to typed values.

Any `{{Token}}` that works elsewhere works inside `calc()`, resolved as its **typed** value — numeric
fields → decimal, date fields → DateTime, switch/checkbox → boolean.

**Dates:**

| Expression | Result |
|---|---|
| `DateTime + number` | adds days |
| `DateTime - number` | subtracts days |
| `DateTime - DateTime` | decimal days between |
| `DateTime + DateTime` | **null + warning** |

**Type preservation:** when the entire parameter value is one `calc(...)` block, the typed result is
assigned directly — DateTime stays DateTime, decimal stays decimal. Embedded in text, the result is
stringified (`MM/dd/yyyy` for dates, invariant-culture for numbers).

**Null propagation:** any null token inside `calc()` nulls the entire result. SQL semantics.

**Limits:** 4000-char body. Divide/modulo by zero → null + warning. Malformed syntax leaves the
original text intact and logs a warning — it does not crash the action or delete content. HTML tags
are stripped from the calc body before evaluation.

**Prefer the shortcut:** `{{@Today+7d}}` over `calc({{@Today}} + 7)`.

---

# Part II — Authoring

## 11. Writing an importable workflow

**Import works.** Field references are reconciled against the target workspace on import; mismatched
names must be fixed up by hand at that point.

### Use the individual-export shape

String enums throughout (§1). An integer where a string belongs is the most likely reason a
hand-built file misbehaves.

### The `ExternalReferences` contract

`RefId`s are **synthetic, export-local identifiers** — they are *not* the platform GUIDs you can read
out of a whole-workspace export or `docs/field-index.json`. Every `RefId` minted in one export shares
a batch suffix; the workspace export's real GUIDs use entirely different ones.

What matters is that they are **internally consistent**: the trigger's `FormId`, each action's
`FormId`, every `FormFieldId` inside a condition, and each `ExternalReferences[].RefId` must agree
within the file. The block then names what each one *is*:

| `Type` | carries |
|---|---|
| `Form` | `WorkspaceName`, `FormName` |
| `FormField` | `WorkspaceName`, `FormName`, `FieldName` |
| `Workspace` | `WorkspaceName` |
| `User` | `UserName`, `Email` |
| `Workflow` | `WorkflowName` (for `Dependencies`) |

**Safest path: clone a template.** Start from an existing export of a similar workflow and reuse its
`RefId`s, editing only names and parameters. Authoring wholly invented `RefId`s is untested.

> ⚠ `Type: "User"` entries carry real staff email addresses, and Static recipient rows (mode `0`)
> carry more. Redact before any export leaves internal hands.

### Checklist

1. **Pick the trigger.** Form Response + Event Type, or Scheduled + cron, or Manual.
2. **Scope it.** Set `MonitoredFieldsJson` on any Update trigger, or it fires on every save.
3. **Write the condition.** Condition-builder JSON (§3). Look every literal up in
   `docs/field-index.json` → `options` — use the `Value` side.
4. **Choose target resolution** by direction (§6).
5. **Assign fields.** `Constant` / `FromTrigger` / `Expression` (§7). Generate bulk arrays with
   `scripts/expand_field_assignments.py` rather than by hand.
6. **Set match policy** — the parameter name differs per action type (§5).
7. **Redact** recipient addresses and `Type: "User"` entries.
8. **Import, reconcile** any fields the platform flags, and export the result back into
   `data/<slug>/workflows/` so the inventory sees it.

### Worked example

*"When enrollment status is approved on the WHP enrollment form, email the contractor and stamp a
field on the 315 assessment."*

- **Trigger form** — `310 - Enrollment Intake`, Update. The field labelled "Enrollment Status" there is
  `EnrollmentSubmissionStatus`; note `300 - Account Management` has a *different* field literally named
  `EnrollmentStatus`, and `Invoice` has a third. Prior art (`Desktop Review`, `Review Notification
  (Operations)`) monitors `EnrollmentSubmissionStatus`, which settles it.
- **Monitored fields** — `["EnrollmentSubmissionStatus"]`.
- **Condition** — that field `Is` the approved option, spelled exactly as `field-index.json` lists it.
- **Target** — 310 and 315 do not link directly; both hang off `300` via `ESAKey`. So: forward
  resolution, `FilterBuilder`, filter `315.ESAKey = ESAKey`. `Update Installation Contractor for Form
  315` already does exactly this and is the file to clone.
- **Email** — a second step, `BuiltIn.SendEmail`, recipients mode `4` on the contractor address field.

---

# Part III — Form-side conventions

## 12. Form design (invoice v80)

### Census

191 nodes. ComponentTypes: Computed 41, TwoWideLayout 27, FormRelationshipReferenceDataInput 24,
DateInput 17, TextInput 11, StackedLayout 11, DropDownInput 8, NumberInput 8, FormSection 8,
TextAreaInput 6, FormGrid 5, OrganizationSelect 4, EmployeeSelect 4, UploadInput 4, ThreeWideLayout 4,
SwitchInput 3, FormPage 2, FormRelationshipInput 2, Header 1.

DataTypes: Text 43, Calculation 42, Date 15, Files 14, Decimal 9, Boolean 3, DateTime 3, Guid 2,
Integer 1.

### Review grids — newest-first

| Grid | Status column | Date column | Sort |
|---|---|---|---|
| `InvoiceDetails` | `StatusFinal` | `StatusDate` | `SortDirection: 2` (desc) |
| `DownPaymentReviewGrid` | `DownPaymentStatus` | `StatusDate_DP` | `SortDirection: 2` (desc) |

`grid[0]` is the current state. Individual approver fields retain stale values when new rows are added
above them — **always read the grid, never the flat field.**

### Option sets

`StatusFinal` and `DownPaymentStatus` share one vocabulary: Received (default), In Review, Pending
Corrections, Rejected, Corrections Submitted, Approved.

Option sets live in `ExtraProperties.DataSourceValues` and are published for every form into
`docs/field-index.json` as an `options` array — see §3 for the `Key` vs `Value` rule.

### Advanced configuration blocks

Each field carries up to four independent script hooks:

| Property | Function |
|---|---|
| `ValueAdvancedConfiguration` | `SetValue` |
| `HiddenAdvancedConfiguration` | `SetVisibility` |
| `EnabledAdvancedConfiguration` | `SetEnabled` |
| `RequiredAdvancedConfiguration` | `SetRequired` |

Each has `Configuration` (JS), `Expression` (base64 condition JSON — mutually exclusive with
`Configuration`), `ClearValueOnTrue`, `ClearValueOnFalse`, and a `Fields[]` dependency array of
`{ModelKey, FieldName}` declaring what the script reads.

`Required` / `Hidden` / `Enabled` are integer enums; `3` indicates an advanced-configuration hook is
attached.

### Existing date-counter pattern

`ThirtyDayPaymentCounter_Final` and `InvoiceDueDate_Final` both: read a stored Date field → guard
empty → `new Date(x)` → `setDate(getDate() + N)` → return `MM/DD/YYYY` **string**.

> String returns fail FilterBuilder date comparisons. Fine for display. Use ISO 8601 or a Date object
> for anything a workflow needs to filter on.

---

## 13. Design spec — 3-day correction timer

### Requirement

When an invoice is set to Pending Corrections, the contractor has 3 days to correct. After that
window, a re-dated invoice is required.

### Key insight

**No new stored start-date field is needed.** `InvoiceDetails` already records the correction start:
when `grid[0].StatusFinal == "Pending Corrections"`, `grid[0].StatusDate` is the clock start. Grid
rows are immutable history, so the value latches itself. No stamping workflow required.

### Stale vs. safe computed fields

A Calculation field goes stale **only if it reads the current date.** One derived purely from stored
inputs computes at save and stays correct indefinitely, because its inputs never change.

| Field | Inputs | Stale? | Filterable |
|---|---|---|---|
| `CorrectionsDueDate` | `grid[0].StatusDate` + 3 | No | **Yes** |
| `CorrectionDaysRemaining` | current date | Yes | **No — display only** |

```
CorrectionsDueDate       → grid[0].StatusFinal == "Pending Corrections"
                            ? ISO(grid[0].StatusDate + 3)
                            : null
CorrectionDaysRemaining  → ceil((CorrectionsDueDate - today) / 86400000)
                            negative = expired
```

Return `CorrectionsDueDate` as ISO 8601 or a Date object, **not** `MM/DD/YYYY`. This is the most
likely silent failure point in the build.

### Scheduled sweep

```
Trigger:  Scheduled
Schedule: Simple Builder → Daily → 02:00 AM   (generates 0 2 * * *)
TimeZone: America/Los_Angeles                 (DST handled by the platform)

Condition (Filter Builder):
  InvoiceStatusSummary   Is         "Pending Corrections"
  AND CorrectionsDueDate <before>   {{@Today}}          ← operator code not yet decoded (§3)

Action: BuiltIn.UpdateFormResponse
  TargetResolution.ResolutionType: FilterBuilder
  FieldAssignments: expiry flag
Then:   BuiltIn.SendEmail, recipient mode 4 (Entity Field) on contractor address
```

Constraints on scheduled triggers:
- No trigger record → `FromTrigger` and `TriggerRecord` both unavailable.
- Current User resolves empty → Static, Entity Field, or Role recipients only.
- **Nothing in `data/` uses `CronExpression` or `TimeZoneId`.** This would be the first scheduled
  workflow — prove it on one form before rolling it to the other invoice variants.

Optional day-2 reminder: same shape, filter `CorrectionsDueDate` equals `{{@Today+1d}}`.

### Enforcement

`Invoice_Final`'s existing `SetEnabled` already restricts contractor edits to `InvoiceStatusSummary`
in `["", "Pending Review", "Pending Corrections"]` — the edit window is already status-bound.

The stated requirement ("new invoice with an updated date") maps onto an existing field: when
`CorrectionDaysRemaining < 0`, require `InvoiceDate_Final` to be later than `grid[0].StatusDate`. This
forces a genuinely re-dated invoice rather than a status flip.

**Why not attachment-based enforcement:** `UploadInput` exposes no per-file timestamp (`Mode: 1`,
`DataType: Files`, no date property in the design export). Detecting a "new" attachment would require
a file-count comparison against a stored baseline. Avoid it — the date rule is cleaner and matches the
stated requirement.

### Flag / reminder

No popup action exists. The closest equivalent is a `Hidden`-conditioned HTML banner driven by
`CorrectionDaysRemaining`, rendering when the record is opened — which is when the contractor would
act anyway.

---

## 14. Open items

**Blocking a confident build:**

1. **Comparison operator codes `6`, `7`, `12`, `16`** — one designer lookup each (§3). `12`/`16` gate
   59 conditions and guessing inverts them.
2. **`Clear/Set Null` ValueType string** (§7) — build one assignment using it and export.
3. Does the expired invoice re-date in place, or spawn a new record? The form carries a single
   `InvoiceNumber_Final` / `InvoiceDate_Final` pair with the grid as history, which reads as in-place.
   If Finance needs the expired attempt preserved separately, the sweep becomes `CreateFormResponse` +
   `DuplicateMatchPolicy: Skip` + a lineage field — a different build.
4. Does the same 3-day rule apply to `DownPaymentStatus`?

**Verify before relying on:**

5. Trigger type `4` and database action `4` (§1) — no individual export of either workflow exists.
6. Whether Calculation-field values persist in a form the Filter Builder can query. The condition JSON
   accepts `FieldDataType: "Calculation"`, but persistence is untested here.
7. The scheduled-trigger constraints in §13 — reasoned from "there is no trigger record", not observed.

**Inventory gaps (this repo, not the platform):**

8. `Dependencies` is not parsed — workflow-to-workflow sequencing is invisible, including where it
   already resolves a flagged write conflict.
9. Condition and Switch nodes are not modelled; `OutgoingTransitions` is ignored. The first branching
   workflow will import fine and appear in the inventory as a flat action list.
10. Cross-workspace action targets have no model — the target shows as dangling.
11. Workflow version numbers are not in the export, so the version-history machinery that works for
    forms has nothing to key on.

**Documentation gaps:**

12. `parameter-types` and `formula-expressions` concept pages — cross-referenced in every Related
    Concepts footer, absent from the help export. §7 and §10 are the substitute.
