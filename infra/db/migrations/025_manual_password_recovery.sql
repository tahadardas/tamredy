ALTER TABLE users ADD COLUMN temporary_password_expires_at timestamptz, ADD COLUMN auth_version uuid;
