import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { NurseReportDto, ReviewDto } from '../common/dto.js';
import { conflict, missing } from '../common/errors.js';
@Injectable()
export class ReviewsService {
  constructor(private readonly db: DbService) {}
  async patientReview(userId:string,visitId:string,dto:ReviewDto) {
    const r=await this.db.query(`INSERT INTO visit_reviews(
        visit_id, reviewer_user_id, reviewer_role, stars, behavior_notes,
        punctuality_stars, conduct_stars, clinical_stars, hygiene_stars, overall_stars
      )
      SELECT v.id,$2,'PATIENT',$3,$4,$5,$6,$7,$8,coalesce($9,$3) FROM visits v JOIN request_assignments a ON a.id=v.assignment_id
      JOIN care_requests cr ON cr.id=a.request_id
      WHERE v.id=$1 AND cr.requester_user_id=$2 AND v.completed_at IS NOT NULL
      AND v.completed_at>now()-interval '48 hours'
      ON CONFLICT(visit_id,reviewer_role) DO NOTHING RETURNING id`,[
        visitId,userId,dto.stars,dto.comment??null,
        dto.punctualityStars??null,dto.conductStars??null,
        dto.clinicalStars??null,dto.hygieneStars??null,dto.overallStars??null
      ]);
    if(!r.rowCount) conflict('REVIEW_NOT_ALLOWED_OR_ALREADY_SUBMITTED');
    return {id:r.rows[0].id};
  }
  async nurseReport(userId:string,visitId:string,dto:NurseReportDto) {
    const r=await this.db.query(`INSERT INTO visit_reviews(visit_id,reviewer_user_id,reviewer_role,stars,behavior_notes)
      SELECT v.id,$2,'NURSE',$4,$3 FROM visits v JOIN request_assignments a ON a.id=v.assignment_id
      JOIN nurses n ON n.id=a.nurse_id WHERE v.id=$1 AND n.user_id=$2 AND v.completed_at IS NOT NULL
      AND v.completed_at>now()-interval '48 hours'
      ON CONFLICT(visit_id,reviewer_role) DO NOTHING RETURNING id`,[visitId,userId,`${dto.category}: ${dto.note??''}`,dto.stars??null]);
    if(!r.rowCount) conflict('REPORT_NOT_ALLOWED_OR_ALREADY_SUBMITTED');
    return {id:r.rows[0].id,private:true};
  }
}
