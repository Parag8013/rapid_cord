import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_quality.dart';
import '../providers/media_provider.dart';
import '../theme/app_colors.dart';

/// Shows the quality settings modal dialog.
void showQualitySettingsPanel(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => ChangeNotifierProvider.value(
      value: Provider.of<MediaProvider>(context, listen: false),
      child: const _QualitySettingsDialog(),
    ),
  );
}

/// Shows a pre-stream dialog before starting screen share.
///
/// Lets the user configure resolution, FPS, and bitrates, then calls
/// [onStart] with the final [MediaQualitySettings].
void showPreStreamDialog(
  BuildContext context, {
  required void Function(MediaQualitySettings settings) onStart,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _PreStreamDialog(onStart: onStart),
  );
}

// ── Pre-Stream (Screen Share) Setup Dialog ──────────────────────────────────

class _PreStreamDialog extends StatefulWidget {
  final void Function(MediaQualitySettings) onStart;
  const _PreStreamDialog({required this.onStart});

  @override
  State<_PreStreamDialog> createState() => _PreStreamDialogState();
}

class _PreStreamDialogState extends State<_PreStreamDialog> {
  VideoResolution _resolution = VideoResolution.p1080;
  FrameRate _fps = FrameRate.fps30;
  VideoBitrate _videoBitrate = VideoBitrate.kbps2500;
  AudioBitrate _audioBitrate = AudioBitrate.kbps128;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: AppColors.sidebarBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.screen_share_rounded,
                      color: AppColors.purple,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Screen Share Settings',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Configure before streaming',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resolution
                    const _SectionHeader(
                      icon: Icons.high_quality_rounded,
                      label: 'Resolution',
                    ),
                    const SizedBox(height: 8),
                    _OptionRow<VideoResolution>(
                      options: VideoResolution.values,
                      selected: _resolution,
                      labelOf: (v) => v.label,
                      subtitleOf: (v) => '${v.width} × ${v.height}',
                      onSelect: (v) => setState(() => _resolution = v),
                    ),
                    const SizedBox(height: 20),

                    // Frame Rate
                    const _SectionHeader(
                      icon: Icons.speed_rounded,
                      label: 'Frame Rate',
                    ),
                    const SizedBox(height: 8),
                    _OptionRow<FrameRate>(
                      options: FrameRate.values,
                      selected: _fps,
                      labelOf: (v) => v.label,
                      subtitleOf: (v) {
                        switch (v) {
                          case FrameRate.fps15:
                            return 'Minimum bandwidth';
                          case FrameRate.fps30:
                            return 'Balanced (recommended)';
                          case FrameRate.fps60:
                            return 'Smooth — requires fast upload';
                        }
                      },
                      onSelect: (v) => setState(() => _fps = v),
                    ),
                    const SizedBox(height: 20),

                    // Video Bitrate
                    const _SectionHeader(
                      icon: Icons.videocam_rounded,
                      label: 'Video Bitrate',
                    ),
                    const SizedBox(height: 8),
                    _OptionRow<VideoBitrate>(
                      options: VideoBitrate.values,
                      selected: _videoBitrate,
                      labelOf: (v) => v.label,
                      subtitleOf: (v) {
                        switch (v) {
                          case VideoBitrate.kbps500:
                            return 'Low bandwidth';
                          case VideoBitrate.kbps1500:
                            return 'Balanced';
                          case VideoBitrate.kbps2500:
                            return 'High quality';
                          case VideoBitrate.kbps4000:
                            return 'Maximum quality';
                        }
                      },
                      onSelect: (v) => setState(() => _videoBitrate = v),
                    ),
                    const SizedBox(height: 20),

                    // Audio Bitrate
                    const _SectionHeader(
                      icon: Icons.audiotrack_rounded,
                      label: 'Audio Bitrate',
                    ),
                    const SizedBox(height: 8),
                    _OptionRow<AudioBitrate>(
                      options: AudioBitrate.values,
                      selected: _audioBitrate,
                      labelOf: (v) => v.label,
                      subtitleOf: (v) => v == AudioBitrate.kbps64
                          ? 'Low bandwidth'
                          : 'High quality',
                      onSelect: (v) => setState(() => _audioBitrate = v),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(color: AppColors.divider, height: 1),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                    ),
                    icon: const Icon(Icons.screen_share_rounded, size: 18),
                    label: const Text('Start Sharing'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onStart(
                        MediaQualitySettings(
                          videoResolution: _resolution,
                          frameRate: _fps,
                          videoBitrate: _videoBitrate,
                          audioBitrate: _audioBitrate,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ongoing Quality Settings Dialog ────────────────────────────────────────

class _QualitySettingsDialog extends StatelessWidget {
  const _QualitySettingsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: AppColors.sidebarBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            _buildHeader(context),
            const Divider(color: AppColors.divider, height: 1),

            // ── Content ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Consumer<MediaProvider>(
                  builder: (context, mediaProv, _) {
                    final qs = mediaProv.qualitySettings;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Video Resolution ──
                        _SectionHeader(
                          icon: Icons.high_quality_rounded,
                          label: 'Video Resolution',
                        ),
                        const SizedBox(height: 8),
                        _OptionRow<VideoResolution>(
                          options: VideoResolution.values,
                          selected: qs.videoResolution,
                          labelOf: (v) => v.label,
                          subtitleOf: (v) => '${v.width} × ${v.height}',
                          onSelect: (v) => mediaProv.setVideoResolution(v),
                        ),
                        const SizedBox(height: 24),

                        // ── Frame Rate ──
                        _SectionHeader(
                          icon: Icons.speed_rounded,
                          label: 'Frame Rate',
                        ),
                        const SizedBox(height: 8),
                        _OptionRow<FrameRate>(
                          options: FrameRate.values,
                          selected: qs.frameRate,
                          labelOf: (v) => v.label,
                          subtitleOf: (v) => switch (v) {
                            FrameRate.fps15 => 'Minimum bandwidth',
                            FrameRate.fps30 => 'Balanced',
                            FrameRate.fps60 => 'Smooth',
                          },
                          onSelect: (v) => mediaProv.setFrameRate(v),
                        ),
                        const SizedBox(height: 24),

                        // ── Audio Bitrate ──
                        _SectionHeader(
                          icon: Icons.audiotrack_rounded,
                          label: 'Audio Bitrate',
                        ),
                        const SizedBox(height: 8),
                        _OptionRow<AudioBitrate>(
                          options: AudioBitrate.values,
                          selected: qs.audioBitrate,
                          labelOf: (v) => v.label,
                          subtitleOf: (v) => v == AudioBitrate.kbps64
                              ? 'Low bandwidth'
                              : 'High quality',
                          onSelect: (v) => mediaProv.setAudioBitrate(v),
                        ),
                        const SizedBox(height: 24),

                        // ── Video Bitrate ──
                        _SectionHeader(
                          icon: Icons.speed_rounded,
                          label: 'Video Bitrate',
                        ),
                        const SizedBox(height: 8),
                        _OptionRow<VideoBitrate>(
                          options: VideoBitrate.values,
                          selected: qs.videoBitrate,
                          labelOf: (v) => v.label,
                          subtitleOf: (v) {
                            switch (v) {
                              case VideoBitrate.kbps500:
                                return 'Low bandwidth';
                              case VideoBitrate.kbps1500:
                                return 'Balanced';
                              case VideoBitrate.kbps2500:
                                return 'High quality';
                              case VideoBitrate.kbps4000:
                                return 'Maximum quality';
                            }
                          },
                          onSelect: (v) => mediaProv.setVideoBitrate(v),
                        ),
                        const SizedBox(height: 16),

                        // ── Current Settings Summary ──
                        _buildSummary(qs),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: AppColors.purple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stream Quality',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Bandwidth & resolution settings',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(MediaQualitySettings qs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.purpleLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${qs.videoResolution.label} · ${qs.frameRate.label} · ${qs.audioBitrate.label} audio · ${qs.videoBitrate.label} video',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Internal Widgets ──

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.purpleLight),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final String Function(T) subtitleOf;
  final ValueChanged<T> onSelect;

  const _OptionRow({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.subtitleOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((option) {
        final isSelected = option == selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(option),
              hoverColor: AppColors.channelHover,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.purple.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.purple.withValues(alpha: 0.5)
                        : AppColors.divider,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Radio indicator
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.purple
                              : AppColors.textMuted,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.purple,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labelOf(option),
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          Text(
                            subtitleOf(option),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColors.purple,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
