
-- DEALPROOF: structured work-contract content and immutable publication snapshot.
-- This migration intentionally preserves the existing agreements and signature data.

alter table public.agreements
  add column if not exists template_key text,
  add column if not exists contract_data jsonb,
  add column if not exists contract_text text,
  add column if not exists content_hash text;

alter table public.agreement_items
  add column if not exists position integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.agreements'::regclass
      and conname = 'agreements_content_hash_sha256'
  ) then
    alter table public.agreements
      add constraint agreements_content_hash_sha256
      check (content_hash is null or content_hash ~ '^[0-9a-f]{64}$');
  end if;
end $$;

create table if not exists public.agreement_versions (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  template_key text not null,
  contract_data jsonb not null,
  contract_text text not null,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (agreement_id, version_no)
);

alter table public.agreement_versions enable row level security;
revoke all on public.agreement_versions from anon, public;
grant select, insert on public.agreement_versions to authenticated;

drop policy if exists agreement_versions_select on public.agreement_versions;
create policy agreement_versions_select
  on public.agreement_versions
  for select to authenticated
  using (public.is_agreement_member(agreement_id));

drop policy if exists agreement_versions_insert on public.agreement_versions;
create policy agreement_versions_insert
  on public.agreement_versions
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and public.is_agreement_owner(agreement_id)
    and public.is_agreement_draft(agreement_id)
  );

create or replace function public.reject_agreement_version_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Historickou verzi dohody nelze změnit ani odstranit.';
end;
$$;

drop trigger if exists agreement_versions_immutable on public.agreement_versions;
create trigger agreement_versions_immutable
before update or delete on public.agreement_versions
for each row execute function public.reject_agreement_version_mutation();

create or replace function public.reject_published_agreement_terms_change()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if old.status <> 'draft' and (
    new.title is distinct from old.title
    or new.description is distinct from old.description
    or new.currency is distinct from old.currency
    or new.template_key is distinct from old.template_key
    or new.contract_data is distinct from old.contract_data
    or new.contract_text is distinct from old.contract_text
    or new.content_hash is distinct from old.content_hash
  ) then
    raise exception 'Potvrzené znění dohody je neměnné. Změny proveďte samostatným dodatkem.';
  end if;
  return new;
end;
$$;

drop trigger if exists agreements_published_terms_immutable on public.agreements;
create trigger agreements_published_terms_immutable
before update of title, description, currency, template_key, contract_data, contract_text, content_hash
on public.agreements
for each row execute function public.reject_published_agreement_terms_change();

create or replace function public.create_work_agreement_with_invite(
  p_title text,
  p_description text,
  p_currency text,
  p_contract_data jsonb,
  p_contract_text text,
  p_items jsonb,
  p_invitee_email text
)
returns uuid
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
  v_auth_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_creator_role text;
  v_creator_email text;
  v_other_email text;
  v_item jsonb;
  v_description text;
  v_quantity numeric;
  v_unit text;
  v_unit_price numeric;
  v_position integer := 0;
  v_hash text;
begin
  if v_user is null then
    raise exception 'Nejprve se přihlas.';
  end if;
  if nullif(btrim(p_title), '') is null or char_length(p_title) > 180 then
    raise exception 'Název smlouvy musí mít 1 až 180 znaků.';
  end if;
  if p_contract_data is null or jsonb_typeof(p_contract_data) <> 'object' then
    raise exception 'Chybí strukturované údaje smlouvy.';
  end if;
  if p_contract_data ->> 'template_key' <> 'cz_work_contract'
     or p_contract_data ->> 'template_version' <> '1' then
    raise exception 'Nepodporovaná verze vzoru smlouvy.';
  end if;
  if nullif(btrim(p_contract_text), '') is null or char_length(p_contract_text) < 500
     or char_length(p_contract_text) > 50000 then
    raise exception 'Text smlouvy není úplný nebo překračuje povolenou délku.';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 100 then
    raise exception 'Smlouva musí obsahovat 1 až 100 rozpočtových položek.';
  end if;

  if nullif(btrim(p_contract_data #>> '{orderer,name}'), '') is null
     or nullif(btrim(p_contract_data #>> '{orderer,address}'), '') is null
     or nullif(btrim(p_contract_data #>> '{orderer,email}'), '') is null
     or nullif(btrim(p_contract_data #>> '{contractor,name}'), '') is null
     or nullif(btrim(p_contract_data #>> '{contractor,address}'), '') is null
     or nullif(btrim(p_contract_data #>> '{contractor,email}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,location}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,scope}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,quality}'), '') is null then
    raise exception 'Chybí povinná identifikace stran nebo přesný popis díla.';
  end if;

  v_creator_role := p_contract_data ->> 'creator_role';
  if v_creator_role = 'zhotovitel' then
    v_creator_email := lower(btrim(p_contract_data #>> '{contractor,email}'));
    v_other_email := lower(btrim(p_contract_data #>> '{orderer,email}'));
  elsif v_creator_role = 'objednatel' then
    v_creator_email := lower(btrim(p_contract_data #>> '{orderer,email}'));
    v_other_email := lower(btrim(p_contract_data #>> '{contractor,email}'));
  else
    raise exception 'Není určeno, v jaké roli smlouvu vytváříš.';
  end if;

  if v_auth_email = '' or v_creator_email <> v_auth_email then
    raise exception 'E-mail vaší smluvní strany musí odpovídat ověřenému e-mailu přihlášeného účtu.';
  end if;
  if nullif(btrim(p_invitee_email), '') is null
     or lower(btrim(p_invitee_email)) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or lower(btrim(p_invitee_email)) <> v_other_email then
    raise exception 'E-mail pozvané osoby musí souhlasit s e-mailem druhé smluvní strany.';
  end if;
  if v_other_email = v_auth_email then
    raise exception 'Obě smluvní strany musí používat rozdílné e-mailové adresy.';
  end if;

  v_hash := encode(
    extensions.digest(
      convert_to(
        p_contract_text || E'\n' || p_contract_data::text || E'\n' || p_items::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.agreements (
    created_by, title, description, currency, status,
    template_key, contract_data, contract_text, content_hash
  )
  values (
    v_user, btrim(p_title), p_description,
    upper(coalesce(nullif(btrim(p_currency), ''), 'CZK')),
    'draft', 'cz_work_contract', p_contract_data, p_contract_text, v_hash
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) as t(value)
  loop
    v_description := nullif(btrim(v_item ->> 'description'), '');
    v_quantity := (v_item ->> 'quantity')::numeric;
    v_unit := nullif(btrim(v_item ->> 'unit'), '');
    v_unit_price := (v_item ->> 'unit_price')::numeric;

    if v_description is null or v_quantity is null or v_quantity <= 0
       or v_unit is null or v_unit_price is null or v_unit_price < 0 then
      raise exception 'Každá položka musí mít popis, kladné množství, jednotku a nezápornou cenu.';
    end if;

    insert into public.agreement_items (
      agreement_id, description, quantity, unit, unit_price, position
    )
    values (v_id, v_description, v_quantity, v_unit, v_unit_price, v_position);

    v_position := v_position + 1;
  end loop;

  insert into public.agreement_participants (agreement_id, email, role)
  values (v_id, lower(btrim(p_invitee_email)), 'participant');

  insert into public.agreement_versions (
    agreement_id, version_no, template_key, contract_data,
    contract_text, content_hash, created_by
  )
  values (v_id, 1, 'cz_work_contract', p_contract_data, p_contract_text, v_hash, v_user);

  update public.agreements
     set status = 'shared'
   where id = v_id;

  return v_id;
end;
$$;

revoke all on function public.create_work_agreement_with_invite(text, text, text, jsonb, text, jsonb, text) from public, anon;
grant execute on function public.create_work_agreement_with_invite(text, text, text, jsonb, text, jsonb, text) to authenticated;

drop policy if exists agreement_signatures_insert on public.agreement_signatures;
create policy agreement_signatures_insert
  on public.agreement_signatures
  for insert to authenticated
  with check (
    signer_id = (select auth.uid())
    and public.is_agreement_member(agreement_id)
    and exists (
      select 1
      from public.agreements a
      where a.id = agreement_signatures.agreement_id
        and a.status = 'shared'
        and (
          a.content_hash is null
          or a.content_hash = agreement_signatures.terms_hash
        )
    )
  );
