-- Migration: add sleeper_user_id column to whitelisted_users + backfill all
-- 12 active rows from Sleeper API (resolved 2026-06-02).
--
-- Run in Supabase dashboard SQL editor. Idempotent — uses
-- `ADD COLUMN IF NOT EXISTS` and email-keyed UPDATEs that no-op when
-- already set to the same value.
--
-- Why: admin_email_test_recipients / admin_users_update / admin_gate
-- all expect this column. The test-email picker stays empty until
-- this is populated.

ALTER TABLE whitelisted_users
  ADD COLUMN IF NOT EXISTS sleeper_user_id text;

UPDATE whitelisted_users SET sleeper_user_id = '418511574492270592'  WHERE email = 'reesedgriffin@gmail.com';
UPDATE whitelisted_users SET sleeper_user_id = '741140723985997824'  WHERE email = 'duncan';
UPDATE whitelisted_users SET sleeper_user_id = '866444821185843200'  WHERE email = 'jim';
UPDATE whitelisted_users SET sleeper_user_id = '992955241630896128'  WHERE email = 'tibor';
UPDATE whitelisted_users SET sleeper_user_id = '1001254799347658752' WHERE email = 'mike';
UPDATE whitelisted_users SET sleeper_user_id = '1127420529155227648' WHERE email = 'tony';
UPDATE whitelisted_users SET sleeper_user_id = '1132215311643787264' WHERE email = 'kyle';
UPDATE whitelisted_users SET sleeper_user_id = '609168618525110272'  WHERE email = 'alex';
UPDATE whitelisted_users SET sleeper_user_id = '867213779035906048'  WHERE email = 'luke.novak10@gmail.com';
UPDATE whitelisted_users SET sleeper_user_id = '865328062403870720'  WHERE email = 'connorfolk@gmail.com';
UPDATE whitelisted_users SET sleeper_user_id = '867213342836711424'  WHERE email = 'gtatich@gmail.com';
UPDATE whitelisted_users SET sleeper_user_id = '594625531702460416' WHERE email = 'dominickj.giordano@gmail.com';
