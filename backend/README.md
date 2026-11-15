# Backend foundation (Supabase)

The repository now has a **connected cloud sales frontend** at the GitHub Pages root, but the complete legacy management system is not yet migrated. The legacy HTML app still uses browser local storage. Do not enter sensitive operational, accounting, HR, or personal data in that legacy app expecting cloud sync or security.

## Supabase setup

1. In Supabase, apply the migrations in order from **SQL Editor**:
   - `supabase/migrations/202611150001_initial_schema.sql`
   - `supabase/migrations/202611150002_sales_person_rls.sql`
2. In **Authentication → URL Configuration**, add the deployed GitHub Pages root URL to the allowed redirect URLs, for example `https://mzeekijana-ux.github.io/DREAMS-MANAGEMENT-SYSTEM-1/`. If using another repository/site URL, enter that exact URL instead.
3. Invite existing users in **Authentication → Users**. The frontend requests a magic link for an existing account (it does not create accounts).
4. Provision each person with one active row in `public.memberships` for the organization's UUID and their Auth user UUID. The role must be server-managed; never rely on the client “View as” selector.
5. Set the intended SMTP/email provider in Supabase Auth and test delivery. The browser app uses the project's public/publishable key; no service-role key or database password belongs in this repo.
6. Open the deployed site root, request a sign-in link, and test with at least two salesperson users. Confirm each only sees their own cloud sales and cannot forge another `salesperson_user_id`. Test manager access separately.

## Connected functionality

- Root `index.html` uses Supabase Auth magic-link sign-in.
- `frontend/supabase-app.js` loads the signed-in user's active organization memberships and displays the server-provided role.
- Salespeople can create their own cloud sales in `public.sales_records`; ownership is the authenticated Supabase user UUID.
- The frontend reads the dedicated `sales_records` table. Supabase RLS is the security boundary and remains authoritative even if a browser request is altered.
- Only the public/publishable key is included in client code. It is expected to be public; data access is protected by RLS.

## Important limits

- The original management app opened from the root previously; it is now linked from the cloud portal as a legacy, browser-local app. It is not authenticated by this portal if opened directly and is not synchronized to Supabase.
- Cloud sales records are separate from the legacy app's local sales. Existing local records are not automatically migrated.
- The current frontend permits active `rsp` and `ssp` accounts to submit their own sales. Managers with RLS read permission can view the organization's sale records. The frontend does not yet include manager entry/edit forms, stock synchronization, or integration of the legacy sales forms.
- Review role/domain permissions, test every RLS policy, configure production email and redirects, and verify database backups before using real business information.
