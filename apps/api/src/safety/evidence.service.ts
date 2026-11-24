import { Injectable } from '@nestjs/common';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import { buildEvidence, openEvidence, sealEvidence, sha256 } from './evidence-bundle.js';
import { EvidenceRepository } from './evidence.repository.js';
import { StaffCasesRepository } from './staff-cases.repository.js';
import type { EvidenceApprovalDto } from './evidence.dto.js';

@Injectable()
export class EvidenceService {
  constructor(private readonly exports: EvidenceRepository, private readonly cases: StaffCasesRepository) {}

  approve(actor: string, caseId: string, dto: EvidenceApprovalDto) {
    return this.exports.transaction(async client => {
      if (await this.cases.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      if (actor === dto.exporterId) invalid('Separate evidence approval is required');
      if (!await this.exports.exporter(client,dto.exporterId)) forbidden();
      if (!await this.cases.find(client,caseId)) missing();
      const approval = await this.exports.approve(client,caseId,actor,dto);
      await this.cases.audit(client,actor,'safety.evidence_approved',caseId);
      return approval;
    });
  }

  generate(actor: string, caseId: string, id: string) {
    return this.exports.transaction(async client => {
      if (!await this.exports.exporter(client,actor)) forbidden();
      const approval = await this.exports.lockApproval(client,id,actor,caseId);
      if (!approval || !approval.current) missing();
      const existing = await this.exports.existing(client,id);
      if (existing) return existing;
      if (!await this.cases.find(client,caseId)) missing();
      const {points,...data} = await this.exports.collect(client,caseId);
      if (points.length > 20_000 || data.custody.length > 10_000) {
        conflict('SAFETY_EVIDENCE_EXPORT_LIMIT');
      }
      const {manifest,envelope} = buildEvidence(caseId,{
        ...data,
        approval: {id,approvedBy:approval.approved_by,exportedBy:actor,
          purpose:approval.purpose,recipient:approval.recipient,caseReference:approval.case_reference},
      },points,new Date());
      const row = await this.exports.store(client,id,actor,manifest,sealEvidence(envelope,id),sha256(envelope));
      await this.cases.audit(client,actor,'safety.evidence_exported',caseId);
      return row;
    });
  }

  download(actor: string, id: string) {
    return this.exports.transaction(async client => {
      if (!await this.exports.exporter(client,actor)) forbidden();
      const row = await this.exports.download(client,actor,id);
      if (!row) missing();
      const bytes = openEvidence(row.sealed_bundle,row.approval_id);
      if (sha256(bytes) !== row.sha256) conflict('SAFETY_EVIDENCE_INTEGRITY_ERROR');
      await this.cases.audit(client,actor,'safety.evidence_downloaded',row.case_id);
      return bytes;
    });
  }
}
