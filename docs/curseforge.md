# Opcow's Auction Ledger

**A gold ledger for WoW: Forever.** See what each character makes selling and spends buying, at the auction house, at vendors, in trades and by COD mail, per item and per category you set up.

## What it counts

- **Auction house.** Sales count when you take the gold from the "Auction successful" mail, after the auction house's cut. Purchases count when you take the item from the "Auction won" mail. Blizzard's mailbox and "Open All" mail addons both work.
- **Vendors.** Buying, selling and selling junk count at the gold that really changed hands, discounts and all. Buying back something you just sold takes that sale back out. Repairs aren't counted.
- **Trades.** A trade counts when gold changed hands: more gold to you is a sale of what you gave, more gold from you is a purchase of what you got. Trades with no gold, or of gold alone, aren't counted.
- **COD mail.** Paying for a COD mail is a purchase; taking the payment for one you sent is a sale, with the items you sent.

Every sale and purchase says where it happened and who with. When one covers several items, its gold is shared out by the items' vendor prices.

## The window

Open it with `/oal`, the minimap button or the addon compartment.

- **Summary:** earned and spent today, in the last 7 and 30 days, and all time, plus your latest sales and purchases.
- **Items:** every item you've sold or bought, with how many, the gold, and the average price of one. Sort by any column.
- **Categories:** make your own, ex: Mining, holding ore, bars and stone. An item can be in as many categories as you like. Add items by typing a name, Shift-clicking or dragging one in, picking from the ledger, or with **Find in bags...**, which searches your bags and bank the way the bags' search box does.
- **Show** picks the time counted: all time, the last 30 or 7 days, or today. **From** picks where: everywhere, or only the auction house, vendors, trades or COD mail.

Each character has its own ledger; categories are shared by all your characters.

## Commands

- `/oal` opens the ledger.
- `/oal minimap` shows or hides the minimap button.
- `/oal search <word>` lists the items in your bags and bank that match.
- `/oal mail` lists the mail in your open mailbox and what it would count.
- `/oal debug` prints each sale and purchase as it's counted, and what isn't and why.
- `/oal clear` deletes this character's sales and purchases (it asks first).
