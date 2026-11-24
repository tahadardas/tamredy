# Tamreedy Pre-Release Requirements & Commercial Readiness Checklist

## Status
`PENDING — OWNER WILL PROVIDE DOMAIN AND SSL BEFORE COMMERCIAL RELEASE`

---

## 1. Domain & SSL/TLS Configuration
- **Status:** PENDING — OWNER WILL PROVIDE DOMAIN AND SSL BEFORE COMMERCIAL RELEASE
- **Requirement:** Production release must reject cleartext HTTP and enforce HTTPS with valid HSTS and trusted certificate authority.
- **Current Development Configuration:**
  - `API_BASE_URL` is decoupled via environment variables (`.env`, `.env.example`, Docker environment) and Flutter Dart Defines:
    ```bash
    --dart-define=API_BASE_URL=http://<SERVER_IP>:<PORT>
    ```
  - Mobile apps in development/staging allow HTTP connections only for testing on controlled local/staging addresses with synthetic test data. No real patient data, medical prescriptions, or identity documents may be transmitted over cleartext HTTP.
  - Production builds reject non-HTTPS URLs by default.

## 2. External Provider Credentials
- **SMS / WhatsApp Business Verification Provider:**
  - Status: PENDING OWNER PROVISIONING
  - Requires official Meta WhatsApp Business API credentials (Phone Number ID, WABA ID, Permanent Access Token) or licensed Syrian telecom SMS gateway (Syriatel / MTN).
  - Development and automated tests utilize `TestVerificationProvider` and `DevConsoleSms` which generate verifiable hash-bound challenges without external dependencies.
- **Push Notifications (Firebase Cloud Messaging):**
  - Requires production service account keys in `serviceAccountKey.json`.
- **Payment & Banking Gateway:**
  - Status: CASH ONLY IN CURRENT PHASE (Cash on delivery / nurse settlement).
  - Real electronic wallet top-ups and cashouts require formal licensing from Syrian regulatory authorities before activating payment aggregator integration.

## 3. Google Play & App Store Compliance
- **Public Privacy Policy URL:**
  - Must be hosted on public domain detailing data safety, location usage (foreground during active visit), and health records.
- **Account & Data Deletion URL:**
  - Self-service account deletion request web endpoint as mandated by Google Play 2024+ policies.
- **Health Apps Declaration:**
  - Declaration in Google Play Console regarding Home Nursing Care coordination, explicit disclaimers that Tamreedy does not provide automated clinical diagnosis or emergency medical dispatch.
- **Foreground Service & Location Disclosures:**
  - Prominent in-app disclosure prior to initiating nurse tracking or GPS capture during active visits.

## 4. Staging Concurrency & PostGIS Validation
- **Requirement:** Run concurrency integration tests and load drills against a real multi-connection PostgreSQL 16+ instance with PostGIS extension enabled before commercial activation.
