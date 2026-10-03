# 3. Check permissions, not roles; enforce in the domain

- Status: accepted

## Context

ERP customers ask for new roles ("supervisor: can count, cannot approve").
If screens check `role == manager`, every new role means hunting through the
UI.

## Decision

- `Permission` is the unit of authorization (`recordMovement`, `countStock`,
  `approveAdjustment`, …). A single map, `rolePermissions`, assigns
  permissions to roles.
- The **UI** hides what the user cannot do (`PermissionGate`, navigation
  tabs filtered by permission).
- The **use cases** check again and throw `PermissionDenied`. Hidden is not
  the same as secure: a stale screen, a deep link or a bug must not let a
  viewer write.
- The **server** checks again (`Forbidden`), because the device is never
  trusted.

## The count-approval rule

`VariancePolicy` lets clerks apply routine differences (≤ 5 units and
≤ 10 %). Anything larger becomes an approval request for a manager. This is
the standard control against stock "disappearing" through adjustments.

An approval applies the **variance**, not the counted figure. Stock may have
moved between the count and the approval, and overwriting it would erase
those movements.
