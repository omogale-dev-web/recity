import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Browser-safe project values. Never add a service-role key here.
const SUPABASE_URL = 'https://xwznrmlvxxiwwjbedkdg.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_QL9RhA1AhSaEXmfB5ANegA_Tk6p4nWs';
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: true, autoRefreshToken: true } });

export async function ensureIdentity() {
  let { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    const { data, error } = await supabase.auth.signInAnonymously();
    if (error) throw error;
    session = data.session;
  }
  return session.user;
}

export async function getMyProfile() {
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!user) throw new Error('ReCity identity is not available');
  const { data, error } = await supabase.from('profiles').select('recity_id, role').eq('id', user.id).single();
  if (error) throw error;
  return data;
}

export async function requestCollector(displayName) {
  const { data, error } = await supabase.rpc('request_collector_role', { p_display_name: displayName });
  if (error) throw error;
  return data;
}

export async function reviewCollectorRequest(id, approved) {
  const { data, error } = await supabase.rpc('review_collector_request', { p_request_id: id, p_approved: approved });
  if (error) throw error;
  return data;
}

export async function getMyCollectorRequest() {
  const { data, error } = await supabase.from('collector_requests').select('id, display_name, status').order('created_at', { ascending: false }).limit(1);
  if (error) throw error;
  return data?.[0] || null;
}

export async function setAvailability(latitude, longitude, available) {
  const { error } = await supabase.rpc('set_collector_availability', { p_latitude: latitude, p_longitude: longitude, p_is_available: available });
  if (error) throw error;
}

export async function getCollectorData() {
  const [offers, tasks, points] = await Promise.all([
    supabase.from('dispatch_offers').select('id, complaint_id, distance_meters, expires_at, complaints(public_id, waste_summary, address)').eq('status', 'offered').order('created_at', { ascending: false }),
    supabase.from('collection_tasks').select('id, complaint_id, status, accepted_at, complaints(public_id, waste_summary, address)').order('updated_at', { ascending: false }),
    supabase.from('collector_point_events').select('points_delta, reason, created_at').order('created_at', { ascending: false })
  ]);
  if (offers.error) throw offers.error;
  if (tasks.error) throw tasks.error;
  if (points.error) throw points.error;
  return { offers: offers.data, tasks: tasks.data, points: points.data };
}

export async function respondToOffer(id, accept) {
  const { data, error } = await supabase.rpc('respond_to_dispatch_offer', { p_offer_id: id, p_accept: accept });
  if (error) throw error;
  return data;
}

export async function uploadProof(taskId, file, userId) {
  const extension = (file.name.split('.').pop() || 'jpg').replace(/[^a-z0-9]/gi, '');
  const path = `${userId}/${taskId}/${Date.now()}.${extension}`;
  const { error } = await supabase.storage.from('collection-proofs').upload(path, file, { upsert: false, contentType: file.type });
  if (error) throw error;
  const { error: proofError } = await supabase.rpc('submit_collection_proof', { p_task_id: taskId, p_photo_path: path, p_latitude: null, p_longitude: null });
  if (proofError) throw proofError;
}

export async function verifyProof(taskId, approved) {
  const { error } = await supabase.rpc('verify_collection_proof', { p_task_id: taskId, p_approved: approved });
  if (error) throw error;
}

export async function getOperationsData() {
  const [reports, requests] = await Promise.all([
    supabase.from('complaints').select('id, public_id, waste_summary, status, latitude, longitude, reported_at').order('reported_at', { ascending: false }).limit(50),
    supabase.from('collector_requests').select('id, display_name, status, created_at').order('created_at', { ascending: false })
  ]);
  if (reports.error) throw reports.error;
  if (requests.error) throw requests.error;
  return { reports: reports.data, requests: requests.data };
}
