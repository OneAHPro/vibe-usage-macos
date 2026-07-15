# Standard Window macOS Design

## Goal

Convert the existing Vibe Usage macOS dashboard from a transient menu-bar
popover into a persistent, standard macOS application window while retaining
the menu-bar status item and background synchronization.

This first milestone changes the application shell only. It keeps the current
dashboard content, data source, filters, charts, settings, and sync pipeline.
Connecting the app to the user's new system and redesigning the dashboard are
separate follow-up milestones.

## Considered Approaches

### 1. Make the existing `NSPanel` draggable

This is the smallest code change, but it leaves the dashboard as a borderless,
nonactivating popup with fragile focus and lifecycle behavior. It would still
not behave like a normal macOS application. Rejected.

### 2. Add a standard `NSWindow` around the existing SwiftUI dashboard

This preserves the working SwiftUI views and data pipeline while replacing the
problematic shell. It is the lowest-risk route to a normal Mac client and is the
selected approach.

### 3. Port the Windows Tauri client to macOS

This could become a cross-platform foundation, but it introduces a second UI
implementation and requires replacing Windows-specific runtime, packaging, and
local-scanning code. Deferred until cross-platform delivery is a requirement.

## User Experience

- Launching the app opens a normal main window.
- The default content size is 960 x 720 points.
- The window is titled, movable, resizable, minimizable, closable, and can enter
  macOS full screen.
- The minimum content size is 760 x 560 points.
- Closing the main window hides it but does not terminate the app; background
  synchronization continues.
- Clicking the menu-bar item toggles the main window instead of opening a
  popover.
- Clicking the Dock icon or selecting the app with Cmd-Tab restores and focuses
  the main window.
- Clicking the desktop or another application never hides the main window.
- Cmd-Q remains the explicit way to quit.
- The last window position and size are restored on the next launch.
- The existing Settings window remains a separate standard window.

## Architecture

### `MainWindowController`

A new controller owns the dashboard `NSWindow`. It constructs one reusable
window with the standard macOS style masks and hosts the SwiftUI dashboard with
`NSHostingController`. It exposes `show()`, `toggle()`, and `closeForQuit()`.
Its window delegate intercepts user close requests and hides the window rather
than releasing it.

### `MenuBarController`

The controller continues to own and render the `NSStatusItem`, including cost
and Token text. It no longer owns a `PopoverPanel`, positioning logic, outside-
click monitors, or popup animations. Its click action calls a supplied window
toggle closure. Data refresh on presentation moves to the main-window path.

### Application Lifecycle

`AppDelegate` creates one shared `AppState`, `UpdaterViewModel`,
`MainWindowController`, and `MenuBarController`. It opens the main window after
initialization. Application activation restores the window only when no other
owned modal surface is active. Application deactivation does nothing.

The app always uses regular activation policy so it remains a normal Dock and
Cmd-Tab application. The old `showInDock` preference is ignored by the new
shell and removed from Settings because hiding the Dock icon conflicts with the
standard-client requirement.

### Dashboard View

The existing `PopoverView` becomes a reusable dashboard surface. Its fixed
520-point width is removed and replaced with flexible sizing. Internal cards
and charts retain their current behavior. Layout changes are limited to what is
required to remain usable between the minimum and default window sizes.

### Updates

The custom build must not install future official releases over the modified
application. Automatic Sparkle checks are disabled and the update controls are
removed from Settings for this milestone. The Sparkle dependency can remain in
the package temporarily to avoid unrelated build-system churn.

## Data and Sync Behavior

No API, model, authentication, or local-scanning behavior changes in this
milestone. The existing `AppState`, `APIClient`, `SyncEngine`, and
`SyncScheduler` remain the source of truth. Showing the main window performs
the same debounced usage and subscription-quota refresh that opening the old
popover performed.

## Error Handling

- Window creation is idempotent; repeated menu-bar and Dock actions reuse the
  same window.
- A hidden or minimized window is restored before it is focused.
- Settings and updater modal state cannot cause the main window to close.
- If data refresh fails, the existing dashboard error and retry behavior is
  retained.

## Testing

1. Add unit tests for the standard window configuration: style masks, default
   size, minimum size, frame autosave name, and hide-on-close behavior.
2. Add lifecycle tests proving deactivation does not request a hide and Dock or
   menu-bar activation requests presentation.
3. Run the complete Swift test suite.
4. Build the release app with the repository build script and verify the code
   signature.
5. Install the app in `/Applications`, launch it, and verify through macOS
   window metadata and a screenshot that a titled standard window is visible.
6. Exercise the acceptance flow: move, resize, minimize, restore, click another
   app, close, reopen from the menu bar, and quit.

## Acceptance Criteria

- A visible standard Vibe Usage window opens at launch.
- The main window can be moved, resized, minimized, and restored.
- Switching to another app leaves the window visible.
- Closing the window keeps the process and background scheduler running.
- The menu-bar item and Dock icon both reopen the same main window.
- Existing usage data loads from the preserved `~/.vibe-usage` configuration.
- The app is installed in `/Applications` and passes signature verification.
- The custom build cannot automatically update back to the official popover
  release.
