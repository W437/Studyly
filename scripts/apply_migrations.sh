#!/bin/bash

# Apply Supabase migrations
# This script uses the Supabase CLI or curl to apply SQL migrations

SUPABASE_URL="https://kzvscyzgzvwyhlhyssvz.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6dnNjeXpnenZ3eWhsaHlzc3Z6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwMDU4MTgsImV4cCI6MjA3NTU4MTgxOH0.ANHxMzoFCfs6dMxbddqGrQc0Ddhk5fc8RGSXsp1NQaM"

echo "========================================"
echo "Applying Supabase Migrations"
echo "========================================"
echo ""

# Check if supabase CLI is installed
if command -v supabase &> /dev/null; then
    echo "Using Supabase CLI..."

    # Link to remote project
    supabase link --project-ref kzvscyzgzvwyhlhyssvz

    # Apply migrations
    supabase db push

    echo "✅ Migrations applied successfully!"
else
    echo "❌ Supabase CLI not found."
    echo ""
    echo "Please install it with:"
    echo "  npm install -g supabase"
    echo ""
    echo "Or apply migrations manually:"
    echo "1. Go to: https://supabase.com/dashboard/project/kzvscyzgzvwyhlhyssvz/editor/sql"
    echo "2. Copy and paste the SQL from each file in supabase/migrations/"
    echo "3. Run them in order (001, 002, 003)"
    exit 1
fi
