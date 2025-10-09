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
    const { text, image_ref, subject, level, language } = await req.json()

    if (!text) {
      return new Response(
        JSON.stringify({ error: 'Missing text parameter' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const openaiKey = Deno.env.get('OPENAI_API_KEY')
    if (!openaiKey) {
      throw new Error('OPENAI_API_KEY not configured')
    }

    // Build system prompt
    const systemPrompt = `You are an expert study assistant. Generate high-quality flashcards from the given text.

Requirements:
- Create 3-8 flashcards depending on content length
- Front: Clear, concise question
- Back: Comprehensive answer (2-4 sentences)
- Hint: Optional mnemonic or tip
- Difficulty: 1 (easiest) to 5 (hardest)
${subject ? `- Subject: ${subject}` : ''}
${level ? `- Academic level: ${level}` : ''}
${language ? `- Language: ${language}` : ''}

Return ONLY valid JSON array with this structure:
[
  {
    "front": "Question here?",
    "back": "Answer here.",
    "hint": "Optional hint",
    "difficulty": 3
  }
]`

    // Call OpenAI
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `Generate flashcards from this text:\n\n${text}` }
        ],
        temperature: 0.7,
        max_tokens: 2000,
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`OpenAI API error: ${error}`)
    }

    const data = await response.json()
    const content = data.choices[0].message.content

    // Parse JSON response
    let flashcards
    try {
      flashcards = JSON.parse(content)
    } catch (e) {
      // Try to extract JSON from markdown code blocks
      const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/)
      if (jsonMatch) {
        flashcards = JSON.parse(jsonMatch[1])
      } else {
        throw new Error('Failed to parse flashcards JSON')
      }
    }

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
