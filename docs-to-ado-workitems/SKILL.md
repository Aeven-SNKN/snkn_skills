---
name: docs-to-ado-workitems
description: 'Extract structured content from a document (Word .docx, Markdown, plain text, PDF, Excel/CSV, or pasted outline) and create a matching work-item hierarchy in Azure DevOps Boards (Epic → Feature → User Story/PBI/Requirement → Task) with Story Points/Effort, tags, area paths and cross-links. Use when the user wants to turn a template, RFP, tender, spec, checklist, or requirements document into ADO work items, backlog items, epics/features/stories/tasks, or "create work items from this document".'
argument-hint: 'Path to the document + target ADO project/area path (and any tagging or story-point preferences)'
---

# Documents → Azure DevOps Work Items

Turn a structured document into a validated Azure DevOps work-item tree that mirrors
the document's own outline. The document's heading hierarchy becomes the work-item
hierarchy; the leaf prompts/requirements become Tasks.

## When to Use
- "Create ADO work items from this RFP / tender / spec / template / checklist."
- "Break this document into epics, features, stories and tasks."
- "Import this outline into Azure DevOps Boards with story points."

## Prerequisites
- Azure DevOps MCP tools available (the `wit_*` and `core_*` family), authenticated to the org.
- PowerShell (for `.docx` extraction). Other formats can be read directly.
- Check the workspace `AGENTS.md` for org conventions (e.g. required **project + area path**,
  "include estimated story points per user story"). Honor them.

## Procedure

### 1. Extract the document outline
- **.docx**: run [extract-docx-outline.ps1](./scripts/extract-docx-outline.ps1) with `-Path` and `-OutFile`,
  then read the output file. It labels paragraphs `[H1]/[H2]/[H3]` and list items `- `.
  ```powershell
  ./scripts/extract-docx-outline.ps1 -Path "<doc.docx>" -OutFile "<tmp>_outline.txt"
  ```
  Delete the temp file when done.
- **.md / .txt / pasted**: read directly; treat `#`/`##`/`###` (or numbered headings) as H1/H2/H3.
- **.pdf**: extract text first (e.g. `pdftotext -layout <in.pdf> <out.txt>` if available, otherwise a
  PowerShell/Python text-extraction step), then treat it like plain text. Infer levels from numbering
  and font/indentation cues; when the structure is unclear, confirm the intended hierarchy with the user.
- **.xlsx / .csv**: treat as a flat list where **each row is one work item**. Identify the columns for
  title, parent/grouping, description, estimate and tags; group rows by the parent/category column to
  form Features, and map each row to a Story or Task. Read `.xlsx` via the `Import-Excel` module or by
  unzipping `xl/worksheets/*.xml`; read `.csv` with `Import-Csv`.
- Capture: heading text + level (document order), list/table items under each heading, and the
  "please describe / requirement / deliverable" body prompts (these become Tasks).

### 2. Detect the ADO process BEFORE creating anything  ⚠️ critical
Do **not** assume Scrum. Call `wit_backlog` (action `list`) for the target team and read the
backlog levels to learn the exact **requirement-level work item type** and the **estimate field**:

| Process | Requirement WIT | Estimate field |
|---|---|---|
| Agile | `User Story` | `Microsoft.VSTS.Scheduling.StoryPoints` |
| Scrum | `Product Backlog Item` | `Microsoft.VSTS.Scheduling.Effort` |
| CMMI | `Requirement` | `Microsoft.VSTS.Scheduling.Size` |
| Basic | `Issue` (only 3 levels: Epic→Issue→Task) | — |

Creating a `Product Backlog Item` in an Agile project fails with `VS402323`. The backlog-levels
response also confirms the estimate field shown in the "Stories" column.

### 3. Choose the hierarchy shape per document, and explain the choice
There is no fixed default — inspect the document and pick the shape that fits, then state which you
chose and why before creating anything.

- **Multi-Epic (H1 = Epic):** use when the doc has several distinct top-level categories/domains that
  each warrant their own epic. Mapping: H1→Epic, H2→Feature, H3→Story, body prompt→Task.
- **Single-Epic (doc = one Epic):** use for one self-contained deliverable, catalogue, or appendix
  where the top sections are peers. Mapping: doc→Epic, each top section→Feature, sub-sections→Story,
  body prompt→Task. Keeps the top-level epic count sane.

Base requirement-level type on step 2 (User Story / PBI / Requirement / Issue).

Rule of thumb: if H1=Epic would create more than a handful of epics for a single document, prefer the
Single-Epic shape. Briefly tell the user which shape you picked and the reason.

Notes:
- Sections with one prompt can stay atomic at the Story level; only decompose into Tasks when a
  section genuinely has multiple sub-parts.
- Flag appendices/attachments (e.g. "bilag", "Statement of Work") with a tag and a produce-the-doc Task.

### 4. Create top-down
- **Epic**: `wit_work_item_write` action `create` (set Title, `System.AreaPath`, Description, Tags).
- **Features / Stories / Tasks**: `wit_work_item_write` action `add_child` under the parent
  (`workItemType` per level). `add_child` auto-parents and accepts `areaPath` per child.
- Pass the **area path** from `AGENTS.md` (e.g. `Project\Area`) on every item.

### 5. Retrieve the created IDs  ⚠️ parallel creation is not ordered
`add_child` batches (and parallel calls) do **not** return items in request order, and large
results are written to a file. After creating a level, run a `wit_query` WIQL for that type/id-range,
then `wit_work_item` action `get_batch` with fields `System.Id, System.Title, System.Parent` to build
an accurate id → (parent, title) map. Do this before setting fields or adding the next level.

### 6. Set estimates + tags in bulk
`add_child` cannot set Story Points/Effort or Tags. After stories exist, use `wit_work_item_write`
action `update_batch` with one op per field:
```json
[{"id":123,"op":"Add","path":"/fields/Microsoft.VSTS.Scheduling.StoryPoints","value":5},
 {"id":123,"op":"Add","path":"/fields/System.Tags","value":"RFP; <category>"}]
```
Use the estimate field from step 2. Tags are semicolon-separated; ADO stores them sorted.

### 7. Optional finishing touches
- **Cross-link** related items: `wit_work_item_link_write` action `link`, `linkType` `related`.
- **Iterations/owners**: set `System.IterationPath` / `System.AssignedTo` if the user wants sprints/SMEs.
- Confirm with a final WIQL count and a short tree summary.

## Story-point heuristic (first pass)
Scale by prompt count / complexity, e.g. 1 prompt → 2–3, 2–3 prompts → 5, big/appendix → 8.
State clearly they are estimates for a planning-poker pass.

## Gotchas (learned)
- **Detect process first** — never hardcode `Product Backlog Item` / `Story Points`.
- **Re-query IDs** after every create round; don't trust creation order.
- **`update_batch`** for points/tags; `add_child` only sets Title/Description/Area/Iteration.
- **Temp files**: delete the extracted-outline file after reading it.
- **Honor `AGENTS.md`** conventions (area path, story-points requirement) without being reminded.
