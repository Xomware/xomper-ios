-- Migration: email_archive table for admin view + resend.
-- Every successful SES send writes one row here (best-effort — failures
-- are swallowed by ses_helper.send_email so a Supabase outage doesn't
-- break email delivery).
--
-- Run in Supabase dashboard SQL editor. Idempotent — uses IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS email_archive (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    sent_at           timestamptz NOT NULL DEFAULT NOW(),
    template          text,                   -- e.g. weekly_recap, week_preview, ai_review_test
    subject           text        NOT NULL,
    recipient_email   text        NOT NULL,
    html_body         text,                   -- can be ~50kb for AI Review payloads
    text_body         text,
    message_id        text,                   -- SES response message id
    metadata          jsonb       NOT NULL DEFAULT '{}'::jsonb
);

-- Index by recipient + date for the admin list query (recent first,
-- optionally filtered to a specific user).
CREATE INDEX IF NOT EXISTS email_archive_sent_at_desc
    ON email_archive (sent_at DESC);

CREATE INDEX IF NOT EXISTS email_archive_recipient_sent_at
    ON email_archive (recipient_email, sent_at DESC);

-- Row-level security: only the service role (which the backend lambdas
-- use) can read/write. Admin lambdas authenticate as the service role
-- via SUPABASE_SERVICE_KEY.
ALTER TABLE email_archive ENABLE ROW LEVEL SECURITY;
