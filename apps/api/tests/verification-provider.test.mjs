import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TestVerificationProvider,
  SmsVerificationProvider,
  WhatsAppVerificationProvider,
} from '../dist/auth/verification-provider.js';

test('TestVerificationProvider captures OTP and prohibits production', async () => {
  const provider = new TestVerificationProvider();
  const phone = '+963911223344';
  const result = await provider.sendOtp(phone, '123456', 'auth');

  assert.equal(result.success, true);
  assert.equal(result.channel, 'TEST');
  assert.equal(provider.getCapturedCode(phone), '123456');

  // Verify production safeguard
  const originalEnv = process.env.NODE_ENV;
  try {
    process.env.NODE_ENV = 'production';
    await assert.rejects(
      async () => provider.sendOtp(phone, '654321', 'auth'),
      err => {
        assert.equal(err.getResponse().code, 'TEST_VERIFICATION_PROVIDER_PROHIBITED_IN_PRODUCTION');
        assert.equal(err.getStatus(), 500);
        return true;
      }
    );
  } finally {
    process.env.NODE_ENV = originalEnv;
  }
});

test('SmsVerificationProvider throws 503 in non-dev when unconfigured', async () => {
  const originalEnv = process.env.NODE_ENV;
  delete process.env.SMS_GATEWAY_URL;
  delete process.env.SMS_API_KEY;

  try {
    process.env.NODE_ENV = 'staging';
    const provider = new SmsVerificationProvider();
    await assert.rejects(
      async () => provider.sendOtp('+963911223344', '123456'),
      err => {
        assert.equal(err.getResponse().code, 'SMS_PROVIDER_NOT_CONFIGURED');
        assert.equal(err.getStatus(), 503);
        return true;
      }
    );
  } finally {
    process.env.NODE_ENV = originalEnv;
  }
});

test('WhatsAppVerificationProvider throws 503 in non-dev when unconfigured', async () => {
  const originalEnv = process.env.NODE_ENV;
  delete process.env.WHATSAPP_API_TOKEN;
  delete process.env.WHATSAPP_PHONE_NUMBER_ID;

  try {
    process.env.NODE_ENV = 'staging';
    const provider = new WhatsAppVerificationProvider();
    await assert.rejects(
      async () => provider.sendOtp('+963911223344', '123456'),
      err => {
        assert.equal(err.getResponse().code, 'WHATSAPP_PROVIDER_NOT_CONFIGURED');
        assert.equal(err.getStatus(), 503);
        return true;
      }
    );
  } finally {
    process.env.NODE_ENV = originalEnv;
  }
});
