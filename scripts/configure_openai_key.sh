#!/bin/bash

# Configure OpenAI API Key in Supabase
# This script should be run once to set up the environment variable

echo "========================================"
echo "Configuring OpenAI API Key in Supabase"
echo "========================================"
echo ""

OPENAI_KEY="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"

# Method 1: Using Supabase CLI (recommended)
if command -v supabase &> /dev/null; then
    echo "Using Supabase CLI to set secret..."

    # Link to project
    supabase link --project-ref kzvscyzgzvwyhlhyssvz

    # Set the secret
    supabase secrets set OPENAI_API_KEY="$OPENAI_KEY"

    echo "✅ OpenAI API key configured successfully!"
else
    echo "❌ Supabase CLI not found."
    echo ""
    echo "Please install it with: npm install -g supabase"
    echo ""
    echo "Or set the secret manually:"
    echo "1. Go to: https://supabase.com/dashboard/project/kzvscyzgzvwyhlhyssvz/settings/functions"
    echo "2. Click 'Edge Function Secrets'"
    echo "3. Add secret:"
    echo "   Name: OPENAI_API_KEY"
    echo "   Value: $OPENAI_KEY"
    exit 1
fi
