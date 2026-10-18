# Data contract with the Study Workspace

Life Desk reads (and in two places edits) plain Markdown tables in the workspace folder (Settings → Workspace).
A companion sync script (not part of this repo) reads the same files, so both must keep these formats.

| File | Table columns Life Desk needs | Notes |
|---|---|---|
| `resources/<course>/assignments.md` | `#`, `Title`, `Due`, `Status` (optional: `Task`, `Submission`, `File`) | first column is the row key; `Status` starting with `done` means finished |
| `resources/exam-dates.md` | `Course`, `Type`, `Date`, `Notes` | dates `YYYY-MM-DD`; words like tentative/unknown/not held mark an unconfirmed date |
| `resources/schedule.md` and lab `schedule.md` | `Date`, time, `Course`, room | ISO dates |
| `resources/sources.md` | one row per chat with a last-read date | drives the Sync page |
| `resources/<course>/course-info.md` | free text; first heading is the course title | |

## What Life Desk writes
- The `Status` cell of one `assignments.md` row (Done / Undo on Deadlines). Nothing else in the file changes.
- Files in `output/` and the four paths listed in `Sources/Core/AgentPolicy.swift`, only through the Agent page, with a snapshot and a revert button.

## Rules
- A row is matched to the bot's assignment by `"<#>: <title>"` (the same key the companion sync script sends).
- CRLF and LF files are both accepted. A row whose cell count differs from the header is never edited.
- Duplicate row keys in one file make the edit refuse (no guessing).
- Dates are read as calendar days in the Mac's time zone.
