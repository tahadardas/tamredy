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
import { MeController } from './auth/me.controller.js';
import { AutoDiscountService } from './pricing/auto-discounts.service.js';
import { AppController } from './app.controller.js';
import { CatalogController } from './catalog/catalog.controller.js';
import { LiveGateway } from './realtime/live.gateway.js';
@Module({
  imports: [
    ThrottlerModule.forRoot([{
      ttl: 60000,
      limit: 120,
    }]),
  ],
  controllers:[AuthController,AppController,CatalogController,RequestsController,NursesController,ReviewsController,WalletController,AdminController,AdminReportsController,AdminUsersController,AdminNursesController,AdminSettingsController,RegionsPublicController,AdminRegionsController,RegistrationController,NurseOnboardingController,ApplicationsPublicController,AdminApplicationsController,AccountController,DevicesController,RoutesController,PricingController,AdminBusinessController,AdminFeesController,MarketingController,MeController,ReferralController,NurseMeController],
  providers:[
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    DocStore,PromoService,AutoDiscountService,FeesService,DuesService,ReferralService,RoutesService,AuthService,{provide:SmsProvider,useClass:DevConsoleSms},DbService,ReferenceCacheService,AuthGuard,RequestsService,DispatchService,NursesService,ReviewsService,LiveGateway
  ],
})
export class AppModule {}
