-- DEALPROOF cloud data model
-- Run this migration in the Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.agreements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  amount text not null default '',
  owner_id uuid not null references auth.users(id),
  invite_code uuid not null unique default gen_random_uuid(),
  status text not null default 'open' check (status in ('open','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.agreement_participants (
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null check (role in ('owner','counterparty')),
  joined_at timestamptz not null default now(),
  primary key (agreement_id, user_id)
);

create table if not exists public.agreement_signatures (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  signer_id uuid not null references auth.users(id),
  signer_name text not null,
  signature_png_base64 text not null,
  terms_hash text not null,
  signed_at timestamptz not null default now(),
  unique (agreement_id, signer_id)
);

create table if not exists public.amendments (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  proposer_id uuid not null references auth.users(id),
  description text not null,
  amount_change text not null default '',
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  proposed_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id)
);

create index if not exists agreement_participants_user_idx on public.agreement_participants(user_id);
create index if not exists amendments_agreement_idx on public.amendments(agreement_id, proposed_at);

create or replace function public.is_agreement_participant(target_agreement uuid)
returns boolean language sql security definer stable set search_path = public
as $$
  select exists (
    select 1 from public.agreement_participants
    where agreement_id = target_agreement and user_id = auth.uid()
  );
$$;

alter table public.profiles enable row level security;
alter table public.agreements enable row level security;
alter table public.agreement_participants enable row level security;
alter table public.agreement_signatures enable row level security;
alter table public.amendments enable row level security;

create policy "profiles readable by signed-in users" on public.profiles
for select to authenticated using (true);
create policy "users insert own profile" on public.profiles
for insert to authenticated with check (id = auth.uid());
create policy "users update own profile" on public.profiles
for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "participants read agreements" on public.agreements
for select to authenticated using (public.is_agreement_participant(id));
create policy "signed-in users create agreements" on public.agreements
for insert to authenticated with check (owner_id = auth.uid());
-- Agreements are intentionally not editable after creation; changes must be proposed as amendments.

create policy "participants read membership" on public.agreement_participants
for select to authenticated using (public.is_agreement_participant(agreement_id));
drop policy if exists "owner adds self as participant" on public.agreement_participants;
create policy "owner adds self as participant" on public.agreement_participants
for insert to authenticated with check (
  user_id = auth.uid()
  and role = 'owner'
  and exists (
    select 1 from public.agreements a
    where a.id = agreement_id and a.owner_id = auth.uid()
  )
);

-- Joining by invite code is performed through this controlled RPC.
create or replace function public.join_agreement_by_code(code uuid, participant_name text default '')
returns uuid language plpgsql security definer set search_path = public
as $$
declare target_id uuid;
begin
  if auth.uid() is null then raise exception 'Přihlášení je povinné'; end if;
  select id into target_id from public.agreements where invite_code = code;
  if target_id is null then raise exception 'Pozvánka nebyla nalezena'; end if;
  insert into public.agreement_participants(agreement_id,user_id,display_name,role)
  values(target_id,auth.uid(),coalesce(participant_name,''),'counterparty')
  on conflict (agreement_id,user_id) do nothing;
  return target_id;
end;
$$;
grant execute on function public.join_agreement_by_code(uuid,text) to authenticated;

create policy "participants read signatures" on public.agreement_signatures
for select to authenticated using (public.is_agreement_participant(agreement_id));
create policy "participants sign once" on public.agreement_signatures
for insert to authenticated with check (
  signer_id = auth.uid() and public.is_agreement_participant(agreement_id)
);

create policy "participants read amendments" on public.amendments
for select to authenticated using (public.is_agreement_participant(agreement_id));
create policy "participants propose amendments" on public.amendments
for insert to authenticated with check (
  proposer_id = auth.uid() and public.is_agreement_participant(agreement_id)
);
create policy "other participant decides amendments" on public.amendments
for update to authenticated using (
  public.is_agreement_participant(agreement_id) and proposer_id <> auth.uid()
) with check (
  public.is_agreement_participant(agreement_id) and decided_by = auth.uid()
);

-- Immutable signatures: no update or delete policies are intentionally provided.
