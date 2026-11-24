import { Module } from '@nestjs/common';
import { MarketplaceEligibilityService } from './marketplace-eligibility.service.js';
import { MarketplaceService } from './marketplace.service.js';
import { ProposalsService } from './proposals.service.js';
import { AssignmentService } from './assignment.service.js';
import { BookingModeService } from './booking-mode.service.js';
import { MarketplaceController } from './marketplace.controller.js';
import { ProposalsController } from './proposals.controller.js';
import { BookingModeController } from './booking-mode.controller.js';

@Module({
  controllers: [
    MarketplaceController,
    ProposalsController,
    BookingModeController,
  ],
  providers: [
    MarketplaceEligibilityService,
    MarketplaceService,
    ProposalsService,
    AssignmentService,
    BookingModeService,
  ],
  exports: [
    MarketplaceEligibilityService,
    MarketplaceService,
    ProposalsService,
    AssignmentService,
    BookingModeService,
  ],
})
export class MarketplaceModule {}
