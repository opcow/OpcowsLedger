# Opcow's Auction Ledger

Keeps track of what each character makes selling and spends buying, at the auction house, at
vendors, in trades with other players and by COD mail, per item and per category you set up. Each
sale and purchase says where it happened.

## How it counts

- **Auction house:** a sale counts when you take its gold from the "Auction successful" mail. It's
  the gold that reached your bags, after the auction house's cut. A purchase counts when you take
  its item from the "Auction won" mail, at the price you paid. Blizzard's mailbox and mail addons
  with an "Open All" button both work.
- **Vendors:** buying, selling and the "sell junk" button count at the gold that really changed
  hands, discounts and all. Buying back something you just sold takes that sale back out. Repairs
  aren't counted, nor items bought with tokens or other items.
- **Trades:** a trade counts when gold changed hands. More gold came to you than went: a sale of
  the items you gave. More went: a purchase of the items you got. A trade with no gold, or the same
  gold both ways, isn't counted, nor a trade of gold alone.
- **COD mail:** paying for a COD mail counts as a purchase when you take its item. Your COD mail
  counts as a sale when you take the payment; the ledger remembers what you sent so it can name the
  items (for COD mail sent before this version, the payment's subject gives the item).

When one sale or purchase covers several items (a trade or a COD mail), its gold is shared out by
the items' vendor prices, or evenly when the game doesn't know them.

## The window

Open it with `/oal`, the minimap button or the addon compartment.

- **Summary:** earned and spent today, in the last 7 and 30 days, and all time, plus your latest
  sales and purchases, with where each happened and who with.
- **Items:** every item you've sold or bought, with how many, the gold, and the average price of
  one. Click a column's header to sort by it.
- **Categories:** make your own, ex: Mining, and add the items it covers: ore, bars, stone. An item
  can be in as many categories as you like. Add items by typing a name, Shift-clicking one into the
  box, dragging one from your bags, picking from the ledger, or with **Find in bags...**.

**Find in bags...** searches your bags and bank the way the search box on your bags does, so
"mining" finds ore, bars and stone, and "leather" or "herb" works too. It starts with the category's
name. Everything it finds is ticked: click an item to untick it, then click **Add ticked**. Your
bank can only be searched this way while it's open, so the addon remembers what's in it each time
you visit; away from the bank, those items are matched by their name and type (ex: "Leather",
"Metal & Stone").

The **Show** button picks the time the Items and Categories tabs count: all time, the last 30 or 7
days, or today. The **From** button picks which to count on every tab: all of them, or only the
auction house, vendors, trades or COD mail.

Each character has its own ledger. Categories are shared by all your characters.

## Commands

- `/oal` opens the ledger.
- `/oal minimap` shows or hides the minimap button.
- `/oal search <word>` lists the items in your bags and bank that match, ex: `/oal search mining`.
- `/oal mail` lists the auction house and COD mail in your open mailbox and what it would count.
- `/oal debug` prints each sale and purchase as it's counted, and what isn't counted and why.
- `/oal clear` deletes this character's sales and purchases (it asks first).
