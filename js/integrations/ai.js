import {supabase} from './supabase.js';
// Groq is called only by Vercel's protected /api/analyze-waste function.
export const analyzeWaste=async({imageData,language='en'}={})=>{
  const {data:{session}}=await supabase.auth.getSession();
  if(!session?.access_token) throw new Error('Please start your Recity journey first.');
  const response=await fetch('/api/analyze-waste',{method:'POST',headers:{'content-type':'application/json',authorization:`Bearer ${session.access_token}`},body:JSON.stringify({imageData,language})});
  const payload=await response.json().catch(()=>({}));
  if(!response.ok) throw new Error(payload.error||'We could not analyze this image.');
  return {summary:payload.summary,hazard:payload.hazard,items:(payload.items||[]).map(item=>({key:item.name,material:item.material,condition:item.condition,reusable:item.reusable,recyclable:item.recyclable,hazard:item.hazard,confidence:item.confidence,emoji:'♻️',ideas:(item.reuse_ideas||[]).map(idea=>idea.title).filter(Boolean),suggestedAction:item.suggested_action,safetyAdvice:item.safety,disposalAdvice:item.disposal_guidance}))};
};
// TODO: CONNECT GROQ GUIDE GENERATION LATER
export const generateGuide=async()=>{await new Promise(r=>setTimeout(r,550));return (await import('../mock/guides.js')).guide};
