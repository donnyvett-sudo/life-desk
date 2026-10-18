# Life Desk — design contract

Job of the app: open it, see in 5 seconds what is due, what is next today and whether anything changed in the chats; then act (mark done, read a course, ask the agent, run sync). It is operated and scanned, not read top to bottom.

## Principles
1. **Summary first, detail below.** Every page opens with one line that answers its question (“2 overdue · 3 due this week”), then the list.
2. **State is shown in form, not colour alone.** Overdue = red chip with the word; today = accent chip; done = struck-through and dimmed; offline = labelled.
3. **One surface level.** Content sits on the window background. A card (surface + 1 px line) is used only for a group of related rows or one standalone object. No cards inside cards, no shadows.
4. **Real data, never placeholders.** Every number comes from the files or the bot; if there is nothing, an empty state says what will appear and how to fill it.
5. **Everything clickable looks clickable and has a hover state;** rows open their detail, chips filter, icons have tooltips; keyboard focus is visible.

## Tokens (same family as the bot's Mini App, light + dark)
| Token | Dark | Light |
|---|---|---|
| bg (window) | #151411 | #f6f3ec |
| sidebar | #1b1915 | #efe9dd |
| surface | #1e1c18 | #fffdf8 |
| surface2 (hover/selected) | #27241f | #efe8db |
| line | #2f2c26 | #e4ddd0 |
| text | #ece6da | #1f1d1a |
| muted | #968d7f | #6f685c |
| accent (coral) | #d9785a | #a34a30 |
| good / warn / bad | #82b98d / #d9a24f / #e0715a | #37703f / #8f5c10 / #a83a28 |

Course colours (8, fixed per course, used only as a 8 px dot + course name; never as card fills): see `Theme.course`.

## Type (SF Pro + New York serif for titles/numbers)
| Role | Spec |
|---|---|
| Page title | serif 28 semibold |
| Section label | 11 semibold, uppercase, tracking 0.6, muted |
| Row title | 14 medium |
| Body / detail | 13 regular, secondary text 12 muted |
| Chips | 11 medium |
| Numbers (dates, counts, times) | monospaced digits |

## Spacing and shape
Scale 4 · 8 · 12 · 16 · 24 · 32. Content column max 780 pt centred, page padding 28. Radius: 10 cards, 6 chips/buttons, full for dots. Row height ≥ 40 pt; hairline dividers between rows.

## Shell
- Sidebar 208 pt: two groups, “Study Workspace” and “Life”. Row = icon + label + optional count badge; selected = surface2 fill + accent icon (no system pink). Badges: Deadlines = overdue count (red), Notices = new count (accent).
- Window title hidden; page title lives in the page.

## Pages
| Page | Question it answers | Layout | Must work |
|---|---|---|---|
| **Today** | What do I do now? | Summary strip (Overdue · Due in 7 days · Next exam in N d) → “Today” agenda (time column + title + course + room) → “Due soon” (top 6, click → Deadlines with that row open) → “Exams” → “New in chats” (5) | all rows click through; “Mark done” inline; bot offline note |
| **Deadlines** | What is due and when? | Header filters (course chips + search) → groups Overdue / This week / Later / No date, exams block at the end of each time group with a “Exam” chip → completed hidden behind a toggle | Done / Undo (file + bot), expand row, filter, search |
| **Courses** | What does each course need from me? | List (left, 260 pt) of courses with dot, name, open count; detail (right): header with AI-policy chip, tabs Overview · Assignments · Files · Facts | tabs, Quick Look (Space), open/reveal files, policy banner for courses with a rule |
| **Notices** | What did the teachers say? | Day-grouped timeline, course dot + text + source; “New” marker since last visit; filter chips + search | mark all seen, filter, search |
| **Agent** | Ask about my courses | Message list (user right, coral-tinted; agent left, plain text with markdown), composer pinned at bottom, course picker + edit toggle in the composer bar | streaming, stop, copy, new chat, history persists |
| **SYNC** | Is the data fresh? | Three source rows (QQ, WeChat, File Transfer): last read, age chip (ok/warn/never) → one “Run sync” button (copies prompt, opens Claude) → “Last sync” diff list | age chips from sources.md; last commit diff |
| **Life tabs** (Day…Habits) | Bot's own screens | Mini App in the content area, same palette | tab switch without reload |

## Rejected
Pink system accent, grey capsule badges on every row, cards for every row, rainbow course fills, tiny 11 pt body text, empty “stage N” placeholders, icons without labels.

## Contrast
Every ink (text, muted, accent, good, warn, bad) is at least 4.5:1 on bg, sidebar, surface and surface2 in both themes. `design/tokens.json` is the source; `scripts/check-tokens.py [styles.css]` verifies Palette.swift and the Mini App. `Sources/Core/Palette.swift` holds the values and `PaletteTests` enforces it.
