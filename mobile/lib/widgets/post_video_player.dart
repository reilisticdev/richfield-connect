// mobile/lib/widgets/post_video_player.dart
//
// The media area of a video post. Shows the poster frame (posts.thumbnail_path)
// with a play button; tapping swaps in a real video_player bound to the
// post's public URL. Nothing is buffered until the member asks for it, so a
// feed of twenty reels doesn't open twenty network streams on scroll.
//
// Tall (9:16) phone recordings are letterboxed inside a 4:5 box so one
// vertical clip can't take over the whole screen in the list.

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../main.dart' show AppColors, AppText, Pill;

class PostVideoPlayer extends StatefulWidget {
  const PostVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.label,
  });

  final String videoUrl;
  final String? thumbnailUrl;

  /// Small pill in the top-left corner ("Video post"). Optional.
  final String? label;

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  /// Narrowest box a clip is shown in: a 9:16 video is centred in this.
  static const double _minAspect = 4 / 5;

  /// Poster-frame box before playback starts.
  static const double _posterAspect = 16 / 10;

  VideoPlayerController? _controller;
  bool _initialising = false;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_initialising || _controller != null) return;
    setState(() {
      _initialising = true;
      _error = null;
    });

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      setState(() {
        _controller = controller;
        _initialising = false;
      });
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = 'This video couldn\'t be loaded. Check your connection and tap to retry.';
      });
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return _player(controller);
    }
    return _poster();
  }

  Widget _player(VideoPlayerController controller) {
    final videoAspect = controller.value.aspectRatio <= 0 ? _posterAspect : controller.value.aspectRatio;
    final boxAspect = videoAspect < _minAspect ? _minAspect : videoAspect;

    return GestureDetector(
      onTap: _togglePlay,
      child: AspectRatio(
        aspectRatio: boxAspect,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: videoAspect,
                  child: VideoPlayer(controller),
                ),
              ),
              // Pause badge only while paused — a play icon over a playing
              // video is what the old mock card did.
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (_, value, __) =>
                    value.isPlaying ? const SizedBox.shrink() : const Center(child: _PlayBadge()),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                  colors: VideoProgressColors(
                    playedColor: AppColors.primary,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster() {
    final thumbnailUrl = widget.thumbnailUrl;
    return GestureDetector(
      onTap: _start,
      child: AspectRatio(
        aspectRatio: _posterAspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
              Image.network(
                thumbnailUrl,
                fit: BoxFit.cover,
                // A dead CDN link must not blow up the whole feed list.
                errorBuilder: (_, __, ___) => const _PosterFallback(),
              )
            else
              const _PosterFallback(),
            Container(color: Colors.black26),
            Center(
              child: _initialising
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                    )
                  : const _PlayBadge(),
            ),
            if (widget.label != null)
              Positioned(
                top: 8,
                left: 8,
                child: Pill(
                  text: widget.label!,
                  background: Colors.black.withValues(alpha: 0.55),
                  foreground: Colors.white,
                  icon: Icons.videocam_outlined,
                ),
              ),
            if (_error != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(_error!, style: AppText.bodySm(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2B2B2B), Color(0xFF3B2A2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white24, size: 64),
      ),
    );
  }
}
