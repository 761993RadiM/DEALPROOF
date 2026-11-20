# DEALPROOF

Android-first application for recording agreements between two people.

## Current implementation

- Email/password accounts through Supabase Auth.
- Cloud-stored agreements visible to their participants.
- Invite code and QR code for the second participant.
- Separate user accounts and signatures drawn on screen.
- Signature records include signer identity, timestamp and SHA-256 fingerprint of the agreed terms.
- Amendment proposals are separate from the original agreement; the other participant can accept or reject them.

A drawn signature and in-app confirmation are evidence records, not automatically a qualified electronic signature. Do not represent the app as guaranteeing legal enforceability.

## Cloud setup required before connected use

1. Create a Supabase project.
2. Open SQL Editor and run `supabase/migrations/202611200001_initial_schema.sql`.
3. In the GitHub repository, add Actions repository secrets:
   - `SUPABASE_URL`: Project URL from Supabase Project Settings → API.
   - `SUPABASE_ANON_KEY`: publishable/anon client key from the same page.
4. Run the **Build Android APK** workflow again.

Never put a Supabase service-role key in the Android app or GitHub build arguments. Only the public anon/publishable key belongs in the client; access is controlled by database row-level security.

## Build

GitHub Actions builds the Android APK. The app cannot connect to a cloud backend until the setup above is completed.
