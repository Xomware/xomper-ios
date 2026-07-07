-- Migration: replace placeholder emails with real emails for 3 whitelisted users.
--
-- These rows already exist and already have the correct sleeper_user_id (backfilled
-- 2026-06-02), but were seeded with a bare nickname in the `email` column. The login
-- gate (AuthStore.checkWhitelist) matches on real email, so these members CANNOT log
-- in until the email is corrected. Emails confirmed via league DM 2026-07-02.
--
-- Run in Supabase dashboard SQL editor. Idempotent — no-ops once emails are set.

UPDATE whitelisted_users
  SET email = 'murchisdm@bellsouth.net', sleeper_username = 'dmurchis'
  WHERE email = 'duncan';   -- sleeper_user_id 741140723985997824

UPDATE whitelisted_users
  SET email = 'mwynne16@gmail.com', sleeper_username = 'mwynne16'
  WHERE email = 'mike';     -- sleeper_user_id 1001254799347658752

UPDATE whitelisted_users
  SET email = 'andrewga23@gmail.com', sleeper_username = 'andrewga23'
  WHERE email = 'tony';     -- sleeper_user_id 1127420529155227648

-- Still on placeholder emails (real emails not yet collected): jim, tibor, kyle, alex
