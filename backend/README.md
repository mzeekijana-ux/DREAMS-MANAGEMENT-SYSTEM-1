# Backend foundation (Supabase)

This directory starts the backend setup for the static management app. It is **not yet connected to the deployed frontend** and is not live until a Supabase project is configured, migrations are reviewed/applied, users are provisioned, and the app's local-storage reads/writes are replaced with authenticated database calls.

## Why Supabase

Supabase provides managed PostgreSQL, authentication, and row-level security (RLS). The current app is a static HTML page that saves records in each browser's local storage. Its “View as” selector is only a UI filter, not sign-in or authorization. Server-managed memberships and database RLS are required for real access control.

## Setup checklist

1. Create a Supabase project in an account you control and choose an appropriate data region.
2. In the Supabase SQL Editor, review and apply migrations in order:
   - `supabase/migrations/202611150001_initial_schema.sql`
   - `supabase/migrations/202611150002_sales_person_rls.sql`
3. Create an organization row, then invite users through Supabase Auth. Assign each user a membership using the SQL Editor or another trusted admin-only process. Never let the browser create or change its own role.
4. Review the role/domain matrix in `has_domain_access` against actual job responsibilities and privacy requirements before adding real data.
5. Integrate Supabase Auth and database calls into the frontend. Use only the project's public/publishable key in browser code; **never** place a service-role key or database password in this repository or frontend.
6. Store individual sales in `public.sales_records`, setting `salesperson_user_id` to the authenticated user's UUID (`auth.uid()` in trusted SQL / server context), not a display name or a client-selected role. Test with two salesperson accounts and verify each sees only its own rows. Also test manager access, cross-organization access, and attempts to forge another seller's ID.
7. Do not use the generic `app_records` table for salesperson-accessible sales: the generic table is intentionally not granted to `rsp`/`ssp`, and its JSON payload cannot enforce per-sale ownership.

## Sales-person RLS behavior

The second migration enables RLS on `public.sales_records` and adds these policies:

- Active `rsp` and `ssp` members can select only rows whose `salesperson_user_id` is their own authenticated user ID.
- Salespeople may insert rows only for themselves; they cannot update or delete rows.
- Roles that already have sales-domain read/write access may review or manage rows for members in their organization.
- A composite foreign key ensures each record's salesperson is a member of that same organization.

The `ssp` role in the earlier generic domain-access helper remains without access to `app_records`. Sales-person access is deliberately limited to the dedicated sales table until other records get equivalent ownership-level policies. The role code alone is not sufficient: the person must be invited to Supabase Auth and have an active organization membership.

## Current authorization assumptions

| Role | Intended access in starter policies |
| --- | --- |
| MD / Board (`md`) | All listed domains |
| Group Finance Manager (`gfm`) | All except HR |
| Internal Auditor (`ia`) | Read-only, all except HR |
| Treasury Controller (`trc`) | Treasury, accounting and operational review domains; limited writes |
| Regional Gas Manager (`rgm`) | Gas, sales, inventory, daily reports; limited writes |
| Yas/Mixx Manager (`ymm`) | Yas/Mixx, float, sales, daily reports; limited writes |
| Wakala Development Manager (`wdm`) | Yas/Mixx and float review; limited writes |
| Accountant (`acc`) | Accounting and related review domains; limited writes |
| HR Manager (`hr`) | HR only |
| Procurement Officer (`po`) | Inventory and gas stock review; limited writes |
| Route/Shop Sales Person (`rsp`, `ssp`) | Own rows in `sales_records` only; no generic `app_records` access |

These are provisional least-privilege defaults, not a final business approval. `app_records` stores one JSON record per domain; do not store the complete app state as one shared JSON blob, because that would defeat domain-level privacy.

## Not done yet

- This is schema and policy work, not a finished production backend.
- There is no Supabase project configuration, login UI, invite flow, frontend synchronization, migration of browser-local records, or deployment automation in this repository yet.
- Existing browser data remains in that browser. It is not automatically transferred or backed up by this scaffold.
- Before production, add automated RLS tests, audit logging/retention policy, backups, and a reviewed recovery process. Review the full role/domain matrix with the organization before entering sensitive data.
