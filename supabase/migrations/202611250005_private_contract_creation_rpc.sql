
-- Keep the privileged transaction function private; expose only an invoker wrapper.
alter function public.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) set schema private;

alter function private.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) security definer;

alter function private.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) set search_path = '';

revoke all on function private.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) from public,anon;
grant execute on function private.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) to authenticated;

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
language sql
security invoker
set search_path = ''
as $$
  select private.create_work_agreement_with_invite(
    p_title,
    p_description,
    p_currency,
    p_contract_data,
    p_contract_text,
    p_items,
    p_invitee_email
  );
$$;

revoke all on function public.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) from public,anon;
grant execute on function public.create_work_agreement_with_invite(
  text,text,text,jsonb,text,jsonb,text
) to authenticated;
