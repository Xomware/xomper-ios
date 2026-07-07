-- Migration: add the admin_cron_settings row for notif_week_preview.
-- Default `enabled=true, test_mode=true` so the first fire after the
-- terraform apply lands in the admin inbox ONLY — flip test_mode=false
-- from the Cron Settings screen once the copy looks right.
--
-- Run in Supabase dashboard SQL editor. Idempotent — ON CONFLICT
-- skips if a row with the same cron_key already exists.

INSERT INTO admin_cron_settings (cron_key, enabled, test_mode, description, updated_at)
VALUES (
    'notif_week_preview',
    true,
    true,
    'Week Preview newsletter — Wed 9am ET',
    NOW()
)
ON CONFLICT (cron_key) DO NOTHING;
