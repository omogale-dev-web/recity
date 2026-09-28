import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '../config.js';

// Client access is deliberately limited to the browser-safe publishable key.
// All sensitive decisions remain protected by Supabase Row Level Security.
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false }
});

const characterMap = {
  reuseRanger: 'reuse_ranger', greenGuardian: 'green_guardian', ecoExplorer: 'eco_explorer',
  natureKeeper: 'nature_keeper', planetProtector: 'planet_protector', greenPioneer: 'green_pioneer'
};
const camelCharacter = value => Object.entries(characterMap).find(([, snake]) => snake === value)?.[0] || 'reuseRanger';

export const toCitizen = profile => ({
  id: profile.recity_id,
  authId: profile.id,
  name: profile.display_name || 'Recity citizen',
  character: camelCharacter(profile.eco_character),
  emoji: camelCharacter(profile.eco_character) === 'greenGuardian' ? '🛡️' : camelCharacter(profile.eco_character) === 'ecoExplorer' ? '🔎' : '🌿',
  level: profile.level,
  points: profile.eco_points,
  reused: profile.items_reused,
  reports: profile.reports_submitted,
  collections: profile.collections_completed,
  diverted: Number(profile.estimated_waste_diverted_kg)
});

async function profileFor(userId) {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).single();
  if (error) throw error;
  return data;
}

// Uses Supabase anonymous Auth to honor Recity's no-phone/no-email UX.
// The database trigger creates the profile and friendly Recity ID.
export async function getOrCreateRecityIdentity({ character = 'reuseRanger', locale = 'en' } = {}) {
  let { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    const { data, error } = await supabase.auth.signInAnonymously({
      options: { data: { eco_character: characterMap[character] || 'reuse_ranger', locale } }
    });
    if (error) throw error;
    session = data.session;
  }
  if (!session?.user) throw new Error('Could not create a Recity identity.');

  // The auth trigger normally finishes before this query; one retry handles
  // propagation timing without presenting a technical error to the citizen.
  try {
    return toCitizen(await profileFor(session.user.id));
  } catch (firstError) {
    await new Promise(resolve => setTimeout(resolve, 450));
    return toCitizen(await profileFor(session.user.id));
  }
}

export async function restoreRecityIdentity() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user) return null;
  return toCitizen(await profileFor(session.user.id));
}

export async function updateIdentityPreferences({ character, locale }) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const update = {};
  if (character) update.eco_character = characterMap[character] || 'reuse_ranger';
  if (locale) update.locale = locale;
  const { data, error } = await supabase.from('profiles').update(update).eq('id', user.id).select().single();
  if (error) throw error;
  return toCitizen(data);
}

// TODO: CONNECT SUPABASE STORAGE LATER
// TODO: CONNECT SUPABASE REALTIME LATER
// TODO: Move collection status and point awards into an Edge Function later.
