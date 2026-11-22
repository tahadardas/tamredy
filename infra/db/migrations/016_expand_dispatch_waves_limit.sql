-- Migration 016: Expand dispatch waves limit to 5 waves
-- Matches admin settings allowing up to 5 waves.

ALTER TABLE request_offers DROP CONSTRAINT IF EXISTS request_offers_wave_no_check;
ALTER TABLE request_offers ADD CONSTRAINT request_offers_wave_no_check CHECK (wave_no BETWEEN 1 AND 5);

ALTER TABLE dispatch_jobs DROP CONSTRAINT IF EXISTS dispatch_jobs_next_wave_check;
ALTER TABLE dispatch_jobs ADD CONSTRAINT dispatch_jobs_next_wave_check CHECK (next_wave BETWEEN 1 AND 6);
