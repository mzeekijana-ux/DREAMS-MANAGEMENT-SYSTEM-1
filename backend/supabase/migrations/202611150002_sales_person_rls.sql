-- Sales-person-scoped records. Do not store sales in the generic app_records table:
-- ownership must be a server-enforced auth user ID, not a client-provided name/role.

create table if not exists public.sales_records (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id text not null,
  salesperson_user_id uuid not null,
  payload jsonb not null,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (organization_id, sale_id),
  constraint sales_records_salesperson_membership_fk
    foreign key (organization_id, salesperson_user_id)
    references public.memberships (organization_id, user_id) on delete restrict
);

create index if not exists sales_records_owner_date_idx
  on public.sales_records (organization_id, salesperson_user_id, created_at desc);

alter table public.sales_records enable row level security;

-- Sales persons may read only their own rows, and only while they have an active
-- sales-person membership in the organization. Managers with existing sales-domain
-- read access may review rows for that organization.
drop policy if exists sales_records_read_scoped on public.sales_records;
create policy sales_records_read_scoped on public.sales_records
  for select to authenticated using (
    (
      salesperson_user_id = (select auth.uid())
      and exists (
        select 1
        from public.memberships m
        where m.organization_id = sales_records.organization_id
          and m.user_id = (select auth.uid())
          and m.active
          and m.role in ('rsp', 'ssp')
      )
    )
    or public.has_domain_access(organization_id, 'sales', false)
  );

-- Sales persons can create a sale only for themselves. Managers with sales write
-- access may record a sale for an active, organization-member sales person.
drop policy if exists sales_records_insert_scoped on public.sales_records;
create policy sales_records_insert_scoped on public.sales_records
  for insert to authenticated with check (
    created_by = (select auth.uid())
    and (
      (
        salesperson_user_id = (select auth.uid())
        and exists (
          select 1
          from public.memberships m
          where m.organization_id = sales_records.organization_id
            and m.user_id = (select auth.uid())
            and m.active
            and m.role in ('rsp', 'ssp')
        )
      )
      or (
        public.has_domain_access(organization_id, 'sales', true)
        and exists (
          select 1
          from public.memberships m
          where m.organization_id = sales_records.organization_id
            and m.user_id = sales_records.salesperson_user_id
            and m.active
            and m.role in ('rsp', 'ssp')
        )
      )
    )
  );

-- Only managers with sales write permission can update or delete sales. No
-- salesperson update/delete policy is provided, preventing seller reassignment.
drop policy if exists sales_records_update_manager on public.sales_records;
create policy sales_records_update_manager on public.sales_records
  for update to authenticated
  using (public.has_domain_access(organization_id, 'sales', true))
  with check (
    public.has_domain_access(organization_id, 'sales', true)
    and exists (
      select 1
      from public.memberships m
      where m.organization_id = sales_records.organization_id
        and m.user_id = sales_records.salesperson_user_id
        and m.active
        and m.role in ('rsp', 'ssp')
    )
  );

drop policy if exists sales_records_delete_manager on public.sales_records;
create policy sales_records_delete_manager on public.sales_records
  for delete to authenticated using (
    public.has_domain_access(organization_id, 'sales', true)
  );
