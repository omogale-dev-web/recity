const MAX_IMAGE_BYTES = 2_500_000;
const send = (res, status, payload) => res.status(status).json(payload);
const bearer = (header = '') => header.startsWith('Bearer ') ? header.slice(7) : null;

async function authenticatedUser(token) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key || !token) return null;
  const response = await fetch(`${url}/auth/v1/user`, { headers: { apikey: key, authorization: `Bearer ${token}` } });
  return response.ok ? response.json() : null;
}

function validImage(imageData) {
  if (typeof imageData !== 'string' || !/^data:image\/(jpeg|png|webp);base64,/.test(imageData)) return false;
  return Buffer.byteLength(imageData.slice(imageData.indexOf(',') + 1), 'base64') <= MAX_IMAGE_BYTES;
}

function item(value) {
  return {
    name: String(value.name || 'Unidentified item').slice(0, 80), material: String(value.material || 'Unknown material').slice(0, 80), condition: String(value.condition || 'Unknown condition').slice(0, 100),
    reusable: Boolean(value.reusable), recyclable: Boolean(value.recyclable), hazard: ['none', 'low', 'medium', 'high'].includes(value.hazard) ? value.hazard : 'low', confidence: Math.max(0, Math.min(100, Number(value.confidence) || 0)),
    suggested_action: String(value.suggested_action || '').slice(0, 280), safety: String(value.safety || '').slice(0, 280), disposal_guidance: String(value.disposal_guidance || '').slice(0, 280),
    reuse_ideas: Array.isArray(value.reuse_ideas) ? value.reuse_ideas.slice(0, 3).map(idea => ({ title: String(idea.title || '').slice(0, 90), difficulty: String(idea.difficulty || '').slice(0, 30), time: String(idea.time || '').slice(0, 30), tools: Array.isArray(idea.tools) ? idea.tools.slice(0, 6).map(tool => String(tool).slice(0, 30)) : [] })) : []
  };
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return send(res, 405, { error: 'Method not allowed' });
  if (!process.env.GROQ_API_KEY) return send(res, 503, { error: 'Analysis is being configured. Please try again shortly.' });
  if (!await authenticatedUser(bearer(req.headers.authorization))) return send(res, 401, { error: 'Please start your Recity journey before analyzing waste.' });
  const { imageData, language = 'en' } = req.body || {};
  if (!validImage(imageData)) return send(res, 400, { error: 'Use a clear JPG, PNG, or WebP image smaller than 2.5 MB.' });

  const languageName = language === 'mr' ? 'Marathi' : 'English';
  const system = `You are Recity, a careful civic waste assistant. Analyze only visible waste. Reply in valid JSON with exactly: {"has_waste":boolean,"summary":string,"hazard":"none|low|medium|high","items":[{"name":string,"material":string,"condition":string,"reusable":boolean,"recyclable":boolean,"hazard":"none|low|medium|high","confidence":number,"suggested_action":string,"safety":string,"disposal_guidance":string,"reuse_ideas":[{"title":string,"difficulty":string,"time":string,"tools":[string]}]}]}. Use ${languageName} for every value shown to a citizen. Never suggest unsafe DIY use for hazardous or uncertain materials.`;
  try {
    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST', headers: { authorization: `Bearer ${process.env.GROQ_API_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model: process.env.GROQ_VISION_MODEL || 'qwen/qwen3.8-27b', temperature: 0.2, max_completion_tokens: 1300, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: system }, { role: 'user', content: [{ type: 'text', text: 'Analyze this image for Recity.' }, { type: 'image_url', image_url: { url: imageData } }] }] })
    });
    if (!response.ok) throw new Error(`Groq returned ${response.status}`);
    const payload = await response.json();
    const parsed = JSON.parse(payload.choices?.[0]?.message?.content || '{}');
    const items = Array.isArray(parsed.items) ? parsed.items.slice(0, 6).map(item) : [];
    return send(res, 200, { has_waste: Boolean(parsed.has_waste && items.length), summary: String(parsed.summary || 'Waste analysis complete').slice(0, 280), hazard: ['none', 'low', 'medium', 'high'].includes(parsed.hazard) ? parsed.hazard : 'low', items });
  } catch (error) {
    console.error('Waste analysis failed', error.message);
    return send(res, 502, { error: 'We could not analyze this image. Please try again.' });
  }
}
