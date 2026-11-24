# DEALPROOF

Android-first application for recording agreements between two people.

## Important: live database and repository are not aligned yet

A read-only inspection of the connected Supabase project on 2026-11-24 found this existing `public` schema:

- `agreements`
- `agreement_participants`
- `agreement_items`
- `amendments`
- `amendment_signatures`

All five tables have Row Level Security enabled. The inspected tables and `auth.users` currently contain zero rows. Supabase's migration history is empty.

**Do not run `supabase/migrations/202611200001_initial_schema.sql` against this database as-is.** It describes a different, earlier schema (including `profiles`, `agreement_signatures`, `owner_id`, `amount`, and `invite_code`). The live database instead uses fields such as `created_by`, `currency`, `agreement_items`, and `amendment_signatures`. Applying the old migration blindly would fail partway through and leave a partial schema.

The current Flutter implementation in `lib/main.dart` also targets the earlier schema and currently does not match the live database. It must be aligned before connected use.

## Current live-schema direction

The existing database appears to model:
- agreements owned by a creator;
- separate agreement participants;
- itemized work/price lines in `agreement_items`;
- amendment proposals in `amendments`;
- amendment decisions in `amendment_signatures`.

Any missing capabilities should be introduced with reviewed, additive migrations. Do not drop or rename existing tables as a shortcut.

## Security notes from the read-only audit

- RLS is enabled on all five public tables.
- Supabase Security Advisor reports that `public.add_agreement_owner()` is a SECURITY DEFINER trigger function executable by the `anon` role; its execute privileges need review.
- The advisor also reports RLS policy initialization-plan warnings and missing foreign-key indexes. Review and remediate these without weakening row-level access.

A drawn signature and in-app confirmation are evidence records, not automatically a qualified electronic signature. Do not represent the app as guaranteeing legal enforceability.

## Cloud configuration

The Android client must use only a Supabase publishable/anon key. Never put a Supabase service-role or secret key in the Android app or GitHub Actions build arguments. Access must be controlled by database Row Level Security.

## Build

GitHub Actions is configured to build a release APK. The build has not yet been verified against the live database configuration.