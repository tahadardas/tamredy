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

@Module({
  imports: [
    ThrottlerModule.forRoot([{
      ttl: 60000,
      limit: 120,
    }]),
  ],
  controllers:[AuthController,AppController,CatalogController,RequestsController,NursesController,ReviewsController,WalletController,AdminController,AdminReportsController,AdminUsersController,AdminNursesController,AdminSettingsController,RegionsPublicController,AdminRegionsController,RegistrationController,NurseOnboardingController,ApplicationsPublicController,AdminApplicationsController,AccountController,DevicesController,RoutesController,PricingController,AdminBusinessController,AdminFeesController,AdminDispatchController,MarketingController,MeController,ReferralController,NurseMeController,CommitmentController,AppealsController,SavedPlacesController,SafetyController,StaffCasesController,TrustedContactsController,DirectoryController,ShiftsController,NightPolicyController],
  providers:[
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    DocStore,PromoService,AutoDiscountService,FeesService,DuesService,ReferralService,RoutesService,AuthService,{provide:SmsProvider,useClass:DevConsoleSms},DbService,ReferenceCacheService,AuthGuard,RequestsService,DispatchService,NursesService,ReviewsService,CommitmentService,AppealsService,LiveGateway,SavedPlacesRepository,SavedPlacesService,SafetyRepository,SafetyService,CheckinsRepository,CheckinsService,StaffCasesRepository,StaffCasesService,TrustedContactsRepository,TrustedContactsService,SafeAbortRepository,SafeAbortService,DirectoryRepository,DirectoryService,ShiftsRepository,ShiftsService,HandoversService,NightPolicyService
  ],
})
export class AppModule {}
