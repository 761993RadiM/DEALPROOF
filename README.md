# DEALPROOF

Android-first application for recording agreements between two parties.

## What is implemented

- Supabase email/password accounts and cloud-stored agreements.
- One structured Czech contract-for-work (`smlouva o dílo`) wizard.
- Identification of both parties, roles, address and business identifiers.
- Detailed work scope, location, quality, materials, dates, itemized prices, VAT mode, payment schedule, handover and defect handling.
- Review of the complete contract text before sending it to the other party.
- Immutable version 1 snapshot and SHA-256 fingerprint over the contract text, structured data and itemized budget.
- Two-party in-app confirmation records with signer identity, timestamp and drawn signature image.
- Separate amendment proposals; the original agreement text is not edited by an amendment.
- PDF export with Czech-capable Noto Sans font, budget lines, signature images, timestamps and SHA-256 fingerprint.

Only the work-contract template is currently offered. Other contract types are not advertised as available until they are separately prepared and tested.

## Legal and electronic-signature limits

The current work-contract form is a structured draft based on the Czech Civil Code. It is not represented as an attorney-reviewed legal opinion or a guarantee of enforceability. A qualified Czech lawyer should review the template before public commercial release.

Consumer contracts are deliberately blocked in this version. The separate consumer information, distance/off-premises contracting and withdrawal workflow has not yet been completed.

An in-app drawn signature and a confirmation record are evidence of the parties' actions; they are not automatically a qualified electronic signature under eIDAS. The PDF export is a copy of stored content and evidence records, not a legal certification.

## Database migrations

Migrations are stored in `supabase/migrations` and use the same version identifiers recorded in the connected Supabase project. For a new, empty Supabase project, apply all files in ascending filename order:

1. `20261124083105_live_schema_alignment.sql` — foundational tables, RLS and invitation/signature workflow.
2. `20261125220529_work_contract_snapshots.sql` — structured contract fields and immutable version snapshots.
3. `20261125220853_private_rls_helpers.sql` — moves internal RLS helper functions to the private schema.
4. `20261125221149_harden_work_contract_creation.sql` — validates creation server-side and blocks direct client writes to core contract tables.
5. `20261125221228_private_contract_creation_rpc.sql` — exposes a public invoker wrapper for the private creation transaction.
6. `20261125221858_work_contract_warranty_termination.sql` — requires explicit warranty selection and termination/settlement terms for every new work contract.
7. `20261125221948_amendment_validation.sql` — validates amendment descriptions and price changes; the amendment may also set a new completion date.
8. `20261125222724_work_contract_ico_validation.sql` — checks Czech IČO control digits in the form and database.
9. `20261125223256_work_contract_consumer_guard.sql` — blocks consumer-like agreements until a compliant consumer flow is implemented.

Do not run just one of these files on a blank database. They form one ordered setup. The connected production project already has these migrations recorded as applied.

## Supabase Auth configuration

- Keep the Supabase **Site URL** as a valid HTTPS website URL; do not set it to a custom app scheme.
- Add `dealproof://login-callback` to the Auth redirect URL allowlist.
- Configure a production SMTP sender before relying on confirmation and invitation emails. The app currently creates the pending invitation in the database and opens the Android share sheet; it does not itself send an email.
- Enable leaked-password protection in Supabase Auth → Password Security.

## Android build

GitHub Actions builds the Android APK. Required GitHub repository Actions secrets:

- `SUPABASE_URL`: the Supabase project URL.
- `SUPABASE_ANON_KEY`: the public publishable/anon client key.

Never put a Supabase service-role key in the Android app or GitHub build arguments. Database access is controlled through row-level security and restricted RPC permissions.

The PDF exporter downloads and caches the Noto Sans font on first use, so the first PDF export needs an internet connection.
