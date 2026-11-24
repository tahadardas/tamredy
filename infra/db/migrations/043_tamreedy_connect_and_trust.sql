-- Migration 043: Tamreedy Connect (In-App Chat, Attachments) and Trust & Blocking

-- Conversations
CREATE TABLE IF NOT EXISTS conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid REFERENCES care_requests(id) ON DELETE SET NULL,
  type text NOT NULL DEFAULT 'VISIT' CHECK (type IN ('VISIT', 'SUPPORT', 'CARE_PLAN')),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CLOSED', 'ARCHIVED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz
);

-- Conversation participants
CREATE TABLE IF NOT EXISTS conversation_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('PATIENT', 'NURSE', 'SUPPORT', 'SUPERVISOR')),
  last_read_message_id uuid,
  last_read_at timestamptz,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, user_id)
);

-- Chat messages
CREATE TABLE IF NOT EXISTS chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  client_message_id text,
  message_type text NOT NULL DEFAULT 'TEXT' CHECK (message_type IN ('TEXT', 'IMAGE', 'PDF', 'DOCUMENT', 'LOCATION', 'SYSTEM_MESSAGE', 'VOICE_NOTE')),
  content text NOT NULL,
  attachment_url text,
  attachment_meta jsonb DEFAULT '{}'::jsonb,
  reply_to_message_id uuid REFERENCES chat_messages(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'STORED' CHECK (status IN ('PENDING', 'STORED', 'DELIVERED', 'READ', 'FAILED')),
  has_contact_advisory boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, client_message_id)
);

-- Chat attachments & medical prescriptions
CREATE TABLE IF NOT EXISTS chat_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid REFERENCES chat_messages(id) ON DELETE CASCADE,
  uploader_user_id uuid NOT NULL REFERENCES users(id),
  storage_key text NOT NULL UNIQUE,
  original_filename text NOT NULL,
  mime_type text NOT NULL,
  file_size_bytes integer NOT NULL CHECK (file_size_bytes > 0 AND file_size_bytes <= 10485760),
  is_prescription boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Mutual Blocking between users
CREATE TABLE IF NOT EXISTS user_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason_code text NOT NULL DEFAULT 'GENERAL_PREFERENCE',
  private_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CHECK (blocker_user_id <> blocked_user_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_blocks_active
  ON user_blocks(blocker_user_id, blocked_user_id)
  WHERE revoked_at IS NULL;

-- Unified Reports and Complaints Center
CREATE TABLE IF NOT EXISTS user_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES users(id),
  reported_user_id uuid REFERENCES users(id),
  request_id uuid REFERENCES care_requests(id) ON DELETE SET NULL,
  report_type text NOT NULL CHECK (report_type IN ('TECHNICAL_SUPPORT', 'FINANCIAL_DISPUTE', 'CLINICAL_COMPLAINT', 'SAFETY_INCIDENT', 'COMMITMENT_APPEAL')),
  severity text NOT NULL DEFAULT 'STANDARD' CHECK (severity IN ('LOW', 'STANDARD', 'URGENT', 'CRITICAL_SAFETY')),
  title text NOT NULL,
  description text NOT NULL,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'INVESTIGATING', 'ESCALATED_TO_GUARDIAN', 'RESOLVED', 'DISMISSED')),
  resolution_note text,
  resolved_by uuid REFERENCES users(id),
  resolved_at timestamptz,
  guardian_case_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_conv_created ON chat_messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_request ON conversations(request_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_status_type ON user_reports(status, report_type);
CREATE INDEX IF NOT EXISTS idx_user_blocks_lookup ON user_blocks(blocked_user_id) WHERE revoked_at IS NULL;
