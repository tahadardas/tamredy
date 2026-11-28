import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/core/nurse_session_coordinator.dart';
import 'package:tamreedy_nurse_app/features/marketplace/marketplace_screen.dart';

class NurseCapabilitiesApi extends TamreedyApi {
  NurseCapabilitiesApi() : super(appType: 'NURSE_APP');

  Future<Map<String, dynamic>> Function() capabilities = () async => {
    'openMarketplaceEnabled': true,
  };
  int submitted = 0;
  int browsed = 0;
  int historyReads = 0;
  int withdrawals = 0;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    CancelToken? cancelToken,
  }) => capabilities();

  @override
  Future<List<dynamic>> getMarketplaceRequests({
    double? maxDistanceKm,
    CancelToken? cancelToken,
  }) async {
    browsed++;
    return const [];
  }

  @override
  Future<List<dynamic>> getMyProposals() async => [
    {'id': 'existing-proposal', 'status': 'PENDING'},
  ];

  @override
  Future<List<dynamic>> getList(String path, {CancelToken? cancelToken}) async {
    if (path == '/v1/nurse/me/history') {
      historyReads++;
      return [
        {'service_title': 'زيارة سابقة مؤكدة', 'nurse_earning': 100},
      ];
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> submitProposal(
    String requestId, {
    int? estimatedMinutes,
    String? specificTime,
    String? note,
  }) async {
    submitted++;
    return {};
  }

  @override
  Future<Map<String, dynamic>> withdrawProposal(
    String proposalId, {
    String? reason,
  }) async {
    withdrawals++;
    return {};
  }

  @override
  Future<void> writeLocal(String key, String? value) async {}

  @override
  Future<void> logout() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unknown and disabled capabilities prevent new proposal mutations',
    () async {
      final api = NurseCapabilitiesApi();
      final session = NurseSessionCoordinator(apiOverride: api);
      addTearDown(session.dispose);

      expect(session.canUseOpenMarketplace, isFalse);
      await expectLater(
        session.marketplace.submitProposal('request-a'),
        throwsA(isA<ApiFailure>()),
      );
      expect(api.submitted, 0);

      await session.loadCapabilities();
      expect(session.canUseOpenMarketplace, isTrue);
      await session.marketplace.submitProposal('request-a');
      expect(api.submitted, 1);

      api.capabilities = () async => {'openMarketplaceEnabled': false};
      await session.loadCapabilities();
      await expectLater(
        session.marketplace.submitProposal('request-b'),
        throwsA(isA<ApiFailure>()),
      );
      expect(api.submitted, 1);
    },
  );

  test(
    'capability failure retains visit history reads and existing proposal withdrawal',
    () async {
      final api = NurseCapabilitiesApi();
      final session = NurseSessionCoordinator(apiOverride: api);
      addTearDown(session.dispose);
      api.capabilities = () async => throw StateError('unavailable');

      await session.loadCapabilities();
      expect(session.canUseOpenMarketplace, isFalse);
      expect(session.capabilitiesError, isNotNull);
      await session.marketplace.refreshAll();
      expect(api.browsed, 0);
      expect(api.historyReads, 1);
      expect(
        session.marketplace.completedHistory.single['service_title'],
        'زيارة سابقة مؤكدة',
      );
      await session.marketplace.withdrawProposal('existing-proposal');
      expect(api.withdrawals, 1);
    },
  );

  test(
    'late capability results cannot restore an older snapshot or previous session',
    () async {
      final api = NurseCapabilitiesApi();
      final session = NurseSessionCoordinator(apiOverride: api);
      addTearDown(session.dispose);
      final old = Completer<Map<String, dynamic>>();
      api.capabilities = () => old.future;
      final previous = session.loadCapabilities();
      api.capabilities = () async => {'openMarketplaceEnabled': false};
      await session.loadCapabilities();
      old.complete({'openMarketplaceEnabled': true});
      await previous;
      expect(session.canUseOpenMarketplace, isFalse);
      expect(session.capabilitiesLoading, isFalse);

      final pending = Completer<Map<String, dynamic>>();
      api.capabilities = () => pending.future;
      final late = session.loadCapabilities();
      await session.signOut();
      pending.complete({'openMarketplaceEnabled': true});
      await late;
      expect(session.capabilities, isNull);
      expect(session.canUseOpenMarketplace, isFalse);
      expect(session.capabilitiesLoading, isFalse);
    },
  );

  testWidgets(
    'disabled marketplace keeps the existing visit history tab accessible',
    (tester) async {
      final session = NurseSessionCoordinator(
        apiOverride: NurseCapabilitiesApi(),
      );
      addTearDown(session.dispose);
      session.marketplace.completedHistory = [
        {'service_title': 'زيارة سابقة مؤكدة', 'nurse_earning': 100},
      ];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MarketplaceScreen(session: session),
          ),
        ),
      );
      expect(find.textContaining('السوق المفتوح معطل'), findsOneWidget);
      await tester.tap(find.text('سجلي'));
      await tester.pump();
      expect(find.text('زيارة سابقة مؤكدة'), findsOneWidget);
    },
  );
}
