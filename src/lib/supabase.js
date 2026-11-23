import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.PUBLIC_SUPABASE_URL=https://wlxnxamlsqezpjsdyrah.supabase.co;
const key = import.meta.env.PUBLIC_SUPABASE_ANON_KEY=sb_publishable_Tvq6grbkSIsG1Doh7Y7Txw_t_cFm7BK;

export const configured = Boolean(url && key);
export const supabase = configured ? createClient(url, key) : null;
