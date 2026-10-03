# 1. Rebase local work on server truth

- Status: accepted

## Context

Warehouse staff work where connectivity is poor: basements, cold rooms,
yards. Several people change the same stock at once, from different devices.
A naive offline app either blocks until it is online, or overwrites
quantities and loses other people's changes.

## Decision

Never store a "current quantity" that was computed on the device. Store two
things instead:

- `stock.server_quantity`: the last value **confirmed by the server**.
- `movements`: this device's changes, each `pending`, `synced` or `rejected`.

The quantity shown is computed in SQL:

```
server_quantity + SUM(pending deltas here) − SUM(pending transfers arriving here)
```

Consequences:

- **Refresh is safe at any time.** Pulling new server figures replaces only
  `server_quantity`, and pending work is re-applied on top. Local work is
  rebased, never lost or double-counted.
- **Delivery is atomic.** When the server accepts a movement, the confirmed
  quantity and the movement's `synced` status are written in one
  transaction. The UI never shows the change twice or not at all.
- **Conflicts are honest.** If another device emptied the shelf first, the
  server rejects the issue (`insufficient_stock`). The movement turns
  `rejected` with the server's available quantity, stops counting, and the
  displayed figure corrects itself.

## Delivery

Writes go through
[`durable_sync_queue`](https://github.com/mokinan/durable_sync_queue)
(previously `offline_sync_queue`):

- **Group = stock line** (`sku@warehouse`). Movements on one item are applied
  in order, so a receive always lands before the issue that depends on it,
  and unrelated items sync in parallel.
- Every request carries an **idempotency key**. The server replays the
  stored result for a retried request.
- The queue's storage is a table in the same database, and each movement is
  queued **in the same transaction** that records it.

Integrating the queue here surfaced two bugs in the package, both fixed
upstream with regression tests (0.1.1, 0.1.2): forced drains could be
absorbed by a concurrent pass, and automatic drains inherited Drift's
transaction zone.
