-- Initial password given to patient/nurse accounts created by staff (and used by "reset password").
-- The account must change it at first login; the server blocks every other request until it does.
UPDATE app_settings SET value = value || '{"defaultPassword":"123456"}'::jsonb
WHERE key = 'security' AND NOT (value ? 'defaultPassword');
