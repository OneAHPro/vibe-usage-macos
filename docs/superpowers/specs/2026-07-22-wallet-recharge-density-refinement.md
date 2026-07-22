# Wallet Recharge Density Refinement

## Goal

Rebalance the wallet recharge card so preset amounts are the primary choice, server-provided discounts are visible, and custom input and checkout remain compact secondary actions.

## Design

- Replace the oversized full-width amount field with a 38-point compact custom amount control.
- Render every `amount_options` entry in a four-column wrapping grid using 58-point preset cards.
- Use a 16-point amount and 10-point discount/detail label so the wider cards remain visually balanced.
- Each preset card shows the amount and, when `discount[amount]` is below `1`, a Chinese discount label such as `9.5 折`.
- Use the exact discount value returned by the new system. Do not infer discounts for amounts without an exact entry.
- Keep checkout as one action. Amount calculation and order creation remain internal to the same click.
- Replace the full-width CTA with a fixed-width trailing button while retaining an obvious primary action.
- Remove the redundant QR-code security footer.
- Center the empty current-subscription state horizontally and vertically inside its content area.
- Preserve equal-height overview cards at the default width and stacked cards at the minimum width.

## Data Rules

- A discount is displayable only when it is finite, greater than `0`, and less than `1`.
- Invalid, missing, or non-discount values display no badge.
- Discount display is informational. The server remains authoritative for the final payment amount.

## Verification

- Unit-test discount normalization and labels.
- Source-contract test the compact controls and removal of the oversized full-width CTA.
- Run the complete Swift test suite and Release build.
- Install the build and inspect default and minimum-width wallet layouts without creating an order.
