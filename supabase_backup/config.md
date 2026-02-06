# Supabase Project Configuration

## Project
- **Name:** Studyly
- **ID:** kzvscyzgzvwyhlhyssvz
- **Organization ID:** ctyxhprwujmunkniteog
- **Region:** us-east-2
- **API URL:** https://kzvscyzgzvwyhlhyssvz.supabase.co
- **DB Host:** db.kzvscyzgzvwyhlhyssvz.supabase.co
- **Postgres Version:** 17.6.1.016

## API Keys
- **Anon Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6dnNjeXpnenZ3eWhsaHlzc3Z6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwMDU4MTgsImV4cCI6MjA3NTU4MTgxOH0.ANHxMzoFCfs6dMxbddqGrQc0Ddhk5fc8RGSXsp1NQaM`

> Note: These keys will be invalid after project deletion. New keys will be generated with a new project.

## Installed Extensions
- `uuid-ossp` (schema: extensions) - UUID generation
- `pgcrypto` (schema: extensions) - Cryptographic functions
- `pg_stat_statements` (schema: extensions) - Query statistics
- `pg_graphql` (schema: graphql) - GraphQL support
- `supabase_vault` (schema: vault) - Vault extension
- `plpgsql` (schema: pg_catalog) - PL/pgSQL

## Migrations (in order)
1. `20251009014228_add_profile_picture_fields`
2. `20251009014544_create_profile_trigger`
3. `20251009071956_add_chat_feedback_fields`
4. `20251009122334_create_scan_tables`
5. `20251009122352_scan_rls_policies`
6. `20251009122409_create_storage_bucket`

## Edge Functions
1. **generate-chat-response** (verify_jwt: true)
   - Uses OpenAI Assistants API
   - Assistant ID: `asst_dmiz0MOWNUtPErn5zpFYkXHw`
   - Requires secret: `OPENAI_API_KEY`

2. **ai_generate_flashcards** (verify_jwt: true)
   - Uses OpenAI Assistants API
   - Assistant ID: `asst_hgEpFUyYhmkTclOOTOUiTWqq`
   - Requires secret: `OPENAI_API_KEY`

## Storage Buckets
- **scans** (private) - Stores user scan images
  - RLS: Users can only access files in their own folder (`{user_id}/...`)

## Edge Function Secrets Required
- `OPENAI_API_KEY` - For both edge functions
- `SUPABASE_URL` - Auto-provided by Supabase
- `SUPABASE_SERVICE_ROLE_KEY` - Auto-provided by Supabase
