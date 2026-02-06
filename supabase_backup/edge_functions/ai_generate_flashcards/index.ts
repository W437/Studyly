import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { content } = await req.json()

    if (!content) {
      return new Response(
        JSON.stringify({ error: 'Missing content parameter' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const openaiKey = Deno.env.get('OPENAI_API_KEY')
    if (!openaiKey) {
      throw new Error('OPENAI_API_KEY not configured')
    }

    const assistantId = 'asst_hgEpFUyYhmkTclOOTOUiTWqq'

    // Step 1: Create a thread
    const threadResponse = await fetch('https://api.openai.com/v1/threads', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
    })

    if (!threadResponse.ok) {
      throw new Error(`Failed to create thread: ${await threadResponse.text()}`)
    }

    const thread = await threadResponse.json()
    const threadId = thread.id

    // Step 2: Add message to thread
    const messageResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      },
      body: JSON.stringify({
        role: 'user',
        content: content,
      }),
    })

    if (!messageResponse.ok) {
      throw new Error(`Failed to add message: ${await messageResponse.text()}`)
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
      throw new Error(`Failed to run assistant: ${await runResponse.text()}`)
    }

    const run = await runResponse.json()
    const runId = run.id

    // Step 4: Poll for completion
    let status = 'queued'
    let attempts = 0
    const maxAttempts = 60 // 60 seconds timeout

    while (status !== 'completed' && attempts < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 1000))

      const statusResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/runs/${runId}`, {
        headers: {
          'Authorization': `Bearer ${openaiKey}`,
          'OpenAI-Beta': 'assistants=v2',
        },
      })

      if (!statusResponse.ok) {
        throw new Error(`Failed to check status: ${await statusResponse.text()}`)
      }

      const statusData = await statusResponse.json()
      status = statusData.status

      if (status === 'failed' || status === 'cancelled' || status === 'expired') {
        throw new Error(`Assistant run failed with status: ${status}`)
      }

      attempts++
    }

    if (status !== 'completed') {
      throw new Error('Assistant run timed out')
    }

    // Step 5: Get the response
    const messagesResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/messages`, {
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'OpenAI-Beta': 'assistants=v2',
      },
    })

    if (!messagesResponse.ok) {
      throw new Error(`Failed to get messages: ${await messagesResponse.text()}`)
    }

    const messagesData = await messagesResponse.json()
    const messages = messagesData.data

    // Get the assistant's response (first message in the list)
    const assistantMessage = messages.find((msg: any) => msg.role === 'assistant')
    if (!assistantMessage) {
      throw new Error('No assistant response found')
    }

    const messageContent = assistantMessage.content
    const textContent = messageContent.find((c: any) => c.type === 'text')
    if (!textContent) {
      throw new Error('No text content in assistant response')
    }

    const responseText = textContent.text.value

    // Parse the JSON response
    let flashcardsData
    try {
      flashcardsData = JSON.parse(responseText)
    } catch (e) {
      // Try to extract JSON from markdown code blocks
      const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/)
      if (jsonMatch) {
        flashcardsData = JSON.parse(jsonMatch[1])
      } else {
        throw new Error('Failed to parse flashcards JSON')
      }
    }

    const flashcards = flashcardsData.flashcards || flashcardsData

    return new Response(
      JSON.stringify({ flashcards }),
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
