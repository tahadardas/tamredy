import { Injectable, HttpException } from '@nestjs/common';

export type VerificationChannel = 'SMS' | 'WHATSAPP' | 'TEST';

export interface VerificationSendResult {
  success: boolean;
  channel: VerificationChannel;
  messageId?: string;
}

export abstract class VerificationProvider {
  abstract readonly channel: VerificationChannel;
  abstract sendOtp(phone: string, code: string, purpose?: string): Promise<VerificationSendResult>;
}

@Injectable()
export class TestVerificationProvider extends VerificationProvider {
  readonly channel: VerificationChannel = 'TEST';
  private readonly capturedCodes = new Map<string, string>();

  async sendOtp(phone: string, code: string, purpose = 'auth'): Promise<VerificationSendResult> {
    if (process.env.NODE_ENV === 'production') {
      throw new HttpException(
        { code: 'TEST_VERIFICATION_PROVIDER_PROHIBITED_IN_PRODUCTION' },
        500,
      );
    }
    // Record for test assertions without logging OTP code in production-like outputs
    this.capturedCodes.set(phone, code);
    if (process.env.NODE_ENV === 'development') {
      console.log(`[TEST VERIFICATION to ${phone}] (purpose: ${purpose})`);
    }
    return {
      success: true,
      channel: 'TEST',
      messageId: `test-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    };
  }

  getCapturedCode(phone: string): string | undefined {
    return this.capturedCodes.get(phone);
  }

  clear(): void {
    this.capturedCodes.clear();
  }
}

@Injectable()
export class SmsVerificationProvider extends VerificationProvider {
  readonly channel: VerificationChannel = 'SMS';

  async sendOtp(phone: string, code: string, purpose = 'auth'): Promise<VerificationSendResult> {
    const gatewayUrl = process.env.SMS_GATEWAY_URL;
    const apiKey = process.env.SMS_API_KEY;

    if (!gatewayUrl || !apiKey) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`[DEV SMS to ${phone}] رمز تمريضي: ${code} (purpose: ${purpose})`);
        return { success: true, channel: 'SMS', messageId: `dev-sms-${Date.now()}` };
      }
      throw new HttpException({ code: 'SMS_PROVIDER_NOT_CONFIGURED' }, 503);
    }

    // Official licensed SMS gateway dispatch
    try {
      const response = await fetch(gatewayUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          recipient: phone,
          message: `رمز تمريضي لتأكيد الدخول: ${code}`,
          sender: process.env.SMS_SENDER_ID ?? 'Tamreedy',
        }),
      });

      if (!response.ok) {
        throw new Error(`SMS gateway returned ${response.status}`);
      }

      const data = (await response.json().catch(() => ({}))) as Record<string, unknown>;
      return {
        success: true,
        channel: 'SMS',
        messageId: String(data.messageId ?? data.id ?? `sms-${Date.now()}`),
      };
    } catch {
      throw new HttpException({ code: 'SMS_DELIVERY_FAILED' }, 502);
    }
  }
}

@Injectable()
export class WhatsAppVerificationProvider extends VerificationProvider {
  readonly channel: VerificationChannel = 'WHATSAPP';

  async sendOtp(phone: string, code: string, purpose = 'auth'): Promise<VerificationSendResult> {
    const token = process.env.WHATSAPP_API_TOKEN;
    const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
    const templateName = process.env.WHATSAPP_OTP_TEMPLATE_NAME ?? 'tamreedy_verification_code';

    if (!token || !phoneId) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`[DEV WHATSAPP to ${phone}] رمز تمريضي: ${code} (purpose: ${purpose})`);
        return { success: true, channel: 'WHATSAPP', messageId: `dev-wa-${Date.now()}` };
      }
      throw new HttpException({ code: 'WHATSAPP_PROVIDER_NOT_CONFIGURED' }, 503);
    }

    // Official Meta WhatsApp Business API integration
    try {
      const normalizedPhone = phone.replace(/^\+/, '');
      const response = await fetch(`https://graph.facebook.com/v21.0/${phoneId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: normalizedPhone,
          type: 'template',
          template: {
            name: templateName,
            language: { code: 'ar' },
            components: [
              {
                type: 'body',
                parameters: [{ type: 'text', text: code }],
              },
              {
                type: 'button',
                sub_type: 'url',
                index: '0',
                parameters: [{ type: 'text', text: code }],
              },
            ],
          },
        }),
      });

      if (!response.ok) {
        throw new Error(`WhatsApp API error: ${response.status}`);
      }

      const resData = (await response.json().catch(() => ({}))) as { messages?: Array<{ id: string }> };
      const messageId = resData?.messages?.[0]?.id ?? `wa-${Date.now()}`;
      return { success: true, channel: 'WHATSAPP', messageId };
    } catch {
      throw new HttpException({ code: 'WHATSAPP_DELIVERY_FAILED' }, 502);
    }
  }
}
