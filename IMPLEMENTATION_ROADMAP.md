# Clipboard History for macOS — Implementation Roadmap

Build this app one focused session at a time. Each task should leave the app in a working state before moving on. Commit your work after every completed task if you initialize this folder as a Git repository.

## Product goal

A native macOS menu-bar utility that keeps a local history of copied text and images. You can search prior copies, copy them back to the clipboard, and favorite important items so automatic cleanup never removes them.

### First-version boundaries

- macOS only, with a deployment target of macOS 14 or later.
- Native Swift, SwiftUI, and SwiftData.
- Text and images only; files, cloud sync, OCR, tags, folders, and automatic pasting come later.
- All data stays on the device. No account or network access.
- The app is opened from the menu bar or a global shortcut, not from the Dock.

## Task 1 — Create and run the macOS project

**Objective:** Start a native SwiftUI macOS application that can run as a menu-bar utility.

**Implementation work:**

- Create a new Xcode project named `ClipboardHistory` using the **App** template, **SwiftUI** interface, **Swift** language, and **macOS 14+** deployment target.
- Add an `AppDelegate` using `NSApplicationDelegateAdaptor`.
- Configure the app as an agent application (`LSUIElement`) so it does not appear in the Dock.
- Add a `MenuBarExtra` with a temporary icon and a Quit action.
- Create a `README.md` with the app’s purpose, required macOS version, and instructions to run it from Xcode.

**Completion check:** The app builds and runs; a menu-bar icon appears, and choosing Quit closes the app.

**Commit checkpoint:** `chore: bootstrap menu bar macOS app`

## Task 2 — Define clipboard entries and persistent storage

**Objective:** Give the app a durable local model for clipboard history.

**Implementation work:**

- Create a SwiftData `ClipboardEntry` model with:
  - A stable UUID
  - `createdAt` and `lastUsedAt` dates
  - `isFavorite`
  - A content kind (`text` or `image`)
  - A content hash used for deduplication
  - Optional text content
  - Optional image-file relative path and thumbnail data/path
- Create a small storage service that resolves an Application Support subdirectory for image files.
- Configure one shared `ModelContainer` in the app entry point.
- Seed a few temporary entries only in SwiftUI previews, not in the running application.

**Completion check:** Add an entry in a temporary debug action, relaunch the app, and confirm SwiftData loads it again.

**Commit checkpoint:** `feat: persist clipboard history entries`

## Task 3 — Monitor and save copied text

**Objective:** Automatically record text copied in other apps.

**Implementation work:**

- Create a `ClipboardMonitor` that watches `NSPasteboard.general.changeCount` on a short repeating timer (roughly 0.5 seconds).
- When the count changes, read plain text from the general pasteboard and save a new `ClipboardEntry`.
- Ignore empty or whitespace-only text.
- Keep the monitoring service alive for the app’s full lifetime and start it when the app launches.
- Add lightweight logging in debug builds for captured text; never log full sensitive clipboard content in release builds.

**Completion check:** Copy text in TextEdit or Safari and confirm it is saved after opening the app’s temporary debug list.

**Commit checkpoint:** `feat: capture copied text`

## Task 4 — Deduplicate text and enforce retention

**Objective:** Keep the history useful and bounded instead of filling with repeats.

**Implementation work:**

- Produce a SHA-256 hash from normalized text content.
- When copied content already exists, update its recency timestamp and move it to the most-recent position instead of inserting a duplicate.
- Define the default non-favorite history limit as 500 entries.
- After an insertion, delete the oldest non-favorite entries over that limit.
- Never prune favorites automatically.
- Put this behavior in a testable history repository/service rather than inside the SwiftUI view.

**Completion check:** Recopying the same text produces one entry; adding more than the configured limit removes only old non-favorites.

**Commit checkpoint:** `feat: deduplicate and retain text history`

## Task 5 — Build the menu-bar history window

**Objective:** Replace debug UI with a usable native clipboard picker.

**Implementation work:**

- Make the menu-bar icon open a compact SwiftUI history window or popover.
- Show clipboard entries in newest-first order.
- Render readable text previews, truncating long text only in the list presentation.
- Add a clear empty state explaining that copied text will appear there.
- Include a simple close action and make reopening reliably refresh the displayed history.
- Keep the initial layout deliberately native and simple; do not introduce custom design systems yet.

**Completion check:** The menu bar opens a history list that survives app relaunches and has a useful empty state.

**Commit checkpoint:** `feat: show clipboard history from menu bar`

## Task 6 — Re-copy and reuse a history item

**Objective:** Let users put a selected history item back on the clipboard.

**Implementation work:**

- Add a row action for copying an entry’s text back to `NSPasteboard.general`.
- Update `lastUsedAt` when an item is selected.
- Teach `ClipboardMonitor` to ignore pasteboard changes written by the app itself, so selecting an item does not create a duplicate history event.
- Close the picker after a successful selection.
- Add keyboard selection/activation where standard SwiftUI controls make it practical.

**Completion check:** Select a prior text entry, switch to another app, press `Cmd+V`, and verify the expected text pastes. Selecting it must not create another entry.

**Commit checkpoint:** `feat: restore items to clipboard`

## Task 7 — Add favorites and history management

**Objective:** Preserve important clipboard items and provide basic cleanup controls.

**Implementation work:**

- Add a favorite toggle to each entry and a visual favorite indicator.
- Add an All/Favorites filter.
- Add a delete action for one entry.
- Add a “Clear non-favorites” action with a confirmation dialog.
- Ensure deleting an image entry also deletes its local image and thumbnail files; text entries require no files.
- Keep favorite state persistent across relaunches and exempt from retention pruning.

**Completion check:** Favorite an item, filter to it, exceed the normal limit in a test configuration, and verify the favorite remains. Verify clear-history leaves favorites untouched.

**Commit checkpoint:** `feat: manage favorite clipboard entries`

## Task 8 — Capture and display images

**Objective:** Extend the history from text-only to text and image clipboard entries.

**Implementation work:**

- Detect image data on the pasteboard when there is no usable text representation.
- Convert captured images to PNG, write them to Application Support, and save the relative path in the entry.
- Generate a small PNG thumbnail for fast list rendering.
- Hash the normalized PNG data for image deduplication.
- Show image thumbnails in the history list and a larger preview in a detail view or expanded row.
- Re-copy image data to the general pasteboard when selected.
- Handle unreadable or unsupported image data by skipping it safely without breaking monitoring.

**Completion check:** Copy an image from Preview or Safari, see its thumbnail in history, select it, and paste the recovered image into a document.

**Commit checkpoint:** `feat: capture and restore clipboard images`

## Task 9 — Add search and a global shortcut

**Objective:** Make history fast to retrieve without navigating menus.

**Implementation work:**

- Add a search field that filters text entries by their content, case-insensitively.
- Keep image entries visible when search is empty; when there is a query, show only image entries if you later add metadata/OCR. For v1, text search hides image-only entries while a query is active.
- Add a configurable global shortcut using a maintained macOS shortcut utility/package or a small, isolated Carbon-based shortcut wrapper.
- Choose a non-conflicting default shortcut such as `Control + Option + V`.
- Open and focus the history picker through the shortcut.
- Store the shortcut preference locally and provide a reset-to-default action.

**Completion check:** Press the global shortcut from another app, search for copied text, select it, then paste it normally with `Cmd+V`.

**Commit checkpoint:** `feat: search clipboard history with global shortcut`

## Task 10 — Add privacy settings and excluded applications

**Objective:** Give users control over local history and reduce accidental retention of sensitive copies.

**Implementation work:**

- Add a Settings window accessible from the menu-bar menu.
- Include controls for the history limit, global shortcut, clearing non-favorites, and excluded applications.
- Store exclusions as bundle identifiers, with a starter list of common password managers.
- At clipboard-change detection time, read the currently active application and skip capture when it matches an exclusion.
- Explain in the UI that app exclusion is best-effort: macOS does not provide a perfectly reliable source-app identity for every clipboard write.
- Keep all settings local via `AppStorage` or a dedicated SwiftData settings model.

**Completion check:** Add a test application’s bundle identifier to exclusions, copy text while it is active, and confirm no entry is created. Remove the exclusion and confirm capture resumes.

**Commit checkpoint:** `feat: add local privacy controls`

## Task 11 — Test, harden, and prepare a first release

**Objective:** Verify the app’s core behavior and make failures recoverable.

**Implementation work:**

- Add unit tests for text hashing, image hashing, duplicate handling, favorite-safe pruning, file cleanup, and exclusion decisions.
- Add UI tests for empty history, favorites filtering, text search, selecting/re-copying an item, and clearing non-favorites.
- Verify persistence across relaunches.
- Manually test text and images in TextEdit, Safari, Preview, Notes, and at least one browser-based editor.
- Test missing-image-file behavior: show a safe unavailable state and allow deletion rather than crashing.
- Set a clear version number, app icon, and concise privacy wording before distribution.

**Completion check:** The automated tests pass, manual smoke tests pass, and the app can be launched, quit, and relaunched without data corruption.

**Commit checkpoint:** `test: cover clipboard history core flows`

## Decisions already made

- The app is macOS-only and native: Swift + SwiftUI + SwiftData.
- It is a background menu-bar app with a global shortcut.
- It retains 500 non-favorite entries by default.
- Repeat copies update an existing entry and move it to the top.
- Choosing an item copies it back to the clipboard; it does not automatically paste.
- Favorites are a durable saved collection and are never automatically removed.
- Clipboard data remains local; password-manager/app exclusions are best-effort.
