// mobile/lib/services/media_service.dart
//
// Device gallery -> Supabase Storage. This file is the piece that did not
// exist before: PostComposerScreen's "Add PNG image" button was
// `onPressed: () => setState(() => _hasAttachment = true)`, i.e. it flipped
// a bool and rendered the hardcoded caption 'portfolio-image.png'. No
// picker plugin was in pubspec.yaml, so no code path could reach device
// storage at all.
//
// The storage path convention here is NOT cosmetic. Both buckets' RLS
// policies are:
//
//     (auth.uid())::text = (storage.foldername(name))[1]
//
// so every object key MUST start with "<the uploader's uid>/". Uploading to
// a bare filename like "photo.jpg" is rejected with a 403 that surfaces to
// Flutter as a generic StorageException with no hint about the cause.

import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown for problems we can explain to the user in plain language
/// (too large, unsupported type). Real network/permission failures stay as
/// StorageException so AuthErrorMapper can surface the server's message.
class MediaException implements Exception {
  MediaException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PickedMedia {
  PickedMedia({required this.file, required this.fileName, required this.sizeBytes});

  final File file;
  final String fileName;
  final int sizeBytes;

  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class MediaService {
  MediaService(this._client);

  final SupabaseClient _client;
  final ImagePicker _picker = ImagePicker();

  static const String avatarsBucket = 'avatars';
  static const String postMediaBucket = 'post-media';

  /// Storage rejects the upload outright above the project limit; catching
  /// it here gives a message a user can act on instead of a 413.
  static const int maxImageBytes = 5 * 1024 * 1024;

  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'};

  /// Opens the device gallery (or camera) and returns the chosen file.
  ///
  /// Returns null when the user backs out of the picker. That is a normal
  /// outcome, not an error — callers must not show a failure message for it.
  ///
  /// maxWidth/imageQuality make image_picker re-encode before the file ever
  /// reaches us, which is what keeps a 12 MP phone photo from becoming a
  /// multi-megabyte upload on conference wifi.
  Future<PickedMedia?> pickImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final file = File(picked.path);
    final size = await file.length();

    final ext = _extensionOf(picked.name);
    if (!_allowedExtensions.contains(ext)) {
      throw MediaException('That file type isn\'t supported. Pick a JPG, PNG or WebP image.');
    }
    if (size > maxImageBytes) {
      throw MediaException(
        'That image is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB. '
        'Please choose one under 5 MB.',
      );
    }

    return PickedMedia(file: file, fileName: picked.name, sizeBytes: size);
  }

  /// Uploads a post attachment and returns the storage path to persist in
  /// `posts.image_path`. We store the path, not the public URL, so the
  /// bucket/CDN origin can change without rewriting rows.
  Future<String> uploadPostImage({
    required String userId,
    required PickedMedia media,
  }) async {
    final path = _objectKey(userId: userId, fileName: media.fileName);
    await _client.storage.from(postMediaBucket).upload(
          path,
          media.file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeOf(media.fileName),
          ),
        );
    return path;
  }

  /// Uploads a profile picture and returns the path for `profiles.avatar_path`.
  ///
  /// Deliberately a stable key per user ("<uid>/avatar.<ext>") + upsert, so
  /// changing your picture replaces the old object instead of leaking a new
  /// orphaned file into the bucket on every edit. This is exactly why
  /// migration 024 adds an UPDATE policy to storage.objects — with only the
  /// original INSERT policy, the second upload 403s.
  Future<String> uploadAvatar({
    required String userId,
    required PickedMedia media,
  }) async {
    final path = '$userId/avatar.${_extensionOf(media.fileName)}';
    await _client.storage.from(avatarsBucket).upload(
          path,
          media.file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeOf(media.fileName),
          ),
        );
    return path;
  }

  /// Both buckets are public, so this is a plain CDN URL with no signing.
  ///
  /// The cache-buster matters for avatars: the object key is stable, so
  /// without it Flutter's image cache keeps showing the previous picture
  /// after an edit even though the upload succeeded.
  String publicUrl(String bucket, String path, {bool bustCache = false}) {
    final url = _client.storage.from(bucket).getPublicUrl(path);
    if (!bustCache) return url;
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  String postImageUrl(String path) => publicUrl(postMediaBucket, path);
  String avatarUrl(String path) => publicUrl(avatarsBucket, path, bustCache: true);

  // --- CV (private evidence) --------------------------------------------

  /// Private bucket (migration 038): owner + administrators only, PDF only.
  static const String cvsBucket = 'cvs';
  static const int maxCvBytes = 5 * 1024 * 1024;

  /// One stable key per member. A re-import replaces the object (the bucket
  /// has an UPDATE policy for exactly this) instead of stacking copies.
  static String cvObjectKey(String userId) => '$userId/cv.pdf';

  /// Stores the CV PDF and returns the path for `profiles.cv_path`.
  Future<String> uploadCv({required String userId, required Uint8List bytes}) async {
    if (bytes.length > maxCvBytes) {
      throw MediaException(
        'That PDF is ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB. '
        'Choose one under ${maxCvBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final path = cvObjectKey(userId);
    await _client.storage.from(cvsBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'),
        );
    return path;
  }

  /// The bucket is private, so every open mints a short-lived signed URL;
  /// nothing durable is ever handed out or stored.
  Future<String> cvSignedUrl(String path) =>
      _client.storage.from(cvsBucket).createSignedUrl(path, 600);

  Future<void> removeCv(String path) async {
    await _client.storage.from(cvsBucket).remove([path]);
  }

  /// Copies the member's current CV to a per-application key so the
  /// business sees exactly what was submitted, even after the member
  /// replaces or removes the CV on their profile (migration 039). Still
  /// under the member's own folder, so the owner policies and the
  /// account-deletion sweep cover it. Returns the new object key.
  Future<String> snapshotCvForApplication({
    required String userId,
    required String sourcePath,
  }) async {
    final target = '$userId/applications/${DateTime.now().millisecondsSinceEpoch}.pdf';
    await _client.storage.from(cvsBucket).copy(sourcePath, target);
    return target;
  }

  // --- helpers -------------------------------------------------------

  String _objectKey({required String userId, required String fileName}) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '$userId/${stamp}_${_sanitize(fileName)}';
  }

  /// Storage keys allow a limited character set; spaces and non-ASCII in a
  /// gallery filename ("IMG 2024 (1).JPG") otherwise fail the upload.
  String _sanitize(String fileName) {
    final lower = fileName.toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'upload' : cleaned;
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return 'jpg';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Supabase Storage defaults new objects to application/octet-stream,
  /// which makes browsers download rather than render them — so the admin
  /// web view of a post image would prompt a file save instead of showing it.
  String _contentTypeOf(String fileName) {
    switch (_extensionOf(fileName)) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
