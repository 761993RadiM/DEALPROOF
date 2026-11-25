
-- DEALPROOF foundational schema.
-- Subsequent migrations align constraints, invitation flow, audit snapshots and RLS helpers.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.agreements (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id),
  title text not null,
  description text,
  currency text not null default 'CZK',
  status text not null default 'draft'
    check (status in ('draft','shared','accepted','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.agreement_items (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1 check (quantity > 0),
  unit text not null default 'ks',
  unit_price numeric not null default 0 check (unit_price >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.agreement_participants (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  email text,
  role text not null default 'participant' check (role in ('owner','participant')),
  invited_at timestamptz not null default now(),
  joined_at timestamptz,
  unique (agreement_id,user_id)
);

create table if not exists public.amendments (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  description text not null,
  price_delta numeric not null default 0,
  due_date date,
  status text not null default 'draft'
    check (status in ('draft','proposed','accepted','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.amendment_signatures (
  id uuid primary key default gen_random_uuid(),
  amendment_id uuid not null references public.amendments(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  decision text not null check (decision in ('accepted','rejected')),
  signed_at timestamptz not null default now(),
  unique (amendment_id,user_id)
);

create index if not exists agreement_items_agreement_idx
  on public.agreement_items(agreement_id);
create index if not exists agreement_participants_user_idx
  on public.agreement_participants(user_id);
create index if not exists agreements_created_by_idx
  on public.agreements(created_by);
create index if not exists amendments_agreement_idx
  on public.amendments(agreement_id);
create index if not exists amendments_created_by_idx
  on public.amendments(created_by);
create index if not exists amendment_signatures_user_idx
  on public.amendment_signatures(user_id);

create or replace function public.is_agreement_member(target_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.agreements a
    where a.id = target_id and a.created_by = auth.uid()
  ) or exists (
    select 1 from public.agreement_participants p
    where p.agreement_id = target_id and p.user_id = auth.uid()
  );
$$;

create or replace function public.is_agreement_owner(target_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.agreements a
    where a.id = target_id and a.created_by = auth.uid()
  );
$$;

create or replace function public.is_agreement_draft(target_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.agreements a
    where a.id = target_id
      and a.created_by = auth.uid()
      and a.status = 'draft'
  );
$$;

revoke all on function public.is_agreement_member(uuid) from public,anon;
revoke all on function public.is_agreement_owner(uuid) from public,anon;
revoke all on function public.is_agreement_draft(uuid) from public,anon;
grant execute on function public.is_agreement_member(uuid) to authenticated;
grant execute on function public.is_agreement_owner(uuid) to authenticated;
grant execute on function public.is_agreement_draft(uuid) to authenticated;

create or replace function public.add_agreement_owner()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.agreement_participants(agreement_id,user_id,role,joined_at)
  values(new.id,new.created_by,'owner',pg_catalog.now());
  return new;
end;
$$;
revoke all on function public.add_agreement_owner() from public,anon,authenticated;

drop trigger if exists agreement_owner_trigger on public.agreements;
create trigger agreement_owner_trigger
after insert on public.agreements
for each row execute function public.add_agreement_owner();

alter table public.agreements enable row level security;
alter table public.agreement_items enable row level security;
alter table public.agreement_participants enable row level security;
alter table public.amendments enable row level security;
alter table public.amendment_signatures enable row level security;

grant select,insert,update,delete on public.agreements to authenticated;
grant select,insert,update,delete on public.agreement_items to authenticated;
grant select,insert,update,delete on public.agreement_participants to authenticated;
grant select,insert,update,delete on public.amendments to authenticated;
grant select,insert,update,delete on public.amendment_signatures to authenticated;

drop policy if exists agreement_select on public.agreements;
create policy agreement_select on public.agreements
for select to authenticated using (public.is_agreement_member(id));
drop policy if exists agreement_insert on public.agreements;
create policy agreement_insert on public.agreements
for insert to authenticated with check (created_by = (select auth.uid()));
drop policy if exists agreement_delete on public.agreements;
create policy agreement_delete on public.agreements
for delete to authenticated using (created_by = (select auth.uid()) and status='draft');
drop policy if exists agreement_update on public.agreements;
create policy agreement_update on public.agreements
for update to authenticated
using (created_by = (select auth.uid()) and status='draft')
with check (created_by = (select auth.uid()) and status in ('draft','shared'));

drop policy if exists items_select on public.agreement_items;
create policy items_select on public.agreement_items
for select to authenticated using (public.is_agreement_member(agreement_id));
drop policy if exists items_insert on public.agreement_items;
create policy items_insert on public.agreement_items
for insert to authenticated with check (public.is_agreement_draft(agreement_id));
drop policy if exists items_update on public.agreement_items;
create policy items_update on public.agreement_items
for update to authenticated
using (public.is_agreement_draft(agreement_id))
with check (public.is_agreement_draft(agreement_id));
drop policy if exists items_delete on public.agreement_items;
create policy items_delete on public.agreement_items
for delete to authenticated using (public.is_agreement_draft(agreement_id));

drop policy if exists participants_select on public.agreement_participants;
create policy participants_select on public.agreement_participants
for select to authenticated using (public.is_agreement_member(agreement_id));

drop policy if exists amendments_select on public.amendments;
create policy amendments_select on public.amendments
for select to authenticated using (public.is_agreement_member(agreement_id));
drop policy if exists amendments_insert on public.amendments;
create policy amendments_insert on public.amendments
for insert to authenticated
with check (
  created_by=(select auth.uid())
  and status='proposed'
  and public.is_agreement_member(agreement_id)
);
drop policy if exists amendments_update on public.amendments;
create policy amendments_update on public.amendments
for update to authenticated
using (created_by=(select auth.uid()) and status='draft')
with check (created_by=(select auth.uid()) and status in ('draft','proposed'));
