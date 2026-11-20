# DEALPROOF

DEALPROOF is an Android-first app for documenting agreements between two people.

## Current status

Version 0.1.0 is an early Flutter prototype. It currently keeps data only in app memory; data is not yet saved after restarting the app, and agreements are not yet shared with another person.

## Planned MVP

- Accounts and cloud synchronization.
- One shared agreement with two participants.
- Separate confirmations from each participant.
- Versioned amendment proposals: the original agreement is never overwritten; accepted and rejected proposals remain in the history.
- Photos and file attachments.
- Timeline and PDF export.

## Run

Install Flutter, then run:

```sh
flutter pub get
flutter analyze
flutter run
```

An in-app confirmation is an evidence record. It is not automatically a qualified electronic signature and the app must not promise legal enforceability.
