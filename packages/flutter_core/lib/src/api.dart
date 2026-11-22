import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Demo mode runs the apps on built-in sample data (no backend needed).
/// Disable with `--dart-define=DEMO=false` to use the real API.
const bool kDemoMode = bool.fromEnvironment('DEMO', defaultValue: true);

/// Interim login is phone + password (accounts are created by an admin).
/// Switch to `--dart-define=AUTH_MODE=otp` once an SMS gateway exists.
const String kAuthMode = String.fromEnvironment(
  'AUTH_MODE',
  defaultValue: 'password',
);

/// Tokens come from an auth flow that is not implemented yet (see docs).
class TamreedyApi {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
  final _storage = const FlutterSecureStorage();
  late final Dio dio =
      Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 12),
          ),
        )
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final jwt = await _storage.read(key: 'access_token');
              if (jwt != null) options.headers['Authorization'] = 'Bearer $jwt';
              handler.next(options);
            },
            onError: (e, handler) async {
              // One silent refresh on 401, then replay the original request.
              if (e.response?.statusCode == 401 &&
                  e.requestOptions.extra['retried'] != true &&
                  !e.requestOptions.path.startsWith('/v1/auth/')) {
                if (await _refresh()) {
                  final opts = e.requestOptions..extra['retried'] = true;
                  try {
                    return handler.resolve(await dio.fetch(opts));
                  } catch (_) {}
                }
              }
              handler.next(e);
            },
          ),
        );

  Future<String?> accessToken() => _storage.read(key: 'access_token');

  /// Rotates the refresh token now (used by the realtime channel on reconnect).
  Future<bool> refreshNow() => _refresh();

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

  Future<bool> _refresh() async {
    final rt = await _storage.read(key: 'refresh_token');
    if (rt == null) return false;
    try {
      final r = await Dio(
        BaseOptions(baseUrl: baseUrl),
      ).post('/v1/auth/refresh', data: {'refreshToken': rt});
      await _saveTokens(Map<String, dynamic>.from(r.data as Map));
      return true;
    } catch (_) {
      await _storage.deleteAll();
      return false;
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
