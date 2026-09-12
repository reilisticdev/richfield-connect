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

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';

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

  String get readableSize => readableBytes(sizeBytes);
}

/// A short-form video ready to post: already transcoded on-device, with the
/// poster frame that will sit next to it in the bucket. Both files live in
/// the app's cache until the upload finishes (see MediaService.clearVideoCache).
class PickedVideo {
  PickedVideo({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.originalSizeBytes,
    required this.thumbnail,
    required this.duration,
    this.width,
    this.height,
  });

  /// The compressed MP4.
  final File file;
  final String fileName;
  final int sizeBytes;

  /// What the user picked, before compression — shown next to the result so
  /// the saving is visible rather than a claim.
  final int originalSizeBytes;

  /// JPEG poster frame extracted from the compressed file.
  final File thumbnail;
  final Duration duration;
  final int? width;
  final int? height;

  String get readableSize => readableBytes(sizeBytes);
  String get readableOriginalSize => readableBytes(originalSizeBytes);

  /// "0:42" style, for the preview card and the feed badge.
  String get readableDuration {
    final total = duration.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// Compression ratio as a percentage saved, or null when nothing was.
  int? get percentSaved {
    if (originalSizeBytes <= 0 || sizeBytes >= originalSizeBytes) return null;
    return (100 - (sizeBytes / originalSizeBytes * 100)).round();
  }
}

String readableBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

  // --- short-form video ----------------------------------------------

  /// Short-form limits. 60 s is the "short-form" ceiling the rubric
  /// describes; 25 MB after compression keeps every upload well under the
  /// project's storage object cap and under a minute on campus wifi.
  static const int maxVideoSeconds = 60;
  static const int maxVideoBytes = 25 * 1024 * 1024;

  /// Refused before compression even starts. A 4K clip can be 300 MB+, and
  /// transcoding that on a mid-range phone takes minutes nobody asked for.
  static const int maxSourceVideoBytes = 250 * 1024 * 1024;

  static const _allowedVideoExtensions = {'mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv'};

  /// Records a clip with the camera or picks one from the gallery. Returns
  /// the raw file — call [compressVideo] before showing a size or uploading.
  ///
  /// Null means the user backed out. Not an error.
  ///
  /// `maxDuration` is enforced by the system camera when recording; gallery
  /// picks are unlimited at this point, so the length is checked again after
  /// transcoding in [compressVideo].
  Future<PickedMedia?> pickVideo({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: maxVideoSeconds),
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return null;

    final file = File(picked.path);
    final size = await file.length();

    final ext = _extensionOf(picked.name);
    if (!_allowedVideoExtensions.contains(ext)) {
      throw MediaException('That file type isn\'t supported. Pick an MP4 or MOV video.');
    }
    if (size > maxSourceVideoBytes) {
      throw MediaException(
        'That video is ${readableBytes(size)}. '
        'Please choose one under ${readableBytes(maxSourceVideoBytes)}.',
      );
    }

    return PickedMedia(file: file, fileName: picked.name, sizeBytes: size);
  }

  /// Transcodes a picked video to a 720p-class H.264 MP4 and extracts a
  /// poster frame — both on the device, before a single byte is uploaded.
  /// This is what makes a 60 MB phone recording a 3–6 MB post.
  ///
  /// [onProgress] receives 0–100 while the encoder runs. Throws
  /// [MediaException] with a user-facing message when the result is still
  /// too long or too large.
  Future<PickedVideo> compressVideo(
    PickedMedia source, {
    void Function(double percent)? onProgress,
  }) async {
    Subscription? progress;
    if (onProgress != null) {
      progress = VideoCompress.compressProgress$.subscribe(onProgress);
    }
    try {
      final info = await VideoCompress.compressVideo(
        source.file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final out = info?.file;
      if (info == null || out == null || info.isCancel == true) {
        throw MediaException('Couldn\'t process that video. Try a different clip.');
      }

      // MediaInfo.duration is milliseconds.
      final duration = Duration(milliseconds: (info.duration ?? 0).round());
      if (duration.inSeconds > maxVideoSeconds + 1) {
        throw MediaException(
          'Videos can be up to $maxVideoSeconds seconds. '
          'That one is ${duration.inSeconds} seconds — trim it and try again.',
        );
      }

      final size = await out.length();
      if (size > maxVideoBytes) {
        throw MediaException(
          'Even after compression that video is ${readableBytes(size)}. '
          'The limit is ${readableBytes(maxVideoBytes)} — try a shorter clip.',
        );
      }

      final thumbnail = await VideoCompress.getFileThumbnail(
        out.path,
        quality: 70,
        position: -1, // encoder picks a representative frame
      );

      final stem = _sanitize(source.fileName).replaceAll(RegExp(r'\.[a-z0-9]+$'), '');
      return PickedVideo(
        file: out,
        fileName: '$stem.mp4',
        sizeBytes: size,
        originalSizeBytes: source.sizeBytes,
        thumbnail: thumbnail,
        duration: duration,
        width: info.width,
        height: info.height,
      );
    } finally {
      progress?.unsubscribe();
    }
  }

  /// Stops an in-flight [compressVideo]; safe to call when none is running.
  Future<void> cancelCompression() => VideoCompress.cancelCompression();

  /// Drops the transcoded files and thumbnails video_compress keeps in the
  /// app cache. Called after a successful post; a failed one keeps them so
  /// a retry doesn't re-encode.
  Future<void> clearVideoCache() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {
      // Cache housekeeping must never surface as an error.
    }
  }

  /// Uploads the compressed video and its poster frame side by side and
  /// returns the two storage paths for `posts.video_path` and
  /// `posts.thumbnail_path`. Same `<uid>/<stamp>_…` key convention as
  /// images, so the post-media RLS (owner folder) applies unchanged.
  ///
  /// If the thumbnail upload fails the video object is removed again: a
  /// post with a video and no poster would render as a blank card.
  Future<({String videoPath, String thumbnailPath})> uploadPostVideo({
    required String userId,
    required PickedVideo video,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final videoPath = '$userId/${stamp}_video.mp4';
    final thumbnailPath = '$userId/${stamp}_thumb.jpg';

    final bucket = _client.storage.from(postMediaBucket);
    await bucket.upload(
      videoPath,
      video.file,
      fileOptions: const FileOptions(upsert: true, contentType: 'video/mp4'),
    );
    try {
      await bucket.upload(
        thumbnailPath,
        video.thumbnail,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
      );
    } catch (_) {
      try {
        await bucket.remove([videoPath]);
      } catch (_) {
        // Best effort; the original failure is the one worth reporting.
      }
      rethrow;
    }
    return (videoPath: videoPath, thumbnailPath: thumbnailPath);
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
  String postVideoUrl(String path) => publicUrl(postMediaBucket, path);
  String avatarUrl(String path) => publicUrl(avatarsBucket, path, bustCache: true);

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
