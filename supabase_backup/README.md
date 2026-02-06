# Studyly Supabase Backup

Backed up on: 2026-02-06

## Project Info
- **Project Name:** Studyly
- **Project ID:** kzvscyzgzvwyhlhyssvz
- **Region:** us-east-2
- **API URL:** https://kzvscyzgzvwyhlhyssvz.supabase.co
- **Postgres Version:** 17.6.1.016

## Contents
- `schema.sql` - Full database schema (tables, RLS policies, functions, triggers, storage)
- `migrations/` - Individual migration files in order
- `edge_functions/` - Edge function source code
- `config.md` - API keys, extensions, and other config

## How to Restore
1. Create a new Supabase project
2. Run `schema.sql` against the new project (or apply migrations in order)
3. Deploy edge functions via Supabase CLI or MCP
4. Update `lib/app/config/supabase_config.dart` with new project URL and anon key
5. Set `OPENAI_API_KEY` in edge function secrets
