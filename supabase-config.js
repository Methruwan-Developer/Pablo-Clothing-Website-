// Add these values from Supabase Project Settings > API.
window.PABLO_SUPABASE_URL = 'https://dnenavzpwkyxwyezkipn.supabase.co';
window.PABLO_SUPABASE_ANON_KEY = 'sb_publishable_-b1w8lUHpgsX-VwBG_nqMg_uXORqKHX';

window.pabloSupabase = window.supabase.createClient(
    window.PABLO_SUPABASE_URL || 'https://placeholder.supabase.co',
    window.PABLO_SUPABASE_ANON_KEY || 'placeholder-anon-key'
);

window.pabloSupabaseReady = Boolean(
    window.PABLO_SUPABASE_URL && window.PABLO_SUPABASE_ANON_KEY
);

window.requireSupabase = function () {
    if (!window.pabloSupabaseReady) {
        throw new Error('Supabase is not configured. Add the project URL and anon key in supabase-config.js.');
    }
};
