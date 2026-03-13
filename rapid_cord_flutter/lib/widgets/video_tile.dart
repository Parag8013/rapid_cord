import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../theme/app_colors.dart';

/// Renders a single video tile with participant name overlay.
///
/// Supports:
/// - Live `RTCVideoRenderer` display
/// - "No video" placeholder when renderer has no source
/// - Name label overlay at bottom-left
/// - Green glowing border when [isSpeaking] is true
/// - Tap handler for PIP mode toggle
class VideoTile extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final String participantName;
  final bool isMini;
  final VoidCallback? onTap;
  final bool isMuted;
  final bool mirror;
  final bool isSpeaking;

  const VideoTile({
    super.key,
    this.renderer,
    required this.participantName,
    this.isMini = false,
    this.onTap,
    this.isMuted = false,
    this.mirror = false,
    this.isSpeaking = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasVideo = renderer?.srcObject != null;

    // Speaking glow: green animated border + box shadow.
    final borderColor = isSpeaking
        ? AppColors.online
        : isMini
        ? AppColors.online.withValues(alpha: 0.6)
        : AppColors.divider;
    final borderWidth = isSpeaking
        ? (isMini ? 2.5 : 2.0)
        : (isMini ? 2.0 : 1.0);
    final glowShadow = isSpeaking
        ? [
            BoxShadow(
              color: AppColors.online.withValues(alpha: 0.55),
              blurRadius: isMini ? 10 : 18,
              spreadRadius: isMini ? 1 : 2,
            ),
          ]
        : isMini
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: AppColors.serverBar,
          borderRadius: BorderRadius.circular(isMini ? 8 : 12),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: glowShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or placeholder
            if (hasVideo)
              RTCVideoView(
                renderer!,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              _buildPlaceholder(),

            // Name label
            Positioned(
              left: isMini ? 6 : 12,
              bottom: isMini ? 6 : 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      participantName,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: isMini ? 10 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isMuted) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.mic_off_rounded,
                        size: isMini ? 10 : 14,
                        color: AppColors.dnd,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Options button (top-right, only for full-size tiles)
            if (!isMini)
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {},
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.serverBar,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isMini ? 40 : 80,
              height: isMini ? 40 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.purple, AppColors.blurple],
                ),
              ),
              child: Center(
                child: Text(
                  participantName.isNotEmpty
                      ? participantName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMini ? 18 : 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (!isMini) ...[
              const SizedBox(height: 12),
              Text(
                participantName,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
