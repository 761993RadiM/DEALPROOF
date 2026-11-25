
-- Keep RLS helper functions out of the exposed public API schema.
-- SECURITY DEFINER remains limited to internal private helpers to avoid RLS recursion.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_agreement_member(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.agreements a
    where a.id = target_id
      and a.created_by = auth.uid()
  )
  or exists (
    select 1
    from public.agreement_participants p
    where p.agreement_id = target_id
      and p.user_id = auth.uid()
  );
$$;

create or replace function private.is_agreement_owner(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.agreements a
    where a.id = target_id
      and a.created_by = auth.uid()
  );
$$;

create or replace function private.is_agreement_draft(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.agreements a
    where a.id = target_id
      and a.created_by = auth.uid()
      and a.status = 'draft'
  );
$$;

revoke all on function private.is_agreement_member(uuid) from public, anon;
revoke all on function private.is_agreement_owner(uuid) from public, anon;
revoke all on function private.is_agreement_draft(uuid) from public, anon;
grant execute on function private.is_agreement_member(uuid) to authenticated;
grant execute on function private.is_agreement_owner(uuid) to authenticated;
grant execute on function private.is_agreement_draft(uuid) to authenticated;

-- Rebind each policy to the private helper functions.
alter policy agreement_select on public.agreements
  using (private.is_agreement_member(id));

alter policy items_delete on public.agreement_items
  using (private.is_agreement_draft(agreement_id));
alter policy items_insert on public.agreement_items
  with check (private.is_agreement_draft(agreement_id));
alter policy items_select on public.agreement_items
  using (private.is_agreement_member(agreement_id));
alter policy items_update on public.agreement_items
  using (private.is_agreement_draft(agreement_id))
  with check (private.is_agreement_draft(agreement_id));

alter policy participants_invite on public.agreement_participants
  with check (
    private.is_agreement_owner(agreement_id)
    and private.is_agreement_draft(agreement_id)
    and user_id is null
    and email is not null
    and length(btrim(email)) > 3
    and (
      select count(*)
      from public.agreement_participants p
      where p.agreement_id = agreement_participants.agreement_id
    ) < 2
    and not exists (
      select 1
      from public.agreement_participants p
      where p.agreement_id = agreement_participants.agreement_id
        and lower(btrim(p.email)) = lower(btrim(agreement_participants.email))
    )
  );
alter policy participants_select on public.agreement_participants
  using (private.is_agreement_member(agreement_id));

alter policy agreement_signatures_select on public.agreement_signatures
  using (private.is_agreement_member(agreement_id));
alter policy agreement_signatures_insert on public.agreement_signatures
  with check (
    signer_id = (select auth.uid())
    and private.is_agreement_member(agreement_id)
    and exists (
      select 1 from public.agreements a
      where a.id = agreement_signatures.agreement_id
        and a.status = 'shared'
        and (a.content_hash is null or a.content_hash = agreement_signatures.terms_hash)
    )
  );

alter policy amendments_select on public.amendments
  using (private.is_agreement_member(agreement_id));
alter policy amendments_insert on public.amendments
  with check (
    created_by = (select auth.uid())
    and status = 'proposed'
    and private.is_agreement_member(agreement_id)
    and exists (
      select 1 from public.agreements a
      where a.id = amendments.agreement_id
        and a.status in ('shared','accepted')
    )
  );

alter policy signatures_select on public.amendment_signatures
  using (
    exists (
      select 1 from public.amendments a
      where a.id = amendment_signatures.amendment_id
        and private.is_agreement_member(a.agreement_id)
    )
  );
alter policy signatures_insert on public.amendment_signatures
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.amendments a
      where a.id = amendment_signatures.amendment_id
        and a.status = 'proposed'
        and a.created_by <> (select auth.uid())
        and private.is_agreement_member(a.agreement_id)
    )
  );

alter policy agreement_versions_select on public.agreement_versions
  using (private.is_agreement_member(agreement_id));
alter policy agreement_versions_insert on public.agreement_versions
  with check (
    created_by = (select auth.uid())
    and private.is_agreement_owner(agreement_id)
    and private.is_agreement_draft(agreement_id)
  );

-- The helpers are now only callable from the private schema through RLS.
revoke all on function public.is_agreement_member(uuid) from public, anon, authenticated;
revoke all on function public.is_agreement_owner(uuid) from public, anon, authenticated;
revoke all on function public.is_agreement_draft(uuid) from public, anon, authenticated;

-- The invitation RPC is exposed as an invoker-rights wrapper only.
create or replace function private.accept_agreement_invitations()
returns setof uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
begin
  if v_user_id is null then
    raise exception 'Pro přijetí pozvánky se nejprve přihlas.';
  end if;

  select lower(btrim(u.email))
    into v_email
  from auth.users u
  where u.id = v_user_id
    and u.email_confirmed_at is not null;

  if v_email is null then
    raise exception 'Nejprve potvrď e-mailovou adresu svého účtu.';
  end if;

  return query
  update public.agreement_participants p
     set user_id = v_user_id,
         joined_at = pg_catalog.now()
   where p.user_id is null
     and p.email is not null
     and lower(btrim(p.email)) = v_email
     and exists (
       select 1 from public.agreements a
       where a.id = p.agreement_id
         and a.status = 'shared'
     )
     and not exists (
       select 1 from public.agreement_participants mine
       where mine.agreement_id = p.agreement_id
         and mine.user_id = v_user_id
     )
  returning p.agreement_id;
end;
$$;

revoke all on function private.accept_agreement_invitations() from public, anon;
grant execute on function private.accept_agreement_invitations() to authenticated;

create or replace function public.accept_agreement_invitations()
returns setof uuid
language sql
security invoker
set search_path = ''
as $$
  select * from private.accept_agreement_invitations();
$$;

revoke all on function public.accept_agreement_invitations() from public, anon;
grant execute on function public.accept_agreement_invitations() to authenticated;
