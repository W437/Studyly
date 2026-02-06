import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { prompt, user_id } = await req.json()

    if (!prompt || !user_id) {
      return new Response(
        JSON.stringify({ error: 'Missing prompt or user_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const aiResponse = await generateAIResponse(prompt, user_id)

    const message = {
      id: crypto.randomUUID(),
      user_id,
      text: aiResponse,
      sender: 0,
      timestamp: new Date().toISOString()
    }

    const { error: dbError } = await supabaseClient
      .from('chat_messages')
      .insert(message)

    if (dbError) {
      console.error('Database error:', dbError)
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

async function generateAIResponse(prompt: string, userId: string): Promise<string> {
  const openaiKey = Deno.env.get('OPENAI_API_KEY')
  const assistantId = 'asst_dmiz0MOWNUtPErn5zpFYkXHw'

  if (!openaiKey) {
    throw new Error('OPENAI_API_KEY not configured')
  }

  try {
    const threadResponse = await fetch('https://api.openai.com/v1/threads', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({ metadata: { user_id: userId } }),
    })

    if (!threadResponse.ok) {
      const error = await threadResponse.text()
      throw new Error(`Failed to create thread: ${error}`)
    }

    const thread = await threadResponse.json()
    const threadId = thread.id

    const messageResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({ role: 'user', content: prompt }),
    })

    if (!messageResponse.ok) {
      const error = await messageResponse.text()
      throw new Error(`Failed to add message: ${error}`)
    }

    const runResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/runs`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({ assistant_id: assistantId }),
    })

    if (!runResponse.ok) {
      const error = await runResponse.text()
      throw new Error(`Failed to run assistant: ${error}`)
    }

    const run = await runResponse.json()
    const runId = run.id

    let runStatus = run.status
    let attempts = 0
    const maxAttempts = 30

    while (runStatus !== 'completed' && attempts < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 1000))

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
