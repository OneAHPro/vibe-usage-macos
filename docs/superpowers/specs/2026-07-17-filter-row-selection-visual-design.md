# Filter Row Selection Visual Design

## Goal

Make filter selection state appear only inside the leading checkbox. Selecting a model or a model family must not apply a background color to the full row.

## Behavior

- Selected options keep the existing filled checkbox and checkmark.
- Partially selected model families keep the existing filled checkbox and minus symbol.
- Selected and partially selected rows keep a transparent background, matching unselected rows.
- The row remains the full-width click target introduced by the filter hit-testing fix.
- Filter state, grouping, scrolling, typography, and animation behavior remain unchanged.

## Implementation

Remove the state-dependent row background from `FilterPanelView.checkRowContent`. Keep the checkbox fill as the sole colored selection indicator and retain the existing `contentShape(Rectangle())` hit area.

## Verification

- Add a regression test that fails while selected rows use `AppTheme.selectionBackground` and passes when row backgrounds are state-independent.
- Run the full Swift test suite and Release build.
- Install the new app and use real mouse events to select a model, verifying the checkbox changes while the row background remains unchanged.
