import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'core/api_models.dart';
import 'errors.dart';

/// Demo mode runs the apps on built-in sample data (no backend needed).
/// Defaults to FALSE. Must only be enabled explicitly in development with `--dart-define=DEMO=true`.
const bool kDemoMode = bool.fromEnvironment('DEMO', defaultValue: false);

/// Application Environments
enum AppEnvironment { dev, staging, production }

/// Resolves active application environment from compile-time definitions.
AppEnvironment resolveEnvironment() {
  const envStr = String.fromEnvironment('ENVIRONMENT', defaultValue: '');
  if (envStr.toLowerCase() == 'prod' || envStr.toLowerCase() == 'production') {
    return AppEnvironment.production;
  }
  if (envStr.toLowerCase() == 'staging' || envStr.toLowerCase() == 'stage') {
    return AppEnvironment.staging;
  }
  if (envStr.toLowerCase() == 'dev' || envStr.toLowerCase() == 'development') {
    return AppEnvironment.dev;
  }
  return kReleaseMode ? AppEnvironment.production : AppEnvironment.dev;
}

/// Global active environment
final AppEnvironment kAppEnvironment = resolveEnvironment();

/// Default base URLs per environment (override with `--dart-define=API_BASE_URL=...`)
String defaultBaseUrlForEnv(AppEnvironment env) {
  switch (env) {
    case AppEnvironment.production:
      return 'https://tamredy.dardus.com.sy/api';
    case AppEnvironment.staging:
      return 'http://85.215.243.237:18300';
    case AppEnvironment.dev:
      if (kIsWeb) return 'http://localhost:3000';
      return defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:3000'
          : 'http://localhost:3000';
  }
}

/// Interim login is phone + password (accounts are created by an admin).
const String kAuthMode = String.fromEnvironment(
  'AUTH_MODE',
  defaultValue: 'password',
);

/// Centralized API client for all Tamreedy mobile apps (Tamreedy 3.0).
/// Features:
/// - Shared HTTP Client with per-operation timeouts
/// - GET in-flight request deduplication
/// - Request cancellation support via CancelToken
/// - Singleflight auth token refresh
/// - End-to-end correlation IDs
/// - Typed ApiResult<T> & ConnectionHealth tracking
/// - Safe idempotency key helpers (no blind retry of financial/booking mutations)
class TamreedyApi {
  static const String _customBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const _uuid = Uuid();

  /// Identifies whether this client instance is running in PATIENT_APP or NURSE_APP.
  final String appType;

  TamreedyApi({this.appType = 'PATIENT_APP'});

  static String get baseUrl {
    String url = _customBaseUrl.isNotEmpty ? _customBaseUrl : defaultBaseUrlForEnv(kAppEnvironment);
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('API_BASE_URL must be a valid URL');
    }
    if (kAppEnvironment == AppEnvironment.production) {
      if (uri.scheme != 'https') {
        throw StateError('Production API_BASE_URL must be a valid HTTPS URL');
      }
    } else {
      if (uri.scheme != 'https' && uri.scheme != 'http') {
        throw StateError('API_BASE_URL must use http or https scheme');
      }
    }
    return url;
  }

  /// Resolves the Socket.IO `/live` namespace URL using only scheme+host+port,
  /// stripping any REST path prefix (such as `/api` in production Nginx/Plesk proxy).
  static String get socketNamespaceUrl {
    final uri = Uri.parse(baseUrl);
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portPart/live';
  }

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );
  final _random = Random();

  /// Tracks live connection health across HTTP & Realtime layers.
  final ValueNotifier<ConnectionHealth> connectionHealth =
      ValueNotifier<ConnectionHealth>(ConnectionHealth.online);

  /// Single Flight completer to prevent multiple concurrent refresh operations
  Completer<bool>? _refreshCompleter;

  /// Coalesces identical concurrent GET requests to prevent duplicate API bursts.
  final Map<String, Future<dynamic>> _inFlightGets = {};

  late final Dio dio = _createDio();

  String newIdempotencyKey() => _uuid.v4();

  void markReconnecting() {
    if (connectionHealth.value != ConnectionHealth.reconnecting) {
      connectionHealth.value = ConnectionHealth.reconnecting;
    }
  }

  void markOnline() {
    if (connectionHealth.value != ConnectionHealth.online) {
      connectionHealth.value = ConnectionHealth.online;
    }
  }

  void markStale() {
    if (connectionHealth.value == ConnectionHealth.online) {
      connectionHealth.value = ConnectionHealth.staleData;
    }
  }

  Dio _createDio() {
    if (kAppEnvironment == AppEnvironment.production && kDemoMode) {
      throw StateError('SECURITY ALERT: Running Production mode with DEMO=true is strictly prohibited!');
    }

    final defaultPolicy = RequestTimeoutPolicy.forClass(ApiRequestClass.read);
    final client = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: defaultPolicy.connectTimeout,
        receiveTimeout: defaultPolicy.receiveTimeout,
        sendTimeout: defaultPolicy.sendTimeout,
        headers: {
          'Accept': 'application/json',
          'X-Client-Platform': defaultTargetPlatform.name,
          'X-Client-Env': kAppEnvironment.name,
          'X-Client-App': appType,
        },
      ),
    );

    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final traceId =
              'tam-${DateTime.now().millisecondsSinceEpoch}-${_random.nextInt(999999).toString().padLeft(6, '0')}';
          options.headers['X-Correlation-Id'] = traceId;

          final jwt = await _storage.read(key: 'access_token');
          if (jwt != null && !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $jwt';
          }
          final devId = await getDeviceId();
          options.headers['X-Device-Id'] = devId;

          if (kDebugMode) {
            debugPrint('[HTTP] -> ${options.method} ${options.uri} [trace:$traceId]');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          markOnline();
          if (kDebugMode) {
            final traceId = response.requestOptions.headers['X-Correlation-Id'];
            debugPrint('[HTTP] <- ${response.statusCode} ${response.requestOptions.path} [trace:$traceId]');
          }
          handler.next(response);
        },
        onError: (e, handler) async {
          final traceId = e.requestOptions.headers['X-Correlation-Id'];
          if (kDebugMode) {
            debugPrint('[HTTP ERROR] ${e.response?.statusCode ?? 'NET'} ${e.requestOptions.path} [trace:$traceId]: ${e.message}');
          }

          if (e.type == DioExceptionType.connectionError) {
            connectionHealth.value = ConnectionHealth.offline;
          } else if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout) {
            connectionHealth.value = ConnectionHealth.reconnecting;
          } else if ((e.response?.statusCode ?? 0) >= 502) {
            connectionHealth.value = ConnectionHealth.serverUnavailable;
          }

          final path = e.requestOptions.path;
          final isUnrecoverableAuthRoute = path.endsWith('/refresh') ||
              path.endsWith('/login') ||
              path.contains('/otp/');

          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['retried'] != true &&
              !isUnrecoverableAuthRoute) {
            final refreshed = await _refreshSingleFlight();
            if (refreshed) {
              final opts = e.requestOptions..extra['retried'] = true;
              final newJwt = await _storage.read(key: 'access_token');
              if (newJwt != null) {
                opts.headers['Authorization'] = 'Bearer $newJwt';
              }
              try {
                return handler.resolve(await dio.fetch(opts));
              } catch (_) {}
            }
          }
          handler.next(e);
        },
      ),
    );

    return client;
  }

  /// Checks whether the server is reachable and responsive before proceeding.
  Future<bool> checkServerHealth() async {
    try {
      final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.health);
      final r = await dio.get('/health', options: policy.toOptions());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> accessToken() => _storage.read(key: 'access_token');

  Future<String?> deviceSessionId() async {
    final token = await accessToken();
    if (token == null) return null;
    final segments = token.split('.');
    if (segments.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      return payload is Map && payload['dsi'] is String ? payload['dsi'] as String : null;
    } catch (_) {
      return null;
    }
  }

  Future<int> nextLocationSequence() async {
    final sessionId = await deviceSessionId();
    if (sessionId == null) throw StateError('Device-bound session is required');
    final key = 'location_sequence_$sessionId';
    final previous = int.tryParse(await _storage.read(key: key) ?? '') ?? 0;
    final next = previous >= 2147483647 ? 1 : previous + 1;
    await _storage.write(key: key, value: '$next');
    return next;
  }

  Future<String> getDeviceId() async {
    var id = await _storage.read(key: 'device_id');
    if (id == null || id.isEmpty) {
      id = 'dev-${DateTime.now().millisecondsSinceEpoch}-${_random.nextInt(999999).toString().padLeft(6, '0')}';
      await _storage.write(key: 'device_id', value: id);
    }
    return id;
  }

  Future<bool> refreshNow() => _refreshSingleFlight();

  bool mustChangePassword = false;

  Future<bool> hasSession() async =>
      (await _storage.read(key: 'refresh_token')) != null;

  Future<String?> getCachedRole() => _storage.read(key: 'cached_user_role');

  Future<void> _saveTokens(Map<String, dynamic> t) async {
    await _storage.write(key: 'access_token', value: t['accessToken'] as String);
    await _storage.write(key: 'refresh_token', value: t['refreshToken'] as String);
  }

  Future<bool> _refreshSingleFlight() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();

    try {
      final rt = await _storage.read(key: 'refresh_token');
      if (rt == null) {
        _refreshCompleter!.complete(false);
        return false;
      }
      final devId = await getDeviceId();
      final r = await Dio(
        BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)),
      ).post('/v1/auth/refresh', data: {'refreshToken': rt, 'deviceId': devId});

      await _saveTokens(Map<String, dynamic>.from(r.data as Map));
      markOnline();
      _refreshCompleter!.complete(true);
      return true;
    } catch (e) {
      if (e is DioException && e.response != null) {
        final code = e.response!.statusCode;
        final data = e.response!.data;
        final err = data is Map ? (data['code'] ?? data['message']) : null;
        if (code == 401 &&
            (err == 'REFRESH_INVALID' ||
                err == 'REFRESH_EXPIRED' ||
                err == 'REFRESH_REUSED' ||
                err == 'SESSION_REVOKED' ||
                err == 'ACCOUNT_INACTIVE')) {
          await _storage.delete(key: 'access_token');
          await _storage.delete(key: 'refresh_token');
          await _storage.delete(key: 'cached_user_role');
        }
      }
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<String> login(String phone, String password) async {
    final devId = await getDeviceId();
    final t = await post('/v1/auth/login', {
      'phone': phone,
      'password': password,
      'deviceId': devId,
      'platform': defaultTargetPlatform.name,
    });
    await _saveTokens(t);
    mustChangePassword = t['mustChangePassword'] == true;
    final role = t['role'] as String;
    await _storage.write(key: 'cached_user_role', value: role);
    return role;
  }

  Future<void> changePassword(String current, String next) async {
    final t = await post('/v1/auth/change-password', {
      'currentPassword': current,
      'newPassword': next,
    });
    await _saveTokens(t);
    mustChangePassword = false;
  }

  Future<void> requestOtp(String phone) async =>
      post('/v1/auth/otp/request', {'phone': phone});

  Future<String> verifyOtp(String phone, String code) async {
    final devId = await getDeviceId();
    final t = await post('/v1/auth/otp/verify', {
      'phone': phone,
      'code': code,
      'deviceId': devId,
      'platform': defaultTargetPlatform.name,
    });
    await _saveTokens(t);
    final role = t['role'] as String;
    await _storage.write(key: 'cached_user_role', value: role);
    return role;
  }

  Future<String> register(String phone, String name, String password) async {
    final devId = await getDeviceId();
    final t = await post('/v1/auth/register', {
      'phone': phone,
      'displayName': name,
      'password': password,
      'deviceId': devId,
      'platform': defaultTargetPlatform.name,
    });
    await _saveTokens(t);
    final role = (t['role'] as String?) ?? 'PATIENT';
    await _storage.write(key: 'cached_user_role', value: role);
    return role;
  }

  Future<void> applyAsNurse({
    required String phone,
    required String name,
    required String governorateId,
    required String areaId,
    String? specialty,
    String? nationalId,
    required String docKind,
    required String licenseRef,
    required String expiresAt,
    required List<int> idBytes,
    required String idName,
    required List<int> docBytes,
    required String docName,
  }) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.upload);
    await dio.post(
      '/v1/auth/nurse-applications',
      data: FormData.fromMap({
        'phone': phone,
        'displayName': name,
        'governorateId': governorateId,
        'areaId': areaId,
        if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        if (nationalId != null && nationalId.isNotEmpty) 'nationalId': nationalId,
        'docKind': docKind,
        'licenseRef': licenseRef,
        'expiresAt': expiresAt,
        'acceptTerms': 'true',
        'idPhoto': MultipartFile.fromBytes(idBytes, filename: idName),
        'document': MultipartFile.fromBytes(docBytes, filename: docName),
      }),
      options: policy.toOptions(),
    );
  }

  Future<void> uploadNurseDocument({
    required List<int> bytes,
    required String filename,
    required String kind,
    String? licenseRef,
    String? expiresAt,
  }) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.upload);
    await dio.post(
      '/v1/nurse/me/documents',
      data: FormData.fromMap({
        'kind': kind,
        if (licenseRef != null) 'licenseRef': licenseRef,
        if (expiresAt != null) 'expiresAt': expiresAt,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      options: policy.toOptions(),
    );
  }

  Future<void> logout() async {
    final rt = await _storage.read(key: 'refresh_token');
    final devId = await getDeviceId();
    try {
      await dio.delete('/v1/devices', data: {'deviceId': devId, 'appType': appType});
    } catch (_) {}
    if (rt != null) {
      try {
        await post('/v1/auth/logout', {'refreshToken': rt, 'deviceId': devId});
      } catch (_) {}
    }
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'cached_user_role');
    mustChangePassword = false;
  }

  Future<void> saveAccessToken(String value) =>
      _storage.write(key: 'access_token', value: value);

  Future<void> signOut() => logout();

  /// Deduplicated GET with optional cancellation token and controlled retry on transient read failures.
  Future<dynamic> _getRaw(
    String path, {
    CancelToken? cancelToken,
    bool deduplicate = true,
  }) async {
    if (cancelToken != null || !deduplicate) {
      return _executeGetWithRetry(path, cancelToken: cancelToken);
    }
    final existing = _inFlightGets[path];
    if (existing != null) return existing;

    final future = _executeGetWithRetry(path).whenComplete(() {
      _inFlightGets.remove(path);
    });
    _inFlightGets[path] = future;
    return future;
  }

  Future<dynamic> _executeGetWithRetry(String path, {CancelToken? cancelToken}) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.read);
    try {
      final res = await dio.get(path, cancelToken: cancelToken, options: policy.toOptions());
      return res.data;
    } on DioException catch (e) {
      // Safe retry ONCE for read-only GET requests on timeout or 502/503/504
      final status = e.response?.statusCode ?? 0;
      final retryable = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          status == 502 ||
          status == 503 ||
          status == 504;
      if (retryable && !(cancelToken?.isCancelled ?? false)) {
        await Future<void>.delayed(Duration(milliseconds: 250 + _random.nextInt(300)));
        final res = await dio.get(path, cancelToken: cancelToken, options: policy.toOptions());
        return res.data;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMap(String path, {CancelToken? cancelToken}) async =>
      Map<String, dynamic>.from((await _getRaw(path, cancelToken: cancelToken)) as Map);

  Future<List<dynamic>> getList(String path, {CancelToken? cancelToken}) async =>
      List<dynamic>.from((await _getRaw(path, cancelToken: cancelToken)) as List);

  Future<ApiResult<Map<String, dynamic>>> safeGetMap(String path, {CancelToken? cancelToken}) async {
    try {
      return ApiOk(await getMap(path, cancelToken: cancelToken));
    } catch (e) {
      return ApiErr(mapApiFailure(e));
    }
  }

  Future<ApiResult<List<dynamic>>> safeGetList(String path, {CancelToken? cancelToken}) async {
    try {
      return ApiOk(await getList(path, cancelToken: cancelToken));
    } catch (e) {
      return ApiErr(mapApiFailure(e));
    }
  }

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  ]) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.mutation);
    final res = await dio.post(
      path,
      data: body,
      cancelToken: cancelToken,
      options: policy.toOptions(base: Options(headers: headers)),
    );
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    return const {};
  }

  Future<ApiResult<Map<String, dynamic>>> safePost(
    String path, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  ]) async {
    try {
      return ApiOk(await post(path, body, headers, cancelToken));
    } catch (e) {
      return ApiErr(mapApiFailure(e));
    }
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
  }) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.mutation);
    final res = await dio.put(
      path,
      data: body,
      cancelToken: cancelToken,
      options: policy.toOptions(),
    );
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    return const {};
  }

  Future<Map<String, dynamic>> delete(
    String path, [
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  ]) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.mutation);
    final res = await dio.delete(
      path,
      data: body,
      cancelToken: cancelToken,
      options: policy.toOptions(),
    );
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    return const {};
  }

  // =========================================================================
  // Smart Booking & Open Marketplace Endpoints
  // =========================================================================

  Future<List<dynamic>> getMarketplaceRequests({double? maxDistanceKm, CancelToken? cancelToken}) async {
    final res = await _getRaw(
      maxDistanceKm != null
          ? '/v1/marketplace/requests?maxDistanceKm=$maxDistanceKm'
          : '/v1/marketplace/requests',
      cancelToken: cancelToken,
    );
    if (res is List) return List<dynamic>.from(res);
    if (res is Map) {
      final list = res['requests'] ?? res['items'];
      if (list is List) return List<dynamic>.from(list);
    }
    return const [];
  }

  Future<void> uploadClinicalEvidence(
    String requestId,
    String type,
    List<int> bytes,
    String filename,
  ) async {
    final policy = RequestTimeoutPolicy.forClass(ApiRequestClass.upload);
    await dio.post(
      '/v1/requests/$requestId/clinical-evidence',
      data: FormData.fromMap({
        'evidenceType': type,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      options: policy.toOptions(),
    );
  }

  Future<Map<String, dynamic>> getMarketplaceRequest(String requestId) =>
      getMap('/v1/marketplace/requests/$requestId');

  Future<Map<String, dynamic>> submitProposal(
    String requestId, {
    int? estimatedMinutes,
    String? specificTime,
    String? note,
  }) =>
      post('/v1/marketplace/requests/$requestId/proposals', {
        if (estimatedMinutes != null) 'arrivalMinutes': estimatedMinutes,
        if (specificTime != null) 'proposedArrivalAt': specificTime,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<Map<String, dynamic>> withdrawProposal(String proposalId, {String? reason}) =>
      post('/v1/marketplace/proposals/$proposalId/withdraw', {
        if (reason != null) 'withdrawalReason': reason,
      });

  Future<List<dynamic>> getMyProposals() => getList('/v1/marketplace/proposals/mine');

  Future<List<dynamic>> getRequestProposals(String requestId) =>
      getList('/v1/requests/$requestId/proposals');

  Future<Map<String, dynamic>> acceptProposal(String requestId, String proposalId) =>
      post(
        '/v1/requests/$requestId/proposals/$proposalId/accept',
        {},
        {'Idempotency-Key': newIdempotencyKey()},
      );

  Future<Map<String, dynamic>> declineProposal(String requestId, String proposalId, {String? reason}) =>
      post('/v1/requests/$requestId/proposals/$proposalId/decline', {
        if (reason != null) 'declineReason': reason,
      });

  Future<Map<String, dynamic>> switchRequestToOpenMarketplace(
    String requestId, {
    int durationMinutes = 60,
  }) =>
      post('/v1/requests/$requestId/booking-mode', {
        'bookingMode': 'OPEN',
        'openDurationMinutes': durationMinutes,
      });

  Future<Map<String, dynamic>> retryInstantDispatch(String requestId) =>
      post('/v1/requests/$requestId/retry-dispatch');

  Future<Map<String, dynamic>> switchRequestToScheduled(
    String requestId, {
    required DateTime scheduledStartAt,
    DateTime? scheduledEndAt,
  }) =>
      post('/v1/requests/$requestId/booking-mode', {
        'bookingMode': 'SCHEDULED',
        'scheduledAt': scheduledStartAt.toUtc().toIso8601String(),
        if (scheduledEndAt != null) 'scheduledEndAt': scheduledEndAt.toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> extendWaitWindow(
    String requestId, {
    int additionalMinutes = 60,
  }) =>
      post('/v1/requests/$requestId/open/extend', {
        'additionalMinutes': additionalMinutes,
      });
}
