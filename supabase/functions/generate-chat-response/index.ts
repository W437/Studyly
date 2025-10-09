import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { prompt, user_id, image_url } = await req.json()

    // Validate input
    if (!prompt || !user_id) {
      return new Response(
        JSON.stringify({ error: 'Missing prompt or user_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client with service role key for admin operations
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Generate AI response using OpenAI Assistant
    const aiResponse = await generateAIResponse(prompt, user_id, image_url)

    // Create message object
    const message = {
      id: crypto.randomUUID(),
      user_id,
      text: aiResponse,
      sender: 0, // 0 = bot, 1 = user
      timestamp: new Date().toISOString()
    }

    // Save to database (skip errors for testing)
    const { error: dbError } = await supabaseClient
      .from('chat_messages')
      .insert(message)

    if (dbError) {
      console.error('Database error:', dbError)
      // For testing: return response anyway with warning
      message.text = `[DB Save Failed] ${message.text}`
    }

    return new Response(
      JSON.stringify(message),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function generateAIResponse(prompt: string, userId: string, imageUrl?: string): Promise<string> {
  const openaiKey = Deno.env.get('OPENAI_API_KEY')
  const assistantId = Deno.env.get('OPENAI_ASSISTANT_ID')

  if (!openaiKey) {
    throw new Error('OPENAI_API_KEY not configured')
  }

  if (!assistantId) {
    throw new Error('OPENAI_ASSISTANT_ID not configured')
  }

  try {
    // Step 1: Create a thread
    const threadResponse = await fetch('https://api.openai.com/v1/threads', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({
        metadata: { user_id: userId }
      }),
    })

    if (!threadResponse.ok) {
      const error = await threadResponse.text()
      throw new Error(`Failed to create thread: ${error}`)
    }

    const thread = await threadResponse.json()
    const threadId = thread.id

    // Step 2: Add user message to thread (with image if provided)
    const messageContent: any[] = [
      {
        type: 'text',
        text: prompt,
      }
    ]

    // Add image if provided (OpenAI Vision API)
    if (imageUrl) {
      messageContent.push({
        type: 'image_url',
        image_url: {
          url: imageUrl,
        },
      })
    }

    const messageResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({
        role: 'user',
        content: messageContent,
      }),
    })

    if (!messageResponse.ok) {
      const error = await messageResponse.text()
      throw new Error(`Failed to add message: ${error}`)
    }

    // Step 3: Run the assistant
    const runResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/runs`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({
        assistant_id: assistantId,
      }),
    })

    if (!runResponse.ok) {
      const error = await runResponse.text()
      throw new Error(`Failed to run assistant: ${error}`)
    }

    const run = await runResponse.json()
    const runId = run.id

    // Step 4: Poll for completion (max 30 seconds)
    let runStatus = run.status
    let attempts = 0
    const maxAttempts = 30

    while (runStatus !== 'completed' && attempts < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 1000)) // Wait 1 second

      const statusResponse = await fetch(
        `https://api.openai.com/v1/threads/${threadId}/runs/${runId}`,
        {
          headers: {
            'Authorization': `Bearer ${openaiKey}`,
            'OpenAI-Beta': 'assistants=v2',
          },
        }
      )

      if (!statusResponse.ok) {
        throw new Error('Failed to check run status')
      }

      const statusData = await statusResponse.json()
      runStatus = statusData.status

      if (runStatus === 'failed' || runStatus === 'cancelled' || runStatus === 'expired') {
        throw new Error(`Assistant run ${runStatus}`)
      }

      attempts++
    }

    if (runStatus !== 'completed') {
      throw new Error('Assistant run timed out')
    }

    // Step 5: Retrieve messages
    const messagesResponse = await fetch(
      `https://api.openai.com/v1/threads/${threadId}/messages?limit=1&order=desc`,
      {
        headers: {
          'Authorization': `Bearer ${openaiKey}`,
          'OpenAI-Beta': 'assistants=v2',
        },
      }
    )

    if (!messagesResponse.ok) {
      throw new Error('Failed to retrieve messages')
    }

    const messages = await messagesResponse.json()
    const assistantMessage = messages.data[0]

    // Extract text content
    const textContent = assistantMessage.content.find((c: any) => c.type === 'text')
    if (!textContent) {
      throw new Error('No text content in response')
    }

    return textContent.text.value

  } catch (error) {
    console.error('OpenAI API error:', error)
    throw new Error(`AI generation failed: ${error.message}`)
  }
}
