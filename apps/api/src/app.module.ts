import { ReadinessService } from './capabilities/readiness.service.js';
import { FeatureCapabilitiesService } from './capabilities/feature-capabilities.service.js';
import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { DbService } from './db/db.service.js';
import { ReferenceCacheService } from './cache/reference-cache.service.js';
import { AuthGuard } from './auth/auth.guard.js';
import { RequestsService } from './requests/requests.service.js';
import { RequestsController } from './requests/requests.controller.js';
import { DispatchService } from './dispatch/dispatch.service.js';
import { NursesService } from './nurses/nurses.service.js';
import { NursesController } from './nurses/nurses.controller.js';
import { ReviewsService } from './reviews/reviews.service.js';
import { ReviewsController } from './reviews/reviews.controller.js';
import { WalletController } from './wallet/wallet.controller.js';
import { AdminController } from './admin/admin.controller.js';
import { AdminReportsController } from './admin/admin-reports.controller.js';
import { NurseMeController } from './nurses/nurse-me.controller.js';
import { AuthController } from './auth/auth.controller.js';
import { AuthService, DevConsoleSms, SmsProvider } from './auth/auth.service.js';
import { AdminNursesController } from './admin/admin-nurses.controller.js';
import { AdminSettingsController } from './admin/admin-settings.controller.js';
import { RegionsPublicController, AdminRegionsController } from './admin/regions.controller.js';
import { AccountController } from './auth/account.controller.js';
import { ApplicationsPublicController, AdminApplicationsController } from './auth/applications.controller.js';
import { DocStore } from './admin/doc-store.js';
import { RegistrationController, NurseOnboardingController } from './auth/registration.controller.js';
import { AdminUsersController } from './admin/admin-users.controller.js';
import { DevicesController } from './devices/devices.controller.js';
import { RoutesController } from './maps/routes.controller.js';
import { RoutesService } from './maps/routes.service.js';
import { PricingController } from './pricing/pricing.controller.js';
import { PromoService } from './pricing/promo.service.js';
import { AdminBusinessController } from './admin/admin-business.controller.js';
import { AdminFeesController } from './admin/admin-fees.controller.js';
import { ReferralController } from './pricing/referral.controller.js';
import { DuesService, FeesService } from './pricing/fees.service.js';
import { ReferralService } from './pricing/referral.service.js';
import { MarketingController } from './admin/marketing.controller.js';
import { AdminDispatchController } from './admin/admin-dispatch.controller.js';
import { MeController } from './auth/me.controller.js';
import { AutoDiscountService } from './pricing/auto-discounts.service.js';
import { AppController } from './app.controller.js';
import { CatalogController } from './catalog/catalog.controller.js';
import { AppealsController } from './requests/appeals.controller.js';
import { AppealsService } from './requests/appeals.service.js';
import { CommitmentController } from './requests/commitment.controller.js';
import { CommitmentService } from './requests/commitment.service.js';
import { LiveGateway } from './realtime/live.gateway.js';
import { SavedPlacesController } from './saved-places/saved-places.controller.js';
import { SavedPlacesRepository } from './saved-places/saved-places.repository.js';
import { SavedPlacesService } from './saved-places/saved-places.service.js';

import { CheckinsService } from './safety/checkins.service.js';
import { CheckinsRepository } from './safety/checkins.repository.js';
import { SafetyController } from './safety/safety.controller.js';
import { SafetyRepository } from './safety/safety.repository.js';
import { SafetyService } from './safety/safety.service.js';

import { StaffCasesController } from './safety/staff-cases.controller.js';
import { StaffCasesRepository } from './safety/staff-cases.repository.js';
import { StaffCasesService } from './safety/staff-cases.service.js';

import { TrustedContactsController } from './trusted-contacts/trusted-contacts.controller.js';
import { TrustedContactsRepository } from './trusted-contacts/trusted-contacts.repository.js';
import { TrustedContactsService } from './trusted-contacts/trusted-contacts.service.js';

import { SafeAbortRepository } from './safety/safe-abort.repository.js';
import { SafeAbortService } from './safety/safe-abort.service.js';

import { DirectoryController } from './safety/directory.controller.js';
import { DirectoryRepository } from './safety/directory.repository.js';
import { DirectoryService } from './safety/directory.service.js';

import { ShiftsController } from './safety/shifts.controller.js';
import { ShiftsRepository } from './safety/shifts.repository.js';
import { ShiftsService } from './safety/shifts.service.js';

import { HandoversService } from './safety/handovers.js';

import { NightPolicyController } from './safety/night-policy.controller.js';
import { NightPolicyService } from './safety/night-policy.js';

import { VisitRiskController } from './safety/visit-risk.controller.js';
import { VisitRiskService } from './safety/visit-risk.js';

import { EvidenceController } from './safety/evidence.controller.js';
import { EvidenceRepository } from './safety/evidence.repository.js';
import { EvidenceService } from './safety/evidence.service.js';

import { RetentionController } from './safety/retention.controller.js';
import { RetentionService } from './safety/retention.js';
import { ChatController } from './chat/chat.controller.js';
import { ChatService } from './chat/chat.service.js';
import { TrustController } from './trust/trust.controller.js';
import { TrustService } from './trust/trust.service.js';
import { NurseCalendarController } from './scheduling/calendar.controller.js';
import { NurseCalendarService } from './scheduling/calendar.service.js';
import { AssignmentLocationAuthorizationService } from './requests/assignment-location-authorization.service.js';
import { CarePlansController } from './care-plans/care-plans.controller.js';
import { CarePlansService } from './care-plans/care-plans.service.js';
import { HealthRecordsController } from './health-records/health-records.controller.js';
import { HealthRecordsService } from './health-records/health-records.service.js';
import { ClinicalReportsController } from './clinical-reports/clinical-reports.controller.js';
import { ClinicalReportsService } from './clinical-reports/clinical-reports.service.js';
import { FavoritesController } from './nurses/favorites.controller.js';
import { FavoritesService } from './nurses/favorites.service.js';
import { PackagesController } from './marketing/packages.controller.js';
import { PackagesService } from './marketing/packages.service.js';
import { LedgerService } from './wallet/ledger.service.js';
import { NurseFinancialController } from './nurses/nurse-financial.controller.js';
import { NurseFinancialService } from './nurses/nurse-financial.service.js';
import { PricingCompositionService } from './pricing/pricing-composition.service.js';
import { FinancialReservationsService } from './wallet/financial-reservations.service.js';
import { VoiceController } from './voice/voice.controller.js';
import { VoiceService } from './voice/voice.service.js';
import { NotificationsController } from './notifications/notifications.controller.js';
import { NotificationsService } from './notifications/notifications.service.js';
import { MarketplaceController } from './marketplace/marketplace.controller.js';
import { ProposalsController } from './marketplace/proposals.controller.js';
import { BookingModeController } from './marketplace/booking-mode.controller.js';
import { MarketplaceEligibilityService } from './marketplace/marketplace-eligibility.service.js';
import { MarketplaceService } from './marketplace/marketplace.service.js';
import { ProposalsService } from './marketplace/proposals.service.js';
import { AssignmentService } from './marketplace/assignment.service.js';
import { BookingModeService } from './marketplace/booking-mode.service.js';
import { AdminBookingController } from './admin/admin-booking.controller.js';
import { AdminBookingService } from './admin/admin-booking.service.js';
import { NurseEligibilityEngine } from './dispatch/nurse-eligibility.engine.js';
import { RequestRecoveryService } from './requests/request-recovery.service.js';
import { AssignmentOrchestrator } from './dispatch/assignment.orchestrator.js';
import { BillingService } from './pricing/billing.service.js';
import { RequestItemsService } from './requests/request-items.service.js';
import { ClinicalApprovalController } from './clinical-approvals/clinical-approval.controller.js';
import { ClinicalApprovalService } from './clinical-approvals/clinical-approval.service.js';
import { ClinicalApprovalRepository } from './clinical-approvals/clinical-approval.repository.js';
import { GeoIndexService } from './live-location/geo-index.service.js';
import { LiveLocationService } from './live-location/live-location.service.js';
import { LiveLocationReadService } from './live-location/live-location-read.service.js';
import { LocationPersistenceService } from './live-location/location-persistence.service.js';
import { LocationValidator } from './live-location/location-validator.js';
import { TrackingAuthorizationService } from './live-location/tracking-authorization.service.js';
import { OperationalMetricsService } from './observability/operational-metrics.service.js';
import {
  VerificationProvider,
  TestVerificationProvider,
  SmsVerificationProvider,
  WhatsAppVerificationProvider,
} from './auth/verification-provider.js';

import { RequestRecordController } from './admin/request-record.controller.js';
import { AdminScheduleController } from './admin/admin-schedule.controller.js';
import { AdminScheduleService } from './admin/admin-schedule.service.js';
import { RequestRecordService } from './admin/request-record.service.js';

@Module({
  imports: [
    ThrottlerModule.forRoot([{
      ttl: 60000,
      limit: 120,
    }]),
  ],
  controllers:[AuthController,AppController,CatalogController,RequestsController,NursesController,ReviewsController,WalletController,AdminController,AdminReportsController,AdminUsersController,AdminNursesController,AdminSettingsController,RegionsPublicController,AdminRegionsController,RegistrationController,NurseOnboardingController,ApplicationsPublicController,AdminApplicationsController,AccountController,DevicesController,RoutesController,PricingController,AdminBusinessController,AdminFeesController,AdminDispatchController,MarketingController,MeController,ReferralController,NurseMeController,CommitmentController,AppealsController,SavedPlacesController,SafetyController,StaffCasesController,TrustedContactsController,DirectoryController,ShiftsController,NightPolicyController,VisitRiskController,EvidenceController,RetentionController,ChatController,TrustController,NurseCalendarController,CarePlansController,HealthRecordsController,ClinicalReportsController,ClinicalApprovalController,FavoritesController,PackagesController,NurseFinancialController,VoiceController,NotificationsController,MarketplaceController,ProposalsController,BookingModeController,AdminBookingController,RequestRecordController,AdminScheduleController],
  providers:[
    RequestRecordService,AdminScheduleService,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    DocStore,PromoService,AutoDiscountService,FeesService,DuesService,ReferralService,PricingCompositionService,RoutesService,AuthService,{provide:SmsProvider,useClass:DevConsoleSms},DbService,ReferenceCacheService,OperationalMetricsService,AuthGuard,RequestsService,AssignmentLocationAuthorizationService,RequestRecoveryService,RequestItemsService,ClinicalApprovalRepository,ClinicalApprovalService,AssignmentOrchestrator,BillingService,FinancialReservationsService,GeoIndexService,LocationValidator,LocationPersistenceService,TrackingAuthorizationService,LiveLocationService,LiveLocationReadService,DispatchService,NursesService,ReviewsService,CommitmentService,AppealsService,LiveGateway,SavedPlacesRepository,SavedPlacesService,SafetyRepository,SafetyService,CheckinsRepository,CheckinsService,StaffCasesRepository,StaffCasesService,TrustedContactsRepository,TrustedContactsService,SafeAbortRepository,SafeAbortService,DirectoryRepository,DirectoryService,ShiftsRepository,ShiftsService,HandoversService,NightPolicyService,VisitRiskService,EvidenceRepository,EvidenceService,RetentionService,ChatService,TrustService,NurseCalendarService,CarePlansService,HealthRecordsService,ClinicalReportsService,FavoritesService,PackagesService,LedgerService,NurseFinancialService,VoiceService,NotificationsService,NurseEligibilityEngine,MarketplaceEligibilityService,MarketplaceService,ProposalsService,AssignmentService,BookingModeService,AdminBookingService,
    TestVerificationProvider,SmsVerificationProvider,WhatsAppVerificationProvider,
    {
      provide: VerificationProvider,
      useFactory: (testP: TestVerificationProvider, smsP: SmsVerificationProvider, waP: WhatsAppVerificationProvider) => {
        const prov = (process.env.VERIFICATION_PROVIDER ?? '').toUpperCase();
        if (prov === 'WHATSAPP') return waP;
        if (prov === 'SMS') return smsP;
        if (process.env.NODE_ENV !== 'production') return testP;
        return smsP;
      },
      inject: [TestVerificationProvider, SmsVerificationProvider, WhatsAppVerificationProvider],
    }
  ],
})
export class AppModule {}
