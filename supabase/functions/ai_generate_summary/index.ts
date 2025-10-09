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
    const systemPrompt = `You are an expert study assistant. Create a comprehensive explanation document from the given text.

Requirements:
- Title: Clear, descriptive title (5-8 words)
- Summary: Concise overview (2-3 sentences)
- Key Points: 3-7 bullet points highlighting main concepts
- Content: Well-structured markdown document with:
  - Introduction paragraph
  - Main sections with ## headings
  - Bullet points and numbered lists where appropriate
  - Clear explanations with examples
  - Conclusion or summary paragraph
${subject ? `- Subject: ${subject}` : ''}
${level ? `- Academic level: ${level}` : ''}
${language ? `- Language: ${language}` : ''}

Return ONLY valid JSON with this structure:
{
  "title": "Document Title Here",
  "summary": "Brief overview of the content.",
  "key_points": [
    "First main concept",
    "Second main concept",
    "Third main concept"
  ],
  "content": "# Main Title\\n\\n## Introduction\\n\\n...full markdown content..."
}`

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
          { role: 'user', content: `Create an explanation document from this text:\n\n${text}` }
        ],
        temperature: 0.7,
        max_tokens: 3000,
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`OpenAI API error: ${error}`)
    }

    const data = await response.json()
    const content = data.choices[0].message.content

    // Parse JSON response
    let result
    try {
      result = JSON.parse(content)
    } catch (e) {
      // Try to extract JSON from markdown code blocks
      const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/)
      if (jsonMatch) {
        result = JSON.parse(jsonMatch[1])
      } else {
        throw new Error('Failed to parse summary JSON')
      }
    }

    return new Response(
      JSON.stringify(result),
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
