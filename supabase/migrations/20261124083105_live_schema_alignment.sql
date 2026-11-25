
-- DEALPROOF live-schema alignment migration.
-- Creates the signature workflow, invite policy, approval triggers and grants.
create table if not exists public.agreement_signatures (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  signer_id uuid not null references auth.users(id),
  signer_name text not null,
  signature_png_base64 text not null,
  terms_hash text not null,
  signed_at timestamptz not null default now(),
  constraint agreement_signatures_one_per_user unique (agreement_id, signer_id),
  constraint agreement_signatures_terms_hash_sha256 check (terms_hash ~ '^[0-9a-f]{64}$')
);

alter table public.agreement_signatures enable row level security;
grant select, insert on public.agreement_signatures to authenticated;

drop policy if exists agreement_signatures_select on public.agreement_signatures;
create policy agreement_signatures_select
on public.agreement_signatures
for select to authenticated
using (public.is_agreement_member(agreement_id));

drop policy if exists agreement_signatures_insert on public.agreement_signatures;
create policy agreement_signatures_insert
on public.agreement_signatures
for insert to authenticated
with check (
  signer_id = (select auth.uid())
  and public.is_agreement_member(agreement_id)
  and exists (
    select 1 from public.agreements a
    where a.id = agreement_signatures.agreement_id and a.status = 'shared'
  )
);

create index if not exists agreement_signatures_signer_idx on public.agreement_signatures(signer_id);
create index if not exists agreement_signatures_agreement_idx on public.agreement_signatures(agreement_id);
create index if not exists agreement_items_agreement_idx on public.agreement_items(agreement_id);
create index if not exists agreement_participants_user_idx on public.agreement_participants(user_id);
create index if not exists agreements_created_by_idx on public.agreements(created_by);
create index if not exists amendments_agreement_idx on public.amendments(agreement_id);
create index if not exists amendments_created_by_idx on public.amendments(created_by);
create index if not exists amendment_signatures_user_idx on public.amendment_signatures(user_id);
create index if not exists agreement_participants_pending_email_idx
  on public.agreement_participants (lower(email)) where user_id is null and email is not null;

drop policy if exists participants_invite on public.agreement_participants;
create policy participants_invite
on public.agreement_participants
for insert to authenticated
with check (
  public.is_agreement_owner(agreement_id)
  and public.is_agreement_draft(agreement_id)
  and user_id is null
  and email is not null
  and length(btrim(email)) > 3
  and (
    select count(*) from public.agreement_participants p
    where p.agreement_id = agreement_participants.agreement_id
  ) < 2
  and not exists (
    select 1 from public.agreement_participants p
    where p.agreement_id = agreement_participants.agreement_id
      and lower(btrim(p.email)) = lower(btrim(agreement_participants.email))
  )
);

create or replace function public.accept_agreement_invitations()
returns setof uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_email text;
begin
  if v_user_id is null then
    raise exception 'Pro přijetí pozvánky se nejprve přihlas.';
  end if;
  select lower(btrim(u.email)) into v_email
  from auth.users u
  where u.id = v_user_id and u.email_confirmed_at is not null;
  if v_email is null then
    raise exception 'Nejprve potvrď e-mailovou adresu svého účtu.';
  end if;
  return query
  update public.agreement_participants p
     set user_id = v_user_id, joined_at = pg_catalog.now()
   where p.user_id is null
     and p.email is not null
     and lower(btrim(p.email)) = v_email
     and exists (
       select 1 from public.agreements a
       where a.id = p.agreement_id and a.status = 'shared'
     )
     and not exists (
       select 1 from public.agreement_participants mine
       where mine.agreement_id = p.agreement_id and mine.user_id = v_user_id
     )
  returning p.agreement_id;
end;
$function$;

revoke all on function public.accept_agreement_invitations() from public, anon;
grant execute on function public.accept_agreement_invitations() to authenticated;

create or replace function public.sync_agreement_acceptance()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
declare
  v_agreement_id uuid := new.agreement_id;
begin
  update public.agreements a
     set status = 'accepted'
   where a.id = v_agreement_id
     and a.status = 'shared'
     and (
       select count(*) from public.agreement_participants p
       where p.agreement_id = v_agreement_id and p.user_id is not null
     ) = 2
     and (
       select count(distinct s.signer_id) from public.agreement_signatures s
       where s.agreement_id = v_agreement_id
     ) = 2;
  return new;
end;
$function$;

drop trigger if exists agreement_signatures_sync_status on public.agreement_signatures;
create trigger agreement_signatures_sync_status
after insert on public.agreement_signatures
for each row execute function public.sync_agreement_acceptance();

drop trigger if exists agreement_participants_sync_status on public.agreement_participants;
create trigger agreement_participants_sync_status
after update of user_id on public.agreement_participants
for each row execute function public.sync_agreement_acceptance();

revoke all on function public.sync_agreement_acceptance() from public, anon, authenticated;

drop policy if exists signatures_insert on public.amendment_signatures;
create policy signatures_insert
on public.amendment_signatures
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.amendments a
    where a.id = amendment_signatures.amendment_id
      and a.status = 'proposed'
      and a.created_by <> (select auth.uid())
      and public.is_agreement_member(a.agreement_id)
  )
);

drop policy if exists amendments_insert on public.amendments;
create policy amendments_insert
on public.amendments
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and status = 'proposed'
  and public.is_agreement_member(agreement_id)
  and exists (
    select 1 from public.agreements a
    where a.id = amendments.agreement_id and a.status in ('shared', 'accepted')
  )
);

drop policy if exists amendments_update on public.amendments;
create policy amendments_update
on public.amendments
for update to authenticated
using (created_by = (select auth.uid()) and status = 'draft')
with check (created_by = (select auth.uid()) and status in ('draft', 'proposed'));

create or replace function public.apply_amendment_decision()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  update public.amendments a
     set status = new.decision
   where a.id = new.amendment_id
     and a.status = 'proposed'
     and a.created_by <> new.user_id;
  if not found then
    raise exception 'Dodatek již není k potvrzení nebo rozhodnutí není platné.';
  end if;
  return new;
end;
$function$;

drop trigger if exists amendment_signatures_apply_decision on public.amendment_signatures;
create trigger amendment_signatures_apply_decision
after insert on public.amendment_signatures
for each row execute function public.apply_amendment_decision();

revoke all on function public.apply_amendment_decision() from public, anon, authenticated;

create or replace function public.add_agreement_owner()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  insert into public.agreement_participants (agreement_id, user_id, role, joined_at)
  values (new.id, new.created_by, 'owner', pg_catalog.now());
  return new;
end;
$function$;

revoke all on function public.add_agreement_owner() from public, anon, authenticated;

grant select, insert, update, delete on public.agreements to authenticated;
grant select, insert on public.agreement_participants to authenticated;
grant select, insert, update, delete on public.agreement_items to authenticated;
grant select, insert, update on public.amendments to authenticated;
grant select, insert on public.amendment_signatures to authenticated;

drop policy if exists agreement_update on public.agreements;
create policy agreement_update
on public.agreements
for update to authenticated
using (created_by = (select auth.uid()) and status = 'draft')
with check (created_by = (select auth.uid()) and status in ('draft', 'shared'));
