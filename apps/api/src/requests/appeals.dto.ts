import { IsIn, IsString, Length } from 'class-validator';

export const appealReviewStatuses = ['UNDER_REVIEW', 'NEEDS_INFORMATION', 'APPROVED', 'REJECTED', 'CLOSED'] as const;
export type AppealReviewStatus = typeof appealReviewStatuses[number];

export class SubmitAppealDto {
  @IsString() @Length(1, 2000) description!: string;
}

export class ReviewAppealDto {
  @IsIn(appealReviewStatuses) status!: AppealReviewStatus;
  @IsString() @Length(1, 2000) reason!: string;
}
