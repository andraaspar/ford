# Parallel Translation Editor — Plan

## Goals
- Source and target text side by side, readable and editable on an Android phone and on desktop (Linux/Windows).
- **Stable scroll position:** adding, removing, splitting or joining rows never makes the view jump.
- Remarks stay visible inline, with no hidden third column.
- Fast **exact** search (accents matter), with a match-case toggle.
- Data lives in plain-text files in a Syncthing folder. No server.
- Files can be organized into nested folders, and actions such as search, import and export can target any selection of those folders.
- One-time import of the existing Obsidian Markdown tables.

## Tech stack
| Concern | Choice |
|---|---|
| Framework | Flutter (stable, 3.47), targets Android + Linux/Windows desktop |
| State management | Plain `ChangeNotifier` (`ChapterEditor`, `ChapterAutosaver`) |
| Long list with stable positions | `scrollable_positioned_list` (jump to index, read which rows are visible) |
| File access (Android) | `MANAGE_EXTERNAL_STORAGE` ("All files access"), then plain `dart:io` |
| File change detection | `watcher` package on desktop; folder scan on app resume / regular check on Android |
| Local, per-device settings | `shared_preferences` (root folder path, last position per chapter, font size, theme) |
| Tests | Unit tests for parser, serializer, importer and row operations; widget tests for the editor |

## Data model
A **folder** holds chapters and other folders, all inside one root folder. A **chapter** is a file. A chapter is a list of **rows**.

- **Folders nest to any depth** and can hold chapters, other folders, or both. A folder may in practice be a book, a section or a sub-section, but that role is only implied by how it is used. It isn't stored or named anywhere, in the data or in the app.
- **A folder has one property for now: its display name.** This is the first row of the first file directly inside the folder, so it has a source and a target side and is translated like any other row. It doesn't need to match the folder's name on disk, and it isn't stored anywhere else.
- **A row is usually one sentence:** source, target, optional remark, plus a stable ID.
- **The first row is the chapter title pair.**
- **Blank rows (source and target both empty) are breaks.** One blank row is a paragraph break; several (for example 3) make a larger section break. They are real rows, so adding, enlarging, shrinking and deleting breaks is ordinary row editing.
- **No line breaks inside a row's source or target.** Remarks may have several lines.

### Data layout (in the Syncthing folder)
```
Translations/     # the root folder
  01/             # a folder
    00.txt        # its first row is the folder's display name
    01.txt        # files and folders sort together by name (natural sort); no shared index file
    02/           # a nested folder, placed between 01.txt and 03.txt
      00.txt      # its first row is this nested folder's display name
      01.txt
    03.txt
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
- **Blank rows are as tall as a row with one line of text.** Three in a row are visibly a bigger gap. Tapping one lets you type into it, which turns it into a normal row.
- A horizontal line separates the rows.
- Rows with a source but no target are visibly marked as untranslated.
- Tap a cell to edit it in place. Only the active cell is a text field; the rest are plain text, which keeps scrolling fast.
- Font size and dark/light theme in settings.

### Row operations
| Operation | Behaviour |
|---|---|
| **Split** (cursor in source *or* target cell; also **Enter**) | The text before the cursor stays in the current row. A new row is inserted below with the text after the cursor on the same side and an **empty** cell on the other side. The remark stays on the original row. |
| **Merge with previous** (**Backspace** at the start of a source or target cell) | Merges row *i* into row *i-1*, with the caret where the texts meet: source = `src_i-1 + " " + src_i`, target likewise, remarks joined on separate lines. Empty sides are joined without an extra space. **Asks for confirmation first** only if the other side of row *i* has text; otherwise it simply undoes a split. |
| Insert blank row (break) / Delete row | From a row menu. Adding or removing a break is just inserting or deleting a blank row. |
| Undo / redo | For text edits and row operations, kept per session. |

The scroll position is anchored to the row being edited, so these operations never move the view.

### Saving & sync
- Autosave about 1 second after you stop typing, and when the app goes to the background. Saves write a temp file and then rename it over the real one.
- When the app resumes or a file changes: if the chapter has no unsaved edits, it reloads quietly and keeps the scroll position (matched by row ID).
- If there are unsaved edits **and** the file changed on disk, you get a prompt (keep mine / take theirs / save mine as a copy).
- If `*.sync-conflict-*` files exist, the app shows a banner.

### Folders
The chapter list becomes a tree of folders and chapters, showing each folder's display name.

| Action | Behaviour |
|---|---|
| **Create** | Asks for a display name, then creates the folder and a first file (`00.txt`) with that name as its title row. The name on disk is generated and doesn't depend on the display name. |
| **New chapter** | Asks for a title, then adds a chapter to the folder under the next free number. |
| **Edit** | Changing the display name edits the title row of the first file, on the source and target sides. The folder isn't renamed on disk. |
| **Reorganize** | Drag chapters and folders into a new order within a folder, or move them to another folder, where they go after what's there. Order comes from names on disk, so the app renames the files and folders it needs to. Open edits are saved first, because the tree is only reachable once a chapter has closed, and saved per-chapter positions follow the move. |
| **Delete** | Always asks for confirmation first, stating the folder's display name and how many chapters, nested folders and other files will go with it. Chapters can be deleted the same way. Syncthing passes the deletion on to the other devices. |

- **Fallback name:** a folder with no file directly inside it, or whose first file has an empty title row, shows its name on disk, marked as unnamed.
- **Renaming for order:** the numbers at the start of names are handed out again in the new order, so only entries between the old and new place change, and the rest of a name stays with its entry. A name that doesn't start with a number gets one in front of it (`Beta/` becomes `01 Beta/`), so an unnamed folder stays recognizable.
- **The first file decides the display name.** If moving, reordering, deleting or adding a file would make a different file first, the app warns about the display name that would result.
- **Folders whose first file is a real chapter** (such as those imported earlier) show that chapter's title as their display name. An **Add name** action adds a new `00.txt` in front, so the chapter's title stays as it is.

### Choosing targets
Search, import and export all choose their targets the same way, from the tree of folders and chapters:
- Ticking a folder includes everything inside it. Anything inside can then be unticked to omit it, and whatever isn't ticked is left out.
- Import writes to one place, so it picks a single destination folder, or creates a new one.

### Search
- Exact substring match, accents count. A **match case** toggle (off by default).
- Scope: source / target / remarks / all; current chapter, current folder, or any selection of folders and chapters (see *Choosing targets*).
- Results list with context and the display name of the folder each result is in; tapping one jumps to the row and highlights the match.

### Import (Obsidian → folder)
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
3. ✅ **Read-only viewer:** pick the folder, list chapters, side-by-side list with break rows, remember the scroll position, reopen the last chapter on launch.
4. ✅ **Editing:** edit cells in place, autosave, split / join / insert / delete, remarks, undo. Being tested by hand on the phone.
5. ✅ **Folders:** nested folder tree with display names read from the first file; create, edit, reorganize and delete; the shared target picker. "Book" is replaced with "folder" in the code and UI. Not yet tested by hand on the phone.
6. **Search,** using the target picker.
7. **Sync robustness:** detect external changes, reload, show a conflict prompt and banner.
8. **Polish & packaging:** settings, theme, signed APK to install on the phone, desktop build, import from inside the app. The folder picker should also point out un-imported Markdown files instead of only showing "0 chapter files".

## Decisions
- Existing data: one Markdown file per chapter, 3-column table; rows are sentences, blank rows are breaks.
- No line breaks inside a source/target cell.
- One file per chapter; order comes from file and folder names (no index or metadata file).
- Folders are called folders, never books or sections. Their roles are implied, not stored, for now.
- A folder's display name comes from the first row of its first file, so a folder normally starts with a dedicated name file (`00.txt`). That file is otherwise an ordinary chapter and can hold more rows, such as a title page.
- The root folder has no display name. Chapters directly inside it still work.
- Any folder can be chosen as the root, including an empty one or one holding only folders.
- Actions on the tree open from ⋮ on a row, a long press or a right-click; the root's are under ⋮ in the app bar.
- Split keeps the new row in the same paragraph; breaks are separate blank rows.
- Search has a match-case toggle.
- Merging moves both sides. It asks first only if the other side of the row has text.
- The keyboard slides over the list instead of resizing it, because resizing lays out many rows per animation frame.
- On launch the app reopens the last chapter at the saved row; Back goes to the chapter list.
- `compileSdk` is 37 because `permission_handler` requires it; `targetSdk` still follows Flutter's default.
- Row actions open from a long press or right-click on any row, or from ⋮ in the app bar while a cell is open. Back, Esc or ✓ closes the open cell.
- The title row can't be deleted and nothing can be inserted above it, because another row would silently become the title.
- Until milestone 7, a save overwrites any change Syncthing made to the open chapter's file.
- Saving drops `#` comment lines, because the parser doesn't keep them.
- Extras (status, progress, export, glossary) are left out of v1. Export will use the shared target picker when it's added.
- This file (`ford/plan.md`) is the main copy of the plan.
