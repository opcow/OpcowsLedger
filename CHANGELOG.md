# Changelog

## 0.2.0

### Added

- A **Profit** tab: what your sales made over what their items cost, per item or per category,
  with the margin, and a chart of profit by the hour (today), day (7 or 30 days) or week (all time).
  Click a row to chart only that item or category. Works across all your characters, so an item
  bought on one and sold by another costs what was paid for it; a button narrows it to this
  character's sales.
- An item's cost is the average paid for it. Items not bought (gathered, looted, or from before the
  ledger) cost their market value: their recent price in the ledger, else the vendor's.
- Crafting is counted: what a craft used and made is seen in your bags while a profession window is
  open, and crafted items cost what went into them. Crafts that make nothing (enchants) aren't
  counted.
- A **Compare** tab: pick a category you sell (ex: Mining) and one you buy (ex: Leather) and see,
  for the time Show picks, what selling the one earned against what buying the other cost, what's
  left over, and how much of the bought category your crafts used, with how much of that you
  gathered yourself.

## 0.1.0

### Added

- First version: sales and purchases are read from the auction house's mail and counted per
  character, per item and per category.
- Vendors, trades and COD mail count too, and each sale and purchase says where it happened (the
  Summary list's **From** column, with who it was with). Trades where no gold changed hands aren't
  counted. A **From** button picks which to count: everywhere, or one of them.
- The ledger window with Summary, Items and Categories tabs, a minimap button and an addon
  compartment entry.
- **Find in bags...** in the Categories tab searches your bags and bank like the bags' search box
  (ex: "mining"), lists what it finds ticked, and adds the ones you keep ticked. The bank's contents
  are remembered at each visit so it can be searched from anywhere.
- `/ol`, `/ol minimap`, `/ol search`, `/ol mail`, `/ol debug` and `/ol clear`.
