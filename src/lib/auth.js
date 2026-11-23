import { supabase } from './supabase.js';
import { u } from './url.js';

export async function getUser() {
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  return data.session ? data.session.user : null;
}

// Client-side guard: send logged-out visitors to /login and bring them back afterwards.
export async function requireUser() {
  const user = await getUser();
  if (!user) {
    location.replace(u('/login/') + '?next=' + encodeURIComponent(location.pathname + location.search));
    return null;
  }
  return user;
}

export async function getProfile(userId) {
  const { data } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle();
  return data;
}

export const isPro = p => Boolean(p && p.plan_expiry && new Date(p.plan_expiry) > new Date());
export const daysLeft = p => Math.max(0, Math.ceil((new Date(p.plan_expiry) - Date.now()) / 86400000));

export async function logout() {
  await supabase.auth.signOut();
  location.href = u('/');
}
