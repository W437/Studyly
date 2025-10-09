# Generate Chat Response Edge Function

This Supabase Edge Function generates AI-powered chat responses for the Studyly app.

## Setup

### 1. Deploy the function

```bash
# Install Supabase CLI if you haven't
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref kzvscyzgzvwyhlhyssvz

# Deploy the function
supabase functions deploy generate-chat-response
```

### 2. Configure Environment Variables

Set up your AI provider API key in the Supabase dashboard:

**Option A: OpenAI**
```bash
supabase secrets set OPENAI_API_KEY=your_openai_api_key_here
```

**Option B: Anthropic Claude**
```bash
supabase secrets set ANTHROPIC_API_KEY=your_anthropic_api_key_here
```

**Option C: Google Gemini**
```bash
supabase secrets set GOOGLE_API_KEY=your_google_api_key_here
```

### 3. Update the code

Uncomment the AI integration you want to use in `index.ts` and remove the placeholder response.

## Testing

Test the function locally:

```bash
supabase functions serve generate-chat-response
```

Then make a request:

```bash
curl -X POST http://localhost:54321/functions/v1/generate-chat-response \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -d '{
    "prompt": "What is organic chemistry?",
    "user_id": "YOUR_USER_ID"
  }'
```

## API Reference

### Request

```typescript
{
  prompt: string;      // User's question/prompt
  user_id: string;     // UUID of the authenticated user
}
```

### Response

```typescript
{
  id: string;          // UUID of the message
  user_id: string;     // UUID of the user
  text: string;        // AI-generated response
  sender: number;      // 0 = bot, 1 = user
  timestamp: string;   // ISO 8601 timestamp
}
```

## Security

- This function uses Row Level Security (RLS)
- Only authenticated users can call this function
- Messages are automatically associated with the calling user
- Service role key is used internally for database operations
