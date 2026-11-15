-- Supabase/PostgreSQL foundation for authenticated, multi-tenant app data.
-- Apply in a Supabase project only after reviewing the authorization matrix in backend/README.md.

create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.memberships (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in (
    'md', 'gfm', 'trc', 'rgm', 'ymm', 'wdm', 'ia', 'acc', 'hr', 'po', 'rsp', 'ssp'
  )),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

-- Records are isolated by organization and business domain. Keep HR and accounting
-- in separate domains; never put the entire localStorage app state in one row.
create table if not exists public.app_records (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  domain text not null check (domain in (
    'management', 'gas_operations', 'yas_operations', 'float', 'daily_reports',
    'sales', 'inventory', 'treasury', 'accounting', 'hr', 'workflows', 'risks'
  )),
  record_id text not null,
  payload jsonb not null,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, domain, record_id)
);

create index if not exists app_records_org_domain_updated_idx
  on public.app_records (organization_id, domain, updated_at desc);

-- Authorization is evaluated from server-managed memberships, not a role selector
-- or user-editable profile field. Membership rows must be provisioned by an admin.
create or replace function public.has_domain_access(
  p_organization_id uuid,
  p_domain text,
  p_write boolean default false
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
      and m.active
      and case
        when p_write then
          (m.role = 'md')
          or (m.role = 'gfm' and p_domain in ('management','gas_operations','yas_operations','float','daily_reports','sales','inventory','treasury','accounting','workflows','risks'))
          or (m.role = 'trc' and p_domain in ('treasury','accounting','daily_reports','risks'))
          or (m.role = 'rgm' and p_domain in ('gas_operations','daily_reports','sales','inventory'))
          or (m.role = 'ymm' and p_domain in ('yas_operations','float','daily_reports','sales'))
          or (m.role = 'wdm' and p_domain in ('float','daily_reports'))
          or (m.role = 'acc' and p_domain in ('accounting','daily_reports'))
          or (m.role = 'hr' and p_domain = 'hr')
          or (m.role = 'po' and p_domain = 'inventory')
        else
          (m.role = 'md')
          or (m.role = 'gfm' and p_domain <> 'hr')
          or (m.role = 'ia' and p_domain <> 'hr')
          or (m.role = 'trc' and p_domain in ('treasury','accounting','gas_operations','yas_operations','float','daily_reports','inventory','sales','workflows','risks'))
          or (m.role = 'rgm' and p_domain in ('gas_operations','daily_reports','sales','inventory','workflows','risks'))
          or (m.role = 'ymm' and p_domain in ('yas_operations','float','daily_reports','sales','workflows','risks'))
          or (m.role = 'wdm' and p_domain in ('yas_operations','float','daily_reports','risks'))
          or (m.role = 'acc' and p_domain in ('accounting','daily_reports','inventory','treasury'))
          or (m.role = 'hr' and p_domain = 'hr')
          or (m.role = 'po' and p_domain in ('inventory','gas_operations','daily_reports'))
          -- Sales-person roles are deliberately denied here until records can be
          -- scoped to a verified person identity, rather than a client-side selector.
        end
  );
$$;

revoke all on function public.has_domain_access(uuid, text, boolean) from public;
grant execute on function public.has_domain_access(uuid, text, boolean) to authenticated;

alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.app_records enable row level security;

-- Users can see only their own active membership rows. Provisioning is performed
-- by a trusted administrator through the Supabase dashboard or a secured admin tool.
drop policy if exists memberships_read_self on public.memberships;
create policy memberships_read_self on public.memberships
  for select to authenticated using (user_id = (select auth.uid()));

-- No client-side organization or membership creation/update policies are defined.
drop policy if exists organizations_read_member on public.organizations;
create policy organizations_read_member on public.organizations
  for select to authenticated using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = organizations.id
        and m.user_id = (select auth.uid())
        and m.active
    )
  );

drop policy if exists app_records_read_authorized on public.app_records;
create policy app_records_read_authorized on public.app_records
  for select to authenticated using (
    public.has_domain_access(organization_id, domain, false)
  );

drop policy if exists app_records_insert_authorized on public.app_records;
create policy app_records_insert_authorized on public.app_records
  for insert to authenticated with check (
    public.has_domain_access(organization_id, domain, true)
    and created_by = (select auth.uid())
    and updated_by = (select auth.uid())
  );

drop policy if exists app_records_update_authorized on public.app_records;
create policy app_records_update_authorized on public.app_records
  for update to authenticated
  using (public.has_domain_access(organization_id, domain, true))
  with check (
    public.has_domain_access(organization_id, domain, true)
    and updated_by = (select auth.uid())
  );

drop policy if exists app_records_delete_authorized on public.app_records;
create policy app_records_delete_authorized on public.app_records
  for delete to authenticated using (
    public.has_domain_access(organization_id, domain, true)
  );

-- Keep timestamps current for client updates.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  new.updated_by = (select auth.uid());
  return new;
end;
$$;

drop trigger if exists app_records_set_updated_at on public.app_records;
create trigger app_records_set_updated_at
  before update on public.app_records
  for each row execute function public.set_updated_at();
