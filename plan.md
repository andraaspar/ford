# Parallel Translation Editor — Plan

## Goals
- Source and target text side by side, readable and editable on an Android phone and on desktop (Linux/Windows).
- **Stable scroll position:** adding, removing, splitting or joining rows never makes the view jump.
- Remarks stay visible inline, with no hidden third column.
- Fast **exact** search (accents matter), with a match-case toggle.
- Data lives in plain-text files in a Syncthing folder. No server.
- One-time import of the existing Obsidian Markdown tables.

## Tech stack
| Concern | Choice |
|---|---|
| Framework | Flutter (stable, 3.47), targets Android + Linux/Windows desktop |
| State management | Plain `ChangeNotifier` (`ChapterEditor`, `ChapterAutosaver`) |
| Long list with stable positions | `scrollable_positioned_list` (jump to index, read which rows are visible) |
| File access (Android) | `MANAGE_EXTERNAL_STORAGE` ("All files access"), then plain `dart:io` |
| File change detection | `watcher` package on desktop; folder scan on app resume / regular check on Android |
| Local, per-device settings | `shared_preferences` (book folder path, last position per chapter, font size, theme) |
| Tests | Unit tests for parser, serializer, importer and row operations; widget tests for the editor |

## Data model
A **book** is a folder. A **chapter** is a file. A chapter is a list of **rows**.

- **A row is usually one sentence:** source, target, optional remark, plus a stable ID.
- **The first row is the chapter title pair.**
- **Blank rows (source and target both empty) are breaks.** One blank row is a paragraph break; several (for example 3) make a larger section break. They are real rows, so adding, enlarging, shrinking and deleting breaks is ordinary row editing.
- **No line breaks inside a row's source or target.** Remarks may have several lines.

### Data layout (in the Syncthing folder)
```
Translations/
  Az új nap könyve/
    01.txt     # chapters ordered by file name (natural sort); no shared index file
    02.txt
    ...
```

### Chapter file format
One block per row, with a blank line between blocks. Each field is a single line, so files diff well and Syncthing conflicts can be fixed by hand.
```
@ k3f9a
< IX. The House Azure
> IX. Az Azúr Ház

@ 7bq2x
< There were dim yellow lights in the lower windows.
> Fakó sárga fény világlott az alsó ablakokban,
! Optional remark. Several "!" lines are allowed.

@ m02xd
<
>
```
- `@ id`: a short random ID that stays with the row (for restoring scroll position and working through conflicts).
- `<` source, `>` target (either may be empty), `!` remark lines (optional). `#` lines are comments.
- Saving always writes the same fixed layout, so diffs stay minimal.
- Reading never fails: missing or duplicate IDs and stray lines are repaired and reported as warnings.

## Core behaviour
### View
- Two equal columns. Each row is a source cell and a target cell. The remark shows below the row in a muted style with a 💬 marker, and can be collapsed.
- **Blank rows are drawn as a short gap row**, not a full-height empty row. Three in a row are visibly a bigger gap. Tapping one lets you type into it, which turns it into a normal row.
- Rows with a source but no target are visibly marked as untranslated.
- Tap a cell to edit it in place. Only the active cell is a text field; the rest are plain text, which keeps scrolling fast.
- Font size and dark/light theme in settings.

### Row operations
| Operation | Behaviour |
|---|---|
| **Split** (cursor in source *or* target cell; also **Enter**) | The text before the cursor stays in the current row. A new row is inserted below with the text after the cursor on the same side and an **empty** cell on the other side. The remark stays on the original row. |
| **Join with next** | **Asks for confirmation first**, then merges row *i* and row *i+1*: source = `src_i + " " + src_i+1`, target likewise, remarks joined on separate lines. Empty sides are joined without an extra space. |
| Insert blank row (break) / Delete row | From a row menu. Adding or removing a break is just inserting or deleting a blank row. |
| Undo / redo | For text edits and row operations, kept per session. |

The scroll position is anchored to the row being edited, so these operations never move the view.

### Saving & sync
- Autosave about 1 second after you stop typing, and when the app goes to the background. Saves write a temp file and then rename it over the real one.
- When the app resumes or a file changes: if the chapter has no unsaved edits, it reloads quietly and keeps the scroll position (matched by row ID).
- If there are unsaved edits **and** the file changed on disk, you get a prompt (keep mine / take theirs / save mine as a copy).
- If `*.sync-conflict-*` files exist, the app shows a banner.

### Search
- Exact substring match, accents count. A **match case** toggle (off by default).
- Scope: source / target / remarks / all; current chapter or whole book.
- Results list with context; tapping one jumps to the row and highlights the match.

### Import (Obsidian → book folder)
Input: one `.md` file per chapter (`1.md` … `22.md`), each a simple 3-column table:
```
| chapter title | fejezetcím | |
| - | - | - |
| First paragraph | Első bekezdés| Megjegyzés|
```
- The header row becomes the title row; the separator row is skipped; cells are trimmed; `\|` becomes `|`.
- Blank rows are kept (they are breaks).
- **Quote artifact repair:** a cell that starts with an unbalanced `"` whose closing quote ended up on its own row (`| " | |`), possibly with blank rows in between, gets the opening quote removed, and the artifact rows are dropped. Each repair is reported.
- `<br>` in source/target is replaced with a space (reported).
- Output names are zero-padded (`1.md` → `01.txt`). Existing files are never overwritten; the originals are left untouched.
- Available now as a command-line tool: `dart run tool/import_obsidian.dart <source> [<target>]` (without a target it's a dry run).

Sample dry run on *Az új nap könyve*: 22 chapters, 6,056 rows, 1,769 blank, 1,782 untranslated, 16 warnings (15 quote repairs in chapters 1, 3, 10 and 11, plus one `<br>`). **Check by hand:** 11.md line 144. It's unclear whether a paragraph break was intended before "I got out of bed".

## Milestones
0. ✅ **Toolchain:** Flutter SDK, JDK, Linux build tools, Android `platform-tools` (`adb`), project created.
1. ✅ **Model + file format:** parser, serializer, row operations, unit tests.
2. ✅ **Importer** with tests based on the real sample, plus the CLI tool.
3. ✅ **Read-only viewer:** pick the book folder, list chapters, side-by-side list with break rows, remember the scroll position, reopen the last chapter on launch.
4. ✅ **Editing:** edit cells in place, autosave, split / join / insert / delete, remarks, undo. Still to check on the phone: the keyboard stays up without flicker on Enter, and the view stays put when the keyboard opens.
5. **Search.**
6. **Sync robustness:** detect external changes, reload, show a conflict prompt and banner.
7. **Polish & packaging:** settings, theme, signed APK to install on the phone, desktop build, import from inside the app. The folder picker should also point out un-imported Markdown files instead of only showing "0 chapter files".

## Decisions
- Existing data: one Markdown file per chapter, 3-column table; rows are sentences, blank rows are breaks.
- No line breaks inside a source/target cell.
- One file per chapter; chapter order comes from file names (no `book.yaml`).
- Split keeps the new row in the same paragraph; breaks are separate blank rows.
- Search has a match-case toggle.
- Join merges both sides, after confirmation.
- On launch the app reopens the last chapter at the saved row; Back goes to the chapter list.
- `compileSdk` is 37 because `permission_handler` requires it; `targetSdk` still follows Flutter's default.
- Row actions open from a long press or right-click on any row, or from ⋮ in the app bar while a cell is open. Back, Esc or ✓ closes the open cell.
- The title row can't be deleted and nothing can be inserted above it, because another row would silently become the title.
- Until milestone 6, a save overwrites any change Syncthing made to the open chapter's file.
- Saving drops `#` comment lines, because the parser doesn't keep them.
- Extras (status, progress, export, glossary) are left out of v1.
- This file (`ford/plan.md`) is the main copy of the plan.
