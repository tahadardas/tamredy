import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

enum ClinicalUploadStatus { pending, uploading, failed }

/// Metadata and encryption keys live in platform secure storage. Only AES-GCM
/// ciphertext is written to the application's private support directory.
class PendingClinicalUploadStore {
  final TamreedyApi api;
  final Future<Directory> Function() supportDirectory;
  final AesGcm _cipher = AesGcm.with256bits();

  PendingClinicalUploadStore({
    required this.api,
    Future<Directory> Function()? supportDirectory,
  }) : supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  String _metadataKey(String owner) => 'pending_clinical_upload_$owner';
  String _secretKey(String operationId) => 'clinical_upload_key_$operationId';

  Future<Map<String, dynamic>?> metadata(String owner) async {
    final raw = await api.readLocal(_metadataKey(owner));
    if (raw == null) return null;
    final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (value['ownerUserId'] != owner) {
      throw StateError('Upload owner mismatch');
    }
    return value;
  }

  Future<File> _file(String reference) async {
    // References are generated locally; never allow a metadata value to select
    // a path outside private storage.
    if (!RegExp(r'^[a-zA-Z0-9-]+\.enc$').hasMatch(reference)) {
      throw StateError('Invalid encrypted clinical file reference');
    }
    final directory = Directory(
      '${(await supportDirectory()).path}/clinical_uploads',
    );
    await directory.create(recursive: true);
    return File('${directory.path}/$reference');
  }

  Future<Map<String, dynamic>> prepare({
    required String ownerUserId,
    required String operationId,
    required String evidenceType,
    required String filename,
    required Uint8List bytes,
  }) async {
    if (ownerUserId.isEmpty ||
        bytes.isEmpty ||
        bytes.length > 8 * 1024 * 1024) {
      throw StateError(
        'Authenticated clinical upload of at most 8 MiB required',
      );
    }
    final digest = await Sha256().hash(bytes);
    final existing = await metadata(ownerUserId);
    if (existing != null) {
      if (existing['operationId'] != operationId) {
        throw StateError('A clinical upload still needs reconciliation');
      }
      if (existing['contentHash'] != base64Encode(digest.bytes) ||
          existing['evidenceType'] != evidenceType) {
        throw StateError('Cannot replace evidence for an unresolved request');
      }
      return existing;
    }
    final secretKey = await _cipher.newSecretKey();
    final box = await _cipher.encrypt(bytes, secretKey: secretKey);
    final reference = '$operationId.enc';
    final file = await _file(reference);
    // Persist the key before the file; metadata is the final commit marker.
    await api.writeLocal(
      _secretKey(operationId),
      base64Encode(await secretKey.extractBytes()),
    );
    await file.writeAsBytes(box.concatenation(), flush: true);
    final value = <String, dynamic>{
      'operationId': operationId,
      'ownerUserId': ownerUserId,
      'requestId': null,
      'evidenceType': evidenceType,
      'filename': filename,
      'encryptedFileReference': reference,
      'contentHash': base64Encode(digest.bytes),
      'uploadStatus': ClinicalUploadStatus.pending.name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'retryCount': 0,
    };
    await api.writeLocal(_metadataKey(ownerUserId), jsonEncode(value));
    return value;
  }

  Future<void> bindRequest(String owner, String requestId) async {
    final value = await metadata(owner);
    if (value == null) return;
    final previous = value['requestId'];
    if (previous != null && previous != requestId) {
      throw StateError('Upload request mismatch');
    }
    value['requestId'] = requestId;
    await api.writeLocal(_metadataKey(owner), jsonEncode(value));
  }

  Future<Uint8List> readBytes(String owner) async {
    final value = await metadata(owner);
    if (value == null) throw StateError('Clinical upload missing');
    final key = await api.readLocal(_secretKey(value['operationId'] as String));
    if (key == null) throw StateError('Clinical upload encryption key missing');
    final packed = await (await _file(
      value['encryptedFileReference'] as String,
    )).readAsBytes();
    final box = SecretBox.fromConcatenation(
      packed,
      nonceLength: 12,
      macLength: 16,
    );
    final bytes = await _cipher.decrypt(
      box,
      secretKey: SecretKey(base64Decode(key)),
    );
    final digest = base64Encode((await Sha256().hash(bytes)).bytes);
    if (digest != value['contentHash']) {
      throw StateError('Clinical upload integrity check failed');
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> markAttempt(String owner, {required bool failed}) async {
    final value = await metadata(owner);
    if (value == null) throw StateError('Clinical upload missing');
    value['uploadStatus'] = failed
        ? ClinicalUploadStatus.failed.name
        : ClinicalUploadStatus.uploading.name;
    if (!failed) value['retryCount'] = (value['retryCount'] as int) + 1;
    await api.writeLocal(_metadataKey(owner), jsonEncode(value));
  }

  /// Only called after the server has confirmed a successful upload.
  Future<void> complete(String owner) async {
    final value = await metadata(owner);
    if (value == null) return;
    final file = await _file(value['encryptedFileReference'] as String);
    if (await file.exists()) await file.delete();
    await api.writeLocal(_secretKey(value['operationId'] as String), null);
    await api.writeLocal(_metadataKey(owner), null);
  }
}
