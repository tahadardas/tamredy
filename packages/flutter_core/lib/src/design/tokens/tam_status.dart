import 'package:flutter/material.dart';
import 'tam_tokens.dart';

/// Canonical request & visit lifecycle statuses across Patient, Nurse, and Admin.
/// Unknown statuses map to [TamRequestStatus.unknown] and are NEVER treated as
/// searching, success, or available.
enum TamRequestStatus {
  scheduled,
  offering,
  awaitingRecoveryChoice,
  openForProposals,
  assigned,
  enRoute,
  arrived,
  inService,
  completed,
  cancelled,
  unfulfilled,
  expired,
  escalated,
  unknown;

  static TamRequestStatus parse(String? raw) {
    switch (raw?.trim().toUpperCase()) {
      case 'SCHEDULED':
        return TamRequestStatus.scheduled;
      case 'DRAFT':
      case 'REQUESTED':
      case 'OFFERING':
        return TamRequestStatus.offering;
      case 'AWAITING_RECOVERY_CHOICE':
        return TamRequestStatus.awaitingRecoveryChoice;
      case 'OPEN_FOR_PROPOSALS':
        return TamRequestStatus.openForProposals;
      case 'ASSIGNED':
        return TamRequestStatus.assigned;
      case 'EN_ROUTE':
        return TamRequestStatus.enRoute;
      case 'ARRIVED':
        return TamRequestStatus.arrived;
      case 'IN_SERVICE':
        return TamRequestStatus.inService;
      case 'COMPLETED':
        return TamRequestStatus.completed;
      case 'CANCELLED':
        return TamRequestStatus.cancelled;
      case 'UNFULFILLED':
        return TamRequestStatus.unfulfilled;
      case 'EXPIRED':
        return TamRequestStatus.expired;
      case 'ESCALATED':
        return TamRequestStatus.escalated;
      default:
        return TamRequestStatus.unknown;
    }
  }

  String get labelAr {
    switch (this) {
      case TamRequestStatus.scheduled:
        return 'مجدولة';
      case TamRequestStatus.offering:
        return 'قيد البحث عن ممرض';
      case TamRequestStatus.awaitingRecoveryChoice:
        return 'بانتظار قرارك';
      case TamRequestStatus.openForProposals:
        return 'مفتوح للعروض';
      case TamRequestStatus.assigned:
        return 'تم الإسناد';
      case TamRequestStatus.enRoute:
        return 'الممرض في الطريق';
      case TamRequestStatus.arrived:
        return 'وصل الممرض';
      case TamRequestStatus.inService:
        return 'الزيارة قيد التنفيذ';
      case TamRequestStatus.completed:
        return 'مكتملة';
      case TamRequestStatus.cancelled:
        return 'ملغاة';
      case TamRequestStatus.unfulfilled:
        return 'لم يُعثر على ممرض';
      case TamRequestStatus.expired:
        return 'منتهي الصلاحية';
      case TamRequestStatus.escalated:
        return 'توقفت الزيارة (تدخل)';
      case TamRequestStatus.unknown:
        return 'حالة غير معروفة';
    }
  }

  IconData get icon {
    switch (this) {
      case TamRequestStatus.scheduled:
        return Icons.event_available_rounded;
      case TamRequestStatus.offering:
        return Icons.radar_rounded;
      case TamRequestStatus.awaitingRecoveryChoice:
        return Icons.help_outline_rounded;
      case TamRequestStatus.openForProposals:
        return Icons.campaign_rounded;
      case TamRequestStatus.assigned:
        return Icons.person_pin_circle_rounded;
      case TamRequestStatus.enRoute:
        return Icons.directions_car_rounded;
      case TamRequestStatus.arrived:
        return Icons.where_to_vote_rounded;
      case TamRequestStatus.inService:
        return Icons.medical_services_rounded;
      case TamRequestStatus.completed:
        return Icons.check_circle_rounded;
      case TamRequestStatus.cancelled:
        return Icons.cancel_rounded;
      case TamRequestStatus.unfulfilled:
        return Icons.person_off_rounded;
      case TamRequestStatus.expired:
        return Icons.timer_off_rounded;
      case TamRequestStatus.escalated:
        return Icons.warning_amber_rounded;
      case TamRequestStatus.unknown:
        return Icons.info_outline_rounded;
    }
  }

  Color foreground(TamThemeColors c) {
    switch (this) {
      case TamRequestStatus.scheduled:
      case TamRequestStatus.openForProposals:
      case TamRequestStatus.enRoute:
        return c.secondary;
      case TamRequestStatus.offering:
      case TamRequestStatus.assigned:
      case TamRequestStatus.arrived:
      case TamRequestStatus.inService:
        return c.primary;
      case TamRequestStatus.completed:
        return c.success;
      case TamRequestStatus.awaitingRecoveryChoice:
      case TamRequestStatus.unfulfilled:
      case TamRequestStatus.expired:
        return c.warning;
      case TamRequestStatus.cancelled:
      case TamRequestStatus.escalated:
        return c.danger;
      case TamRequestStatus.unknown:
        return c.textSecondary;
    }
  }

  Color background(TamThemeColors c) {
    switch (this) {
      case TamRequestStatus.scheduled:
      case TamRequestStatus.openForProposals:
      case TamRequestStatus.enRoute:
        return c.secondaryTint;
      case TamRequestStatus.offering:
      case TamRequestStatus.assigned:
      case TamRequestStatus.arrived:
      case TamRequestStatus.inService:
        return c.primaryTint;
      case TamRequestStatus.completed:
        return c.successTint;
      case TamRequestStatus.awaitingRecoveryChoice:
      case TamRequestStatus.unfulfilled:
      case TamRequestStatus.expired:
        return c.warningTint;
      case TamRequestStatus.cancelled:
      case TamRequestStatus.escalated:
        return c.dangerTint;
      case TamRequestStatus.unknown:
        return c.surfaceElevated;
    }
  }
}
