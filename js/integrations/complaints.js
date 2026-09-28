import {supabase} from './supabase.js';

const dataUrlToBlob = async dataUrl => (await fetch(dataUrl)).blob();

export async function submitComplaint({imageData, analysis, address, location}) {
  const {data: {user}} = await supabase.auth.getUser();
  if (!user) throw new Error('Please start your RECITY journey first.');

  const photoPath = user.id + '/' + crypto.randomUUID() + '.jpg';
  const {error: uploadError} = await supabase.storage
    .from('complaint-photos')
    .upload(photoPath, await dataUrlToBlob(imageData), {contentType: 'image/jpeg', upsert: false});
  if (uploadError) throw uploadError;

  const {data, error} = await supabase.rpc('submit_complaint', {
    p_waste_summary: analysis.summary,
    p_ai_summary: analysis.summary,
    p_hazard: analysis.hazard || 'low',
    p_photo_path: photoPath,
    p_address: address || null,
    p_latitude: location?.lat || null,
    p_longitude: location?.lng || null,
    p_items: analysis.items.map(({key, material, condition, reusable, recyclable, hazard, confidence, suggestedAction}) => ({
      name: key, material, condition, reusable, recyclable, hazard, confidence, suggestedAction
    }))
  });
  if (error) {
    await supabase.storage.from('complaint-photos').remove([photoPath]);
    throw error;
  }
  return data;
}
