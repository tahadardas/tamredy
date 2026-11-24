import { Injectable, ForbiddenException, NotFoundException, BadRequestException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

export interface ObservationInputDto {
  observationType: string;
  numericValue: number;
  measuredAt?: string;
  notes?: string;
  source?: 'NURSE_VISIT' | 'PATIENT_SELF_REPORT' | 'CLINICAL_VERIFIED';
}

export interface VisitNoteInputDto {
  servicesPerformed: Array<{ serviceId: string; titleAr: string; status: 'COMPLETED' | 'SKIPPED'; skipReason?: string }>;
  clinicalNotes: string;
  materialsUsed?: Array<{ name: string; quantity: number }>;
  patientResponse?: string;
  followupRecommendations?: string;
  amendmentReason?: string;
}

export interface UpdateBeneficiaryProfileDto {
  displayName?: string;
  relationship?: string;
  dateOfBirth?: string;
  gender?: 'MALE' | 'FEMALE';
  knownAllergies?: string[];
  chronicConditions?: string[];
  currentMedications?: Array<{ name: string; dosage?: string; frequency?: string }>;
  careNotes?: string;
  emergencyContactPhone?: string;
}

@Injectable()
export class HealthRecordsService {
  constructor(private readonly db: DbService) {}

  /** Asserts actor is allowed to access beneficiary health record and logs audit */
  async assertBeneficiaryAccess(
    actorUserId: string,
    beneficiaryId: string,
    action: string,
    requestId?: string,
  ): Promise<{ isOwner: boolean; isAssignedNurse: boolean; isAdmin: boolean }> {
    const actor = (await this.db.query(`SELECT id, role FROM users WHERE id = $1`, [actorUserId])).rows[0];
    if (!actor) throw new ForbiddenException({ code: 'USER_NOT_FOUND' });

    const ben = (await this.db.query(`SELECT owner_user_id FROM beneficiaries WHERE id = $1`, [beneficiaryId])).rows[0];
    if (!ben) throw new NotFoundException({ code: 'BENEFICIARY_NOT_FOUND' });

    const isOwner = ben.owner_user_id === actorUserId;
    const isAdmin = ['ADMIN', 'CLINICAL_REVIEWER'].includes(actor.role);

    let isAssignedNurse = false;
    if (actor.role === 'NURSE') {
      const activeVisit = await this.db.query(`
        SELECT cr.id FROM care_requests cr
        JOIN request_assignments ra ON ra.request_id = cr.id
        JOIN nurses n ON n.id = ra.nurse_id
        WHERE cr.beneficiary_id = $1
          AND n.user_id = $2
          AND ra.status = 'ACTIVE'
          AND cr.status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED')
          AND ($3::uuid IS NULL OR cr.id = $3::uuid)
        LIMIT 1
      `, [beneficiaryId, actorUserId, requestId ?? null]);

      isAssignedNurse = (activeVisit.rowCount ?? 0) > 0;
    }

    if (!isOwner && !isAssignedNurse && !isAdmin) {
      throw new ForbiddenException({ code: 'HEALTH_RECORD_ACCESS_DENIED' });
    }

    // Record audit trail
    await this.db.query(`
      INSERT INTO health_record_access_audit(actor_user_id, beneficiary_id, request_id, action)
      VALUES($1, $2, $3, $4)
    `, [actorUserId, beneficiaryId, requestId ?? null, action]).catch(() => {});

    return { isOwner, isAssignedNurse, isAdmin };
  }

  /** Gets health profile of beneficiary */
  async getBeneficiaryProfile(actorUserId: string, beneficiaryId: string, requestId?: string) {
    await this.assertBeneficiaryAccess(actorUserId, beneficiaryId, 'VIEW_PROFILE', requestId);

    const res = await this.db.query(`
      SELECT b.id, b.owner_user_id, b.display_name, b.relationship, b.date_of_birth,
             b.gender, b.known_allergies, b.chronic_conditions, b.current_medications,
             b.care_notes, b.emergency_contact_phone, b.consent_status, b.created_at, b.updated_at
      FROM beneficiaries b
      WHERE b.id = $1
    `, [beneficiaryId]);

    const latestVitals = await this.db.query(`
      SELECT DISTINCT ON (observation_type)
             observation_type, numeric_value, unit, measured_at, verification_status
      FROM clinical_observations
      WHERE beneficiary_id = $1
      ORDER BY observation_type, measured_at DESC
    `, [beneficiaryId]);

    return {
      profile: res.rows[0],
      latestObservations: latestVitals.rows,
    };
  }

  /** Updates patient profile */
  async updateBeneficiaryProfile(patientUserId: string, beneficiaryId: string, dto: UpdateBeneficiaryProfileDto) {
    const ben = await this.db.query(`SELECT owner_user_id FROM beneficiaries WHERE id = $1`, [beneficiaryId]);
    if (!ben.rowCount) throw new NotFoundException({ code: 'BENEFICIARY_NOT_FOUND' });
    if (ben.rows[0].owner_user_id !== patientUserId) throw new ForbiddenException({ code: 'NOT_BENEFICIARY_OWNER' });

    const res = await this.db.query(`
      UPDATE beneficiaries
      SET display_name = coalesce($2, display_name),
          relationship = coalesce($3, relationship),
          date_of_birth = coalesce($4::date, date_of_birth),
          gender = coalesce($5, gender),
          known_allergies = coalesce($6, known_allergies),
          chronic_conditions = coalesce($7, chronic_conditions),
          current_medications = coalesce($8::jsonb, current_medications),
          care_notes = coalesce($9, care_notes),
          emergency_contact_phone = coalesce($10, emergency_contact_phone),
          updated_at = now()
      WHERE id = $1
      RETURNING *
    `, [
      beneficiaryId,
      dto.displayName ?? null,
      dto.relationship ?? null,
      dto.dateOfBirth ?? null,
      dto.gender ?? null,
      dto.knownAllergies ?? null,
      dto.chronicConditions ?? null,
      dto.currentMedications ? JSON.stringify(dto.currentMedications) : null,
      dto.careNotes ?? null,
      dto.emergencyContactPhone ?? null,
    ]);

    return res.rows[0];
  }

  /** Records clinical measurements/observations */
  async recordObservations(
    actorUserId: string,
    beneficiaryId: string,
    requestId: string | undefined,
    observations: ObservationInputDto[],
  ) {
    await this.assertBeneficiaryAccess(actorUserId, beneficiaryId, 'RECORD_OBSERVATIONS', requestId);

    if (!Array.isArray(observations) || observations.length === 0) {
      throw new BadRequestException({ code: 'EMPTY_OBSERVATIONS' });
    }

    const typeCodes = [...new Set(observations.map(o => o.observationType))];
    const typesRes = await this.db.query(
      `SELECT code, unit, min_value, max_value FROM clinical_observation_types WHERE code = ANY($1::text[])`,
      [typeCodes],
    );
    const typeMap = new Map(typesRes.rows.map(r => [r.code, r]));

    // Strict clinical validation
    for (const obs of observations) {
      const typeDef = typeMap.get(obs.observationType);
      if (!typeDef) {
        throw new BadRequestException({ code: 'INVALID_OBSERVATION_TYPE', detail: obs.observationType });
      }
      const val = Number(obs.numericValue);
      const min = Number(typeDef.min_value);
      const max = Number(typeDef.max_value);
      if (isNaN(val) || val < min || val > max) {
        throw new BadRequestException({
          code: 'OBSERVATION_OUT_OF_RANGE',
          detail: `${obs.observationType} must be between ${min} and ${max} ${typeDef.unit}`,
        });
      }
    }

    return this.db.transaction(async client => {
      const inserted: any[] = [];
      for (const obs of observations) {
        const typeDef = typeMap.get(obs.observationType)!;
        const measuredAt = obs.measuredAt ? new Date(obs.measuredAt).toISOString() : new Date().toISOString();
        const res = await client.query(`
          INSERT INTO clinical_observations(
            beneficiary_id, request_id, recorded_by_user_id, observation_type,
            numeric_value, unit, source, notes, measured_at
          )
          VALUES($1, $2, $3, $4, $5, $6, coalesce($7, 'NURSE_VISIT'), $8, $9)
          RETURNING *
        `, [
          beneficiaryId,
          requestId ?? null,
          actorUserId,
          obs.observationType,
          obs.numericValue,
          typeDef.unit,
          obs.source ?? 'NURSE_VISIT',
          obs.notes ?? null,
          measuredAt,
        ]);
        inserted.push(res.rows[0]);
      }
      return inserted;
    });
  }

  /** Time-series trends for charts */
  async getObservationTimeline(actorUserId: string, beneficiaryId: string, type?: string, limit = 50) {
    await this.assertBeneficiaryAccess(actorUserId, beneficiaryId, 'VIEW_OBSERVATIONS');
    const clampedLimit = Math.min(Math.max(1, limit), 100);

    let query = `
      SELECT o.id, o.observation_type, t.name_ar, t.name_en, o.numeric_value,
             o.unit, o.source, o.measured_at, o.notes, o.request_id
      FROM clinical_observations o
      JOIN clinical_observation_types t ON t.code = o.observation_type
      WHERE o.beneficiary_id = $1
    `;
    const params: unknown[] = [beneficiaryId];

    if (type) {
      params.push(type);
      query += ` AND o.observation_type = $2`;
    }
    params.push(clampedLimit);
    query += ` ORDER BY o.measured_at DESC LIMIT $${params.length}`;

    const res = await this.db.query(query, params);
    return res.rows;
  }

  /** Field-tailored form configuration for nurse during visit */
  async getNurseFormConfig(requestId: string, nurseUserId: string) {
    const reqRes = await this.db.query(`
      SELECT cr.id, cr.beneficiary_id, cr.service_id, s.code AS primary_code, s.title_ar AS primary_title
      FROM care_requests cr
      JOIN services s ON s.id = cr.service_id
      WHERE cr.id = $1
    `, [requestId]);

    if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
    const req = reqRes.rows[0];

    const items = await this.db.query(`
      SELECT s.id, s.code, s.title_ar, s.requires_prescription, s.category_id,
             sc.code AS category_code
      FROM care_request_items cri
      JOIN services s ON s.id = cri.service_id
      LEFT JOIN service_categories sc ON sc.id = s.category_id
      WHERE cri.request_id = $1
    `, [requestId]);

    const serviceCodes = items.rowCount
      ? items.rows.map(r => r.code)
      : [req.primary_code];

    const requiredFields: Array<{ code: string; nameAr: string; unit: string; required: boolean }> = [];
    const showVitals = serviceCodes.some(c => ['VITAL_SIGNS', 'BP_GLUCOSE_CHECK', 'ELDERLY_NURSING', 'CHRONIC_CARE_VISIT', 'IV_INFUSION'].includes(c));
    const showWound = serviceCodes.some(c => c.startsWith('WOUND_') || c.startsWith('SUTURE_'));
    const showGlucose = serviceCodes.some(c => ['BP_GLUCOSE_CHECK', 'VITAL_SIGNS', 'INJ_SC', 'CHRONIC_CARE_VISIT'].includes(c));

    if (showVitals) {
      requiredFields.push({ code: 'SYSTOLIC_BP', nameAr: 'ضغط الدم الانقباضي', unit: 'mmHg', required: true });
      requiredFields.push({ code: 'DIASTOLIC_BP', nameAr: 'ضغط الدم الانبساطي', unit: 'mmHg', required: true });
      requiredFields.push({ code: 'HEART_RATE', nameAr: 'معدل النبض', unit: 'bpm', required: true });
      requiredFields.push({ code: 'TEMPERATURE', nameAr: 'حرارة الجسم', unit: '°C', required: false });
      requiredFields.push({ code: 'O2_SATURATION', nameAr: 'تشبع الأكسجين', unit: '%', required: false });
    }

    if (showGlucose) {
      requiredFields.push({ code: 'BLOOD_GLUCOSE', nameAr: 'سكر الدم', unit: 'mg/dL', required: true });
    }

    if (showWound) {
      requiredFields.push({ code: 'PAIN_SCORE', nameAr: 'مستوى الألم (0-10)', unit: 'scale_0_10', required: false });
    }

    return {
      requestId,
      beneficiaryId: req.beneficiary_id,
      services: items.rows.length ? items.rows : [{ code: req.primary_code, titleAr: req.primary_title }],
      suggestedFields: requiredFields,
      hasWoundAssessment: showWound,
    };
  }

  /** Saves visit note with 24h amendment window & version history */
  async saveVisitNote(nurseUserId: string, requestId: string, dto: VisitNoteInputDto, isDraft = false) {
    const reqRes = await this.db.query(`
      SELECT cr.id, cr.beneficiary_id, ra.nurse_id, n.user_id AS nurse_user_id
      FROM care_requests cr
      JOIN request_assignments ra ON ra.request_id = cr.id AND ra.status = 'ACTIVE'
      JOIN nurses n ON n.id = ra.nurse_id
      WHERE cr.id = $1
    `, [requestId]);

    if (!reqRes.rowCount) throw new NotFoundException({ code: 'ACTIVE_ASSIGNMENT_NOT_FOUND' });
    if (reqRes.rows[0].nurse_user_id !== nurseUserId) throw new ForbiddenException({ code: 'NOT_ASSIGNED_NURSE' });

    const beneficiaryId = reqRes.rows[0].beneficiary_id;

    return this.db.transaction(async client => {
      const existing = await client.query(
        `SELECT * FROM clinical_visit_notes WHERE request_id = $1 FOR UPDATE`,
        [requestId],
      );

      if (!existing.rowCount) {
        // Create new note
        const res = await client.query(`
          INSERT INTO clinical_visit_notes(
            request_id, beneficiary_id, nurse_user_id, status, services_performed,
            clinical_notes, materials_used, patient_response, followup_recommendations,
            submitted_at, finalized_at
          )
          VALUES($1, $2, $3, $4, $5::jsonb, $6, $7::jsonb, $8, $9, $10, $11)
          RETURNING *
        `, [
          requestId,
          beneficiaryId,
          nurseUserId,
          isDraft ? 'DRAFT' : 'SUBMITTED',
          JSON.stringify(dto.servicesPerformed ?? []),
          dto.clinicalNotes,
          JSON.stringify(dto.materialsUsed ?? []),
          dto.patientResponse ?? null,
          dto.followupRecommendations ?? null,
          isDraft ? null : new Date().toISOString(),
          isDraft ? null : new Date().toISOString(),
        ]);
        return res.rows[0];
      }

      // Existing note update/amendment
      const current = existing.rows[0];
      const hoursSinceSubmitted = current.submitted_at
        ? (Date.now() - new Date(current.submitted_at).getTime()) / (3600 * 1000)
        : 0;

      // Archive previous version if note was already submitted
      if (current.status !== 'DRAFT') {
        if (!dto.amendmentReason) {
          throw new BadRequestException({ code: 'AMENDMENT_REASON_MANDATORY' });
        }

        await client.query(`
          INSERT INTO clinical_note_versions(note_id, version_number, snapshot, amended_by, amendment_reason)
          VALUES($1, $2, $3::jsonb, $4, $5)
        `, [
          current.id,
          current.version,
          JSON.stringify(current),
          nurseUserId,
          dto.amendmentReason,
        ]);
      }

      const nextStatus = current.status === 'DRAFT'
        ? (isDraft ? 'DRAFT' : 'SUBMITTED')
        : (hoursSinceSubmitted <= 24 ? 'AMENDED' : 'FINALIZED');

      const res = await client.query(`
        UPDATE clinical_visit_notes
        SET services_performed = $2::jsonb,
            clinical_notes = $3,
            materials_used = $4::jsonb,
            patient_response = $5,
            followup_recommendations = $6,
            amendment_reason = $7,
            version = version + 1,
            status = $8,
            updated_at = now()
        WHERE id = $1
        RETURNING *
      `, [
        current.id,
        JSON.stringify(dto.servicesPerformed ?? []),
        dto.clinicalNotes,
        JSON.stringify(dto.materialsUsed ?? []),
        dto.patientResponse ?? null,
        dto.followupRecommendations ?? null,
        dto.amendmentReason ?? null,
        nextStatus,
      ]);

      return res.rows[0];
    });
  }

  /** Gets visit clinical note and its version history */
  async getVisitNote(actorUserId: string, requestId: string) {
    const noteRes = await this.db.query(`
      SELECT n.*, u.phone_e164 AS nurse_phone
      FROM clinical_visit_notes n
      JOIN users u ON u.id = n.nurse_user_id
      WHERE n.request_id = $1
    `, [requestId]);

    if (!noteRes.rowCount) throw new NotFoundException({ code: 'CLINICAL_NOTE_NOT_FOUND' });
    const note = noteRes.rows[0];

    await this.assertBeneficiaryAccess(actorUserId, note.beneficiary_id, 'VIEW_VISIT_NOTE', requestId);

    const versions = await this.db.query(`
      SELECT id, version_number, amended_by, amendment_reason, amended_at
      FROM clinical_note_versions
      WHERE note_id = $1
      ORDER BY version_number DESC
    `, [note.id]);

    return {
      ...note,
      versionHistory: versions.rows,
    };
  }
}
