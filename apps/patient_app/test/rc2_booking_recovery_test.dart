import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/features/booking/booking_draft_store.dart';
import 'package:tamreedy_patient_app/features/booking/pending_clinical_upload_store.dart';
import 'package:tamreedy_patient_app/features/booking/pending_request_operation_store.dart';
import 'package:tamreedy_patient_app/features/catalog/catalog_store.dart';

class MemoryApi extends TamreedyApi {
  final values = <String, String>{};
  String? owner = 'patient-a';
  Completer<List<dynamic>>? pendingBeneficiaries;
  final posts = <Map<String, dynamic>>[];
  final headers = <Map<String, String>?>[];
  bool failUpload = false;
  bool loseCreateResponse = false;
  int uploads = 0;
  String clinicalStatus = 'PENDING';
  final request = <String, dynamic>{
    'id': 'request-a',
    'status': 'OFFERING',
    'clinical_approval_status': 'PENDING',
    'beneficiary_name': 'خالد أحمد',
  };

  @override
  Future<String?> currentUserId() async => owner;
  @override
  Future<String?> readLocal(String key) async => values[key];
  @override
  Future<void> writeLocal(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<List<dynamic>> getList(
    String path, {
    CancelToken? cancelToken,
  }) async => pendingBeneficiaries == null ? [] : pendingBeneficiaries!.future;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    CancelToken? cancelToken,
  }) async => {...request, 'clinical_approval_status': clinicalStatus};

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? data,
    Map<String, String>? extraHeaders,
    CancelToken? cancelToken,
  ]) async {
    posts.add(Map<String, dynamic>.from(data ?? {}));
    headers.add(extraHeaders);
    if (loseCreateResponse) {
      throw StateError('Connection lost after server commit');
    }
    return Map<String, dynamic>.from(request);
  }

  @override
  Future<void> uploadClinicalEvidence(
    String requestId,
    String evidenceType,
    List<int> bytes,
    String filename,
  ) async {
    uploads++;
    if (failUpload) throw StateError('Upload unavailable');
    return;
  }
}

BookingDraftStore readyDraft(
  MemoryApi api,
  PendingClinicalUploadStore uploads,
) {
  final catalog = CatalogStore(api: api);
  final draft = BookingDraftStore(
    api: api,
    catalog: catalog,
    clinicalUploads: uploads,
  );
  draft.serviceQuantities['service-a'] = 1;
  draft.selectedBeneficiaryId = 'beneficiary-a';
  draft.locationPoint = kDamascus;
  draft.addressLabel = 'دمشق، المزة';
  draft.estimateStatus = EstimateStatus.verified;
  draft.capabilities = const ServerCapabilities(ordersAccepting: true);
  addTearDown(draft.dispose);
  addTearDown(catalog.dispose);
  return draft;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryApi api;
  late Directory directory;
  late PendingClinicalUploadStore uploads;

  setUp(() async {
    api = MemoryApi();
    directory = await Directory.systemTemp.createTemp('tamreedy-rc2-clinical-');
    uploads = PendingClinicalUploadStore(
      api: api,
      supportDirectory: () async => directory,
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'RC2-030 request creation survives restart with the identical key and Arabic payload',
    () async {
      final first = PendingRequestOperationStore(api);
      final operation = await first.begin('patient-a', {
        'addressText': 'دمشق، المزة',
        'quantity': 1,
      });
      final restored = PendingRequestOperationStore(api);
      final retry = await restored.begin('patient-a', {
        'quantity': 1,
        'addressText': 'دمشق، المزة',
      });
      expect(retry['idempotencyKey'], operation['idempotencyKey']);
      expect(retry['operationId'], operation['operationId']);
      expect(
        jsonDecode(retry['canonicalPayload'] as String)['addressText'],
        'دمشق، المزة',
      );
    },
  );

  test(
    'RC2-030 a changed draft cannot overwrite an unresolved operation',
    () async {
      final store = PendingRequestOperationStore(api);
      final original = await store.begin('patient-a', {'quantity': 1});
      await expectLater(
        store.begin('patient-a', {'quantity': 2}),
        throwsStateError,
      );
      expect(
        (await store.read('patient-a'))!['idempotencyKey'],
        original['idempotencyKey'],
      );
      expect(await store.read('patient-b'), isNull);
      await expectLater(store.begin('', {'quantity': 1}), throwsStateError);
    },
  );

  test(
    'RC2-030 CONFIRMED persists the result before RECONCILED removes sensitive payload',
    () async {
      final store = PendingRequestOperationStore(api);
      final operation = await store.begin('patient-a', {
        'addressText': 'المزة',
      });
      await expectLater(
        store.reconcile('patient-a', 'request-a'),
        throwsStateError,
      );
      await store.confirm('patient-a', operation, api.request);
      final restored = (await PendingRequestOperationStore(
        api,
      ).read('patient-a'))!;
      expect(restored['status'], 'CONFIRMED');
      expect(restored['confirmedResponse']['id'], 'request-a');
      await store.reconcile('patient-a', 'request-a');
      final reconciled = (await store.read('patient-a'))!;
      expect(reconciled['status'], 'RECONCILED');
      expect(reconciled.containsKey('canonicalPayload'), isFalse);
      expect(reconciled.containsKey('confirmedResponse'), isFalse);
    },
  );

  test(
    'RC2-019 private file is authenticated ciphertext and survives process restart',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('تقرير طبي خاص بالمريض'));
      final metadata = await uploads.prepare(
        ownerUserId: 'patient-a',
        operationId: 'operation-a',
        evidenceType: 'CLINICAL_REPORT',
        filename: 'تقرير.pdf',
        bytes: bytes,
      );
      await uploads.bindRequest('patient-a', 'request-a');
      final file = File(
        '${directory.path}/clinical_uploads/${metadata['encryptedFileReference']}',
      );
      expect(await file.readAsBytes(), isNot(orderedEquals(bytes)));
      final restored = PendingClinicalUploadStore(
        api: api,
        supportDirectory: () async => directory,
      );
      expect(await restored.readBytes('patient-a'), orderedEquals(bytes));
      expect((await restored.metadata('patient-a'))!['requestId'], 'request-a');
      expect(await restored.metadata('patient-b'), isNull);
      await restored.complete('patient-a');
      expect(await file.exists(), isFalse);
      expect(await restored.metadata('patient-a'), isNull);
      expect(
        api.values.keys.where((key) => key.startsWith('clinical_upload_key_')),
        isEmpty,
      );
    },
  );

  test(
    'RC2-019 rejects tampered ciphertext and replacing unresolved evidence',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final value = await uploads.prepare(
        ownerUserId: 'patient-a',
        operationId: 'operation-a',
        evidenceType: 'PRESCRIPTION',
        filename: 'rx.pdf',
        bytes: bytes,
      );
      await expectLater(
        uploads.prepare(
          ownerUserId: 'patient-a',
          operationId: 'operation-a',
          evidenceType: 'PRESCRIPTION',
          filename: 'rx.pdf',
          bytes: Uint8List.fromList([4]),
        ),
        throwsStateError,
      );
      final file = File(
        '${directory.path}/clinical_uploads/${value['encryptedFileReference']}',
      );
      final ciphertext = await file.readAsBytes();
      ciphertext[ciphertext.length - 1] ^= 1;
      await file.writeAsBytes(ciphertext);
      await expectLater(uploads.readBytes('patient-a'), throwsA(anything));
    },
  );

  test(
    'RC2-010 late previous-account reads cannot repopulate reset draft',
    () async {
      final draft = readyDraft(api, uploads);
      api.pendingBeneficiaries = Completer<List<dynamic>>();
      final pending = draft.loadBeneficiaries();
      draft.savedPlaces = const [
        SavedPlaceModel(
          id: 'a',
          label: 'منزل',
          placeType: 'HOME',
          formattedAddress: 'دمشق',
          latitude: 33,
          longitude: 36,
        ),
      ];
      draft.stagedEvidence = StagedEvidence(
        evidenceType: 'PRESCRIPTION',
        filename: 'rx.pdf',
        bytes: Uint8List(1),
      );
      draft.resetForSessionChange();
      api.owner = 'patient-b';
      api.pendingBeneficiaries!.complete([
        {'id': 'old-beneficiary', 'display_name': 'المريض السابق'},
      ]);
      await pending;
      expect(draft.beneficiaries, isEmpty);
      expect(draft.savedPlaces, isEmpty);
      expect(draft.serviceQuantities, isEmpty);
      expect(draft.locationPoint, isNull);
      expect(draft.stagedEvidence, isNull);
      expect(draft.addressLabel, isEmpty);
      expect(draft.loadingBeneficiaries, isFalse);
    },
  );

  test(
    'RC2-010 drafts are never restored into another owner or from legacy shared key',
    () async {
      api.values['patient_booking_draft_v3'] = jsonEncode({
        'addressLabel': 'عنوان قديم',
      });
      api.values['patient_booking_draft_v3_patient-a'] = jsonEncode({
        'addressLabel': 'عنوان المريض أ',
      });
      final draft = readyDraft(api, uploads);
      await draft.restoreDraft();
      expect(draft.addressLabel, 'عنوان المريض أ');
      draft.resetForSessionChange();
      api.owner = 'patient-b';
      await draft.restoreDraft();
      expect(draft.addressLabel, isEmpty);
      expect(api.values.containsKey('patient_booking_draft_v3'), isFalse);
      expect(
        api.values.containsKey('patient_booking_draft_v3_patient-a'),
        isTrue,
      );
    },
  );

  test(
    'RC2-030 lost creation response is replayed from durable payload without a new key',
    () async {
      final draft = readyDraft(api, uploads);
      api.loseCreateResponse = true;
      expect(await draft.submit(), isNull);
      expect(draft.hasUnresolvedRequest, isTrue);
      final firstKey = api.headers.single!['Idempotency-Key'];
      draft.resetForSessionChange();
      api.loseCreateResponse = false;
      await draft.restoreDraft();
      final recovered = await draft.recoverPendingRequest();
      expect(recovered!.id, 'request-a');
      expect(api.posts.length, 2);
      expect(api.posts.last, api.posts.first);
      expect(api.headers.last!['Idempotency-Key'], firstKey);
      expect(
        (await PendingRequestOperationStore(api).read('patient-a'))!['status'],
        'RECONCILED',
      );
    },
  );

  test(
    'RC2-019 failed medical upload can restart and retry for the same request',
    () async {
      final draft = readyDraft(api, uploads);
      draft.setStagedEvidence(
        StagedEvidence(
          evidenceType: 'PRESCRIPTION',
          filename: 'وصفة.pdf',
          bytes: Uint8List.fromList(utf8.encode('وصفة طبية')),
        ),
      );
      api.failUpload = true;
      expect((await draft.submit())!.id, 'request-a');
      expect(draft.pendingEvidenceRequestId, 'request-a');
      expect(await uploads.metadata('patient-a'), isNotNull);
      draft.resetForSessionChange();
      await draft.restoreDraft();
      expect(draft.stagedEvidence!.filename, 'وصفة.pdf');
      api.failUpload = false;
      expect(await draft.retryPendingEvidenceUpload(), isTrue);
      expect(api.posts.length, 1);
      expect(draft.pendingEvidenceRequestId, isNull);
      expect(await uploads.metadata('patient-a'), isNull);
    },
  );

  test(
    'RC2-019 rejects upload after approval while retaining encrypted recovery data',
    () async {
      await uploads.prepare(
        ownerUserId: 'patient-a',
        operationId: 'operation-a',
        evidenceType: 'PRESCRIPTION',
        filename: 'rx.pdf',
        bytes: Uint8List.fromList([1]),
      );
      await uploads.bindRequest('patient-a', 'request-a');
      api.clinicalStatus = 'APPROVED';
      final draft = readyDraft(api, uploads);
      await draft.restoreDraft();
      expect(await draft.retryPendingEvidenceUpload(), isFalse);
      expect(api.uploads, 0);
      expect(await uploads.metadata('patient-a'), isNotNull);
    },
  );

  test(
    'RC2-028 refuses order creation with unavailable server capabilities',
    () async {
      final draft = readyDraft(api, uploads);
      draft.updateCapabilities(
        const ServerCapabilities(ordersAccepting: false),
      );
      expect(await draft.submit(), isNull);
      expect(api.posts, isEmpty);
      expect(draft.submitting, isFalse);
    },
  );

  test('RC2-030 refuses creation without authenticated owner', () async {
    final draft = readyDraft(api, uploads);
    api.owner = null;
    expect(await draft.submit(), isNull);
    expect(api.posts, isEmpty);
    expect(
      api.values.keys.where((key) => key.startsWith('pending_create_op_')),
      isEmpty,
    );
    expect(draft.submitting, isFalse);
  });
  test('RC2-030 late confirmation cannot replace a newer operation', () async {
    final store = PendingRequestOperationStore(api);
    final original = await store.begin('patient-a', {'quantity': 1});
    await store.confirm('patient-a', original, api.request);
    await store.reconcile('patient-a', 'request-a');
    final next = await store.begin('patient-a', {'quantity': 2});
    await expectLater(
      store.confirm('patient-a', original, api.request),
      throwsStateError,
    );
    expect(
      (await store.read('patient-a'))!['operationId'],
      next['operationId'],
    );
    expect((await store.read('patient-a'))!['status'], 'PENDING');
  });
}
