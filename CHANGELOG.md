# Changelog

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
