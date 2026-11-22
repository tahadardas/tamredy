import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
      return 'http://85.215.243.237:18300';
    case AppEnvironment.staging:
      return 'https://staging-api.tamreedy.com';
    case AppEnvironment.dev:
      if (kIsWeb) return 'http://localhost:3000';
      return defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:3000'
          : 'http://localhost:3000';
  }
}

/// Interim login is phone + password (accounts are created by an admin).
/// Switch to `--dart-define=AUTH_MODE=otp` once an SMS gateway exists.
const String kAuthMode = String.fromEnvironment(
  'AUTH_MODE',
  defaultValue: 'password',
);

/// Centralized API client for all Tamreedy mobile apps.
class TamreedyApi {
  static const String _customBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    String url = _customBaseUrl.isNotEmpty ? _customBaseUrl : defaultBaseUrlForEnv(kAppEnvironment);
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  final _storage = const FlutterSecureStorage();
  final _random = Random();

  /// Single Flight completer to prevent multiple concurrent refresh operations
  Completer<bool>? _refreshCompleter;

  late final Dio dio = _createDio();

  Dio _createDio() {
    // Safety check: Prevent running production build with DEMO=true
    if (kAppEnvironment == AppEnvironment.production && kDemoMode) {
      throw StateError('SECURITY ALERT: Running Production mode with DEMO=true is strictly prohibited!');
    }

    final client = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          'X-Client-Platform': defaultTargetPlatform.name,
          'X-Client-Env': kAppEnvironment.name,
        },
      ),
    );

    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Generate unique correlation ID for end-to-end tracing
          final traceId = 'tam-${DateTime.now().millisecondsSinceEpoch}-${_random.nextInt(999999).toString().padLeft(6, '0')}';
          options.headers['X-Correlation-Id'] = traceId;

          // Attach JWT access token if available
          final jwt = await _storage.read(key: 'access_token');
          if (jwt != null && !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $jwt';
          }

          if (kDebugMode) {
            debugPrint('[HTTP] -> ${options.method} ${options.uri} [trace:$traceId]');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
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

          // Single-flight silent refresh on 401 Unauthorized
          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['retried'] != true &&
              !e.requestOptions.path.startsWith('/v1/auth/')) {
            final refreshed = await _refreshSingleFlight();
            if (refreshed) {
              final opts = e.requestOptions..extra['retried'] = true;
              // Update Authorization header with the newly acquired token
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
      final r = await dio.get('/health', options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> accessToken() => _storage.read(key: 'access_token');

  /// Rotates the refresh token now (used by the realtime channel on reconnect).
  Future<bool> refreshNow() => _refreshSingleFlight();

  /// True right after a login with the initial password; the app must show the change-password screen.
  bool mustChangePassword = false;

  Future<bool> hasSession() async =>
      (await _storage.read(key: 'refresh_token')) != null;

  Future<void> _saveTokens(Map<String, dynamic> t) async {
    await _storage.write(
      key: 'access_token',
      value: t['accessToken'] as String,
    );
    await _storage.write(
      key: 'refresh_token',
      value: t['refreshToken'] as String,
    );
  }

  /// Single Flight Refresh: prevents multiple simultaneous refresh calls when parallel requests receive 401.
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
      final r = await Dio(
        BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)),
      ).post('/v1/auth/refresh', data: {'refreshToken': rt});

      await _saveTokens(Map<String, dynamic>.from(r.data as Map));
      _refreshCompleter!.complete(true);
      return true;
    } catch (e) {
      // Security: Only clear session if the server definitively rejected the token (400, 401, 403).
      // DO NOT clear user session on transient network timeouts / socket errors!
      if (e is DioException && e.response != null) {
        final code = e.response!.statusCode;
        if (code == 400 || code == 401 || code == 403) {
          await _storage.deleteAll();
        }
      }
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Interim password login; returns the account role.
  Future<String> login(String phone, String password) async {
    final t = await post('/v1/auth/login', {
      'phone': phone,
      'password': password,
    });
    await _saveTokens(t);
    mustChangePassword = t['mustChangePassword'] == true;
    return t['role'] as String;
  }

  /// Replaces the password (ends other sessions) and keeps this device signed in.
  Future<void> changePassword(String current, String next) async {
    final t = await post('/v1/auth/change-password', {
      'currentPassword': current,
      'newPassword': next,
    });
    await _saveTokens(t);
    mustChangePassword = false;
  }

  /// Step 1 of login: the server sends an OTP by SMS.
  Future<void> requestOtp(String phone) async =>
      post('/v1/auth/otp/request', {'phone': phone});

  /// Step 2: exchange the code for tokens; returns the account role.
  Future<String> verifyOtp(String phone, String code) async {
    final t = await post('/v1/auth/otp/verify', {'phone': phone, 'code': code});
    await _saveTokens(t);
    return t['role'] as String;
  }

  /// Patient self-registration. Signs the new account in and returns its role.
  Future<String> register(String phone, String name, String password) async {
    final t = await post('/v1/auth/register', {
      'phone': phone,
      'displayName': name,
      'password': password,
    });
    await _saveTokens(t);
    return (t['role'] as String?) ?? 'PATIENT';
  }

  /// Nurse join application (no account is created until staff approve it).
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
      options: Options(sendTimeout: const Duration(seconds: 90)),
    );
  }

  /// Nurse onboarding: uploads a licence/ID/degree/photo (stored encrypted by the server).
  Future<void> uploadNurseDocument({
    required List<int> bytes,
    required String filename,
    required String kind,
    String? licenseRef,
    String? expiresAt,
  }) async {
    await dio.post(
      '/v1/nurse/me/documents',
      data: FormData.fromMap({
        'kind': kind,
        if (licenseRef != null) 'licenseRef': licenseRef,
        if (expiresAt != null) 'expiresAt': expiresAt,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      options: Options(sendTimeout: const Duration(seconds: 60)),
    );
  }

  Future<void> logout() async {
    final rt = await _storage.read(key: 'refresh_token');
    if (rt != null) {
      try {
        await post('/v1/auth/logout', {'refreshToken': rt});
      } catch (_) {}
    }
    await _storage.deleteAll();
  }

  Future<void> saveAccessToken(String value) =>
      _storage.write(key: 'access_token', value: value);

  Future<void> signOut() => _storage.deleteAll();

  Future<Map<String, dynamic>> getMap(String path) async =>
      Map<String, dynamic>.from((await dio.get(path)).data as Map);

  Future<List<dynamic>> getList(String path) async =>
      List<dynamic>.from((await dio.get(path)).data as List);

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  ]) async => Map<String, dynamic>.from(
    (await dio.post(
          path,
          data: body,
          options: Options(headers: headers),
        )).data
        as Map,
  );

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async =>
      Map<String, dynamic>.from((await dio.put(path, data: body)).data as Map);
}
