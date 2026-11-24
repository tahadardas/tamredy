import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { ServiceUnavailableException } from '@nestjs/common';

export type EvidencePoint = {
  sequence_no: number;
  longitude: number;
  latitude: number;
  accuracy_m: number;
  captured_at: Date;
  received_at: Date;
};

export function sha256(data: Buffer) {
  return createHash('sha256').update(data).digest('hex');
}

function evidenceKey() {
  const key = process.env.GUARDIAN_EVIDENCE_KEY;
  if (!key || !/^[0-9a-f]{64}$/i.test(key) || /^0+$/.test(key)) {
    throw new ServiceUnavailableException({code:'SAFETY_EVIDENCE_KEY_NOT_CONFIGURED'});
  }
  return Buffer.from(key,'hex');
}

export function sealEvidence(contents: Buffer, approvalId: string) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm',evidenceKey(),iv);
  cipher.setAAD(Buffer.from(approvalId));
  const encrypted = Buffer.concat([cipher.update(contents),cipher.final()]);
  return Buffer.concat([iv,cipher.getAuthTag(),encrypted]);
}

export function openEvidence(sealed: Buffer, approvalId: string) {
  const decipher = createDecipheriv('aes-256-gcm',evidenceKey(),sealed.subarray(0,12));
  decipher.setAAD(Buffer.from(approvalId));
  decipher.setAuthTag(sealed.subarray(12,28));
  return Buffer.concat([decipher.update(sealed.subarray(28)),decipher.final()]);
}

export function buildEvidence(caseId: string, data: object, points: EvidencePoint[], at: Date) {
  const json = (value: unknown) => Buffer.from(JSON.stringify(value));
  const csv = Buffer.from([
    'sequence,longitude,latitude,accuracy_m,captured_at,received_at',
    ...points.map(p => [p.sequence_no,p.longitude,p.latitude,p.accuracy_m,
      new Date(p.captured_at).toISOString(),new Date(p.received_at).toISOString()].join(',')),
  ].join('\n')+'\n');
  const geo = json({type:'FeatureCollection',features:points.map(p => ({
    type:'Feature', geometry:{type:'Point',coordinates:[p.longitude,p.latitude]},
    properties:{sequence:p.sequence_no,accuracy_m:p.accuracy_m,captured_at:p.captured_at,received_at:p.received_at},
  }))});
  const files = {'case.json':json(data),'locations.csv':csv,'locations.geojson':geo};
  const manifest = {
    version:1,caseId,createdAt:at.toISOString(),
    files:Object.entries(files).map(([name,bytes]) => ({name,bytes:bytes.length,sha256:sha256(bytes)})),
  };
  const envelope = Buffer.from(JSON.stringify({
    manifest,
    files:Object.fromEntries(Object.entries(files).map(([name,bytes]) => [name,bytes.toString('base64')])),
  }));
  return {manifest,envelope};
}
