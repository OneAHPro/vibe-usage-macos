# System Appearance Theme Design

## Goal

Make the macOS client follow the current system appearance automatically. The dashboard, settings surfaces, charts, filters, quota cards, tooltips, and standard title bar must remain readable in both Light and Dark appearances without a separate in-app theme preference.

## Chosen Approach

Introduce a centralized semantic color palette backed by dynamic `NSColor` values. Views will reference roles such as window background, elevated surface, separator, primary text, secondary text, selection, and tooltip instead of fixed grayscale values.

This is preferred over globally inverting colors, which produces poor contrast and corrupts data colors, and over maintaining duplicate light and dark view trees, which would double maintenance cost.

## Behavior

- The app inherits the macOS appearance; no window or root view forces Dark Aqua.
- Switching the system appearance updates visible SwiftUI content without restarting the app.
- Neutral UI colors resolve to calibrated light and dark variants.
- Semantic status and data colors (success green, activity blue, warning orange, destructive red, and chart series colors) retain their meaning in both modes, with contrast-adjusted variants only where needed.
- The menu-bar item continues to use the system primary label color.
- No theme preference or persisted theme state is added.

## Components

### `AppTheme`

A small Swift file owns the semantic tokens. Custom tokens use AppKit's dynamic color provider so SwiftUI re-resolves them when the effective appearance changes. Standard label roles use native semantic system colors where possible.

### Views

The dashboard views replace hard-coded neutral colors with `AppTheme` roles. Data series colors remain explicit. Tooltips and selected controls use dedicated tokens because they need stronger contrast than ordinary cards.

### Window Lifecycle

`MainWindowController` stops assigning `.darkAqua`; the standard window inherits the system appearance. All existing close, minimize, resize, menu-bar, and background-sync behavior remains unchanged.

## Testing

- A window test verifies that the main window does not override the system appearance.
- Palette tests resolve representative tokens under Aqua and Dark Aqua and verify that their luminance and contrast direction differ as intended.
- The full Swift test suite and release build must pass.
- The installed app is visually checked in the computer's current appearance, and the dynamic palette is verified under both appearances without persisting a theme override.

## Repository Strategy

Keep development on the existing local feature branch for this milestone. Before new-system API integration or public releases, create a dedicated GitHub fork/repository under the user's organization or account, preserve the upstream license and attribution, and use that repository as the source for releases and future update feeds.
