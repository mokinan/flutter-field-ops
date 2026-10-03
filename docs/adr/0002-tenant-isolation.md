# 2. One local database per tenant

- Status: accepted

## Context

The app is SaaS: one install may be used for more than one company (a
contractor serving two clients), and support staff switch tenants often. A
`tenant_id` column on every table relies on every query remembering a
`WHERE` clause. One forgotten filter shows company A's stock to company B.

## Decision

- Each tenant gets its own SQLite file (`fieldops_<tenant>.sqlite`). Signing
  in opens that tenant's database. Signing out closes it and disposes the
  repository and sync queue.
- Everything tenant-scoped (repository, queue, screen state) is created under
  a `SessionScope` keyed by user. Switching account rebuilds it from scratch.
  No state can leak between sessions through a long-lived singleton.
- The server checks the tenant on every request as well. The device-side
  split is defence in depth, not the only line.

## Consequences

- Cross-tenant leaks through local queries are impossible by construction.
- Removing a tenant from a device is "delete one file".
- Cross-tenant reporting on a device is not possible. That is a deliberate
  choice, because it belongs on the server.
- **Not done:** encryption at rest (SQLCipher). That is the next step if a
  customer requires it.
