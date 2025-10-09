We already have UI screens for:

Daily study plan & AI chatbot

Explore materials (study sets, flashcards, explanations/docs, exercises)

Scan & solve

Library (create/edit/manage sets, flashcards, docs, exercises with AI)

Upgrade/memberships & payments

Settings (profile, payments, security, appearance, help)

Onboarding/auth (sign up/in, forgot password, advanced setup)

Implement the complete app logic, using clean architecture and local-first sync.

0) STACK & CONVENTIONS (assume unless told otherwise)

Flutter (stable), Dart

State: Riverpod + AsyncValue patterns

Routing: go_router with guards (auth/subscription/onboarding)

Backend: Supabase (Auth, Postgres, Storage, Edge Functions)

AI: Edge Function proxy → OpenAI/Claude/Gemini (server-side)

Subscriptions: RevenueCat (iOS/Android), Stripe (web)

OCR/Scan: native ML Kit wrapper or Tesseract via plugin (abstract behind service)

Offline: Local DB isar (preferred) or hive with conflict resolution (CRDT-lite)

Analytics: Firebase + custom events

Errors: Sentry (or Crashlytics)

Theming: already implemented; expose use-cases via controllers only

Project layout (create if missing):