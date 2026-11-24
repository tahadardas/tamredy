export interface ShieldCheckResult {
  hasContactLeak: boolean;
  advisoryMessage?: string;
  detectedKind?: 'PHONE' | 'EMAIL' | 'EXTERNAL_LINK';
}

const ARABIC_INDIC_DIGITS = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

export function normalizeDigits(input: string): string {
  let result = input;
  for (let i = 0; i < ARABIC_INDIC_DIGITS.length; i++) {
    result = result.replaceAll(ARABIC_INDIC_DIGITS[i]!, String(i));
  }
  return result;
}

// Emergency numbers permitted across Syria & medical hotlines
const EMERGENCY_NUMBERS = new Set(['110', '112', '113', '115', '133', '190', '191', '199']);

// Regex for Syrian / International mobile and landline patterns
const PHONE_PATTERN = /(?:\+?963|00963|0)?[\s.-]?(9\d{8}|[1-5]\d{7})/g;
const GENERAL_PHONE_PATTERN = /(?:\+?\d{1,3}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}/g;
const EMAIL_PATTERN = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/;
const LINK_PATTERN = /(?:https?:\/\/|www\.)[^\s/$.?#].[^\s]*/i;

// Medical patterns to protect from false-positive detection
const MEDICAL_BLOOD_PRESSURE = /\b\d{2,3}\s*\/\s*\d{2,3}\b/; // e.g. 120/80
const MEDICAL_DOSAGE = /\b\d+(?:\.\d+)?\s*(?:mg|ml|mcg|iu|ملغ|مل|غم|جرعة|حبة|كبسولة)\b/i;
const MEDICAL_GLUCOSE = /\b\d{2,3}\s*(?:mg\/dl|مغ\/دل)\b/i;
const DATE_PATTERN = /\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b|\b\d{1,2}[-/.]\d{1,2}[-/.]\d{4}\b/;

export const PRIVACY_ADVISORY_TEXT =
  'لحماية خصوصيتك وضمان توثيق الزيارة وحقوق الطرفين، يُرجى إبقاء التواصل والتنسيق داخل تطبيق تمريضي.';

export function inspectMessageForContactInfo(rawContent: string): ShieldCheckResult {
  if (!rawContent || typeof rawContent !== 'string') {
    return { hasContactLeak: false };
  }

  const normalized = normalizeDigits(rawContent);

  // Exclude single emergency numbers
  const trimmed = normalized.trim();
  if (EMERGENCY_NUMBERS.has(trimmed)) {
    return { hasContactLeak: false };
  }

  // Check email
  if (EMAIL_PATTERN.test(normalized)) {
    return {
      hasContactLeak: true,
      detectedKind: 'EMAIL',
      advisoryMessage: PRIVACY_ADVISORY_TEXT,
    };
  }

  // Check external links
  if (LINK_PATTERN.test(normalized)) {
    return {
      hasContactLeak: true,
      detectedKind: 'EXTERNAL_LINK',
      advisoryMessage: PRIVACY_ADVISORY_TEXT,
    };
  }

  // Check if text is purely a medical reading
  if (
    MEDICAL_BLOOD_PRESSURE.test(normalized) ||
    MEDICAL_DOSAGE.test(normalized) ||
    MEDICAL_GLUCOSE.test(normalized) ||
    DATE_PATTERN.test(normalized)
  ) {
    // If it contains medical measurements, verify if there is also an explicit 10-digit phone number
    const match = normalized.match(PHONE_PATTERN);
    if (!match) {
      return { hasContactLeak: false };
    }
  }

  // Phone match
  const phoneMatches = normalized.match(PHONE_PATTERN) || normalized.match(GENERAL_PHONE_PATTERN);
  if (phoneMatches && phoneMatches.length > 0) {
    // Filter out matches that are just dates or dosages
    const genuinePhones = phoneMatches.filter(p => {
      const cleanDigits = p.replace(/\D/g, '');
      return cleanDigits.length >= 8 && cleanDigits.length <= 15 && !EMERGENCY_NUMBERS.has(cleanDigits);
    });

    if (genuinePhones.length > 0) {
      return {
        hasContactLeak: true,
        detectedKind: 'PHONE',
        advisoryMessage: PRIVACY_ADVISORY_TEXT,
      };
    }
  }

  return { hasContactLeak: false };
}
