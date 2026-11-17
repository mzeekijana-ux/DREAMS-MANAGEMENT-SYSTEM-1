# Salesperson dashboard and access boundary

## Current safe design

The root portal (`index.html` + `frontend/supabase-app.js`) is the salesperson-facing cloud sales experience. Keep it as a focused sales dashboard rather than exposing the legacy management application to `rsp` or `ssp` users. The legacy management HTML stores a broad set of management records in `public.app_records`; salesperson roles are intentionally denied access to that table by `has_domain_access()` in migration `202611150001_initial_schema.sql`.

Salespeople may use `public.sales_records` only:

- `SELECT`: their own rows, while they have an active `rsp`/`ssp` membership in the organization.
- `INSERT`: rows for themselves only, with `created_by = auth.uid()`.
- `UPDATE` and `DELETE`: no salesperson policy; managers with the appropriate server-side sales permission may manage rows.

These rules are enforced by Supabase Row Level Security. Hiding a tab, changing the client role selector, or adding a link to `management.html` is not an authorization control. Do not grant `rsp`/`ssp` access to generic `app_records` merely to make the legacy dashboard load; its records are not scoped to a verified salesperson identity.

## If a salesperson needs a management-style home screen

Build a small, separate salesperson view using only `sales_records` and, if required, additional dedicated tables whose ownership and organization scope are enforced by RLS. Do not load generic `app_records` into that view. Server policies must bind ownership to `auth.uid()` and an active membership, and managers' access should be explicitly granted per role. Keep HR, accounting, treasury, workflows, risk, and other sensitive domains unavailable to salesperson roles.

The current Cloud Sales portal already follows this data boundary. A future unified login can route users to the appropriate experience after reading their active server-managed membership: `rsp`/`ssp` to the sales portal; authorized management roles to the management app. Do not redirect salespeople into the management app unless the app is redesigned to avoid querying `app_records` for them.

## Pre-deployment verification checklist

Run against a non-production Supabase project or test users before releasing policy changes:

1. Create two active salesperson test accounts in the same organization and one management test account. Also prepare an inactive salesperson membership.
2. As salesperson A, confirm the portal lists only A's sales; insert a sale as A and verify it succeeds.
3. As A, attempt to select salesperson B's rows and insert a row with B's `salesperson_user_id`; both must be blocked by RLS.
4. As A, attempt `UPDATE` and `DELETE` on `sales_records`; both must be denied.
5. As the inactive salesperson, verify sales reads and inserts are denied.
6. As the manager, verify only the intended organization-scoped sales permissions work.
7. As either salesperson, attempt to read and write `app_records` in every sensitive domain (including `hr`, `accounting`, `treasury`, `workflows`, and `risks`); those requests must return no rows or be denied.
8. Confirm the login UI does not offer a client-side role override as an access control, and test direct API requests as well as visible pages.

The repository's SQL files are migration sources, not proof that the live Supabase project has applied them. Review migration order and apply reviewed migrations to the intended Supabase project through its approved deployment process; then run the checks above. Never put a Supabase service-role key in the browser or repository.
