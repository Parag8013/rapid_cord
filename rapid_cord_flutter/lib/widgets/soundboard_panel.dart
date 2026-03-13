import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';

/// Soundboard grid data.
class _SoundItem {
  final String label;
  final IconData icon;
  final SoundEffect effect;
  final Color color;

  const _SoundItem({
    required this.label,
    required this.icon,
    required this.effect,
    required this.color,
  });
}

const List<_SoundItem> _soundItems = [
  _SoundItem(
    label: 'Airhorn',
    icon: Icons.campaign_rounded,
    effect: SoundEffect.soundboardAirhorn,
    color: Color(0xFFED4245),
  ),
  _SoundItem(
    label: 'Rimshot',
    icon: Icons.music_note_rounded,
    effect: SoundEffect.soundboardRimshot,
    color: Color(0xFFFAA81A),
  ),
  _SoundItem(
    label: 'Sad Trombone',
    icon: Icons.sentiment_dissatisfied_rounded,
    effect: SoundEffect.soundboardSadTrombone,
    color: Color(0xFF3BA55D),
  ),
  _SoundItem(
    label: 'Applause',
    icon: Icons.celebration_rounded,
    effect: SoundEffect.soundboardApplause,
    color: Color(0xFF5865F2),
  ),
  _SoundItem(
    label: 'Crickets',
    icon: Icons.bug_report_rounded,
    effect: SoundEffect.soundboardCrickets,
    color: Color(0xFF9B84FF),
  ),
  _SoundItem(
    label: 'Drum Roll',
    icon: Icons.queue_music_rounded,
    effect: SoundEffect.soundboardDrumRoll,
    color: Color(0xFFE67E22),
  ),
];

/// Shows the soundboard panel dialog.
void showSoundboardPanel(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => const _SoundboardDialog(),
  );
}

class _SoundboardDialog extends StatelessWidget {
  const _SoundboardDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.dashboard_rounded,
                    color: AppColors.purple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Soundboard',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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
            const SizedBox(height: 20),

            // Sound grid
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: _soundItems.length,
              itemBuilder: (context, index) {
                return _SoundButton(item: _soundItems[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SoundButton extends StatefulWidget {
  final _SoundItem item;

  const _SoundButton({required this.item});

  @override
  State<_SoundButton> createState() => _SoundButtonState();
}

class _SoundButtonState extends State<_SoundButton>
    with SingleTickerProviderStateMixin {
  bool _playing = false;

  void _onTap() async {
    setState(() => _playing = true);
    await SoundService.instance.playSoundboard(widget.item.effect);

    // Broadcast the sound effect to the rest of the room.
    if (mounted) {
      context.read<CallProvider>().sendSoundboardEffect(
        widget.item.effect.name,
      );
    }

    // Brief visual feedback.
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _playing
                ? widget.item.color.withValues(alpha: 0.3)
                : AppColors.channelActive.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _playing ? widget.item.color : AppColors.divider,
              width: _playing ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                size: 28,
                color: _playing ? widget.item.color : AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                widget.item.label,
                style: TextStyle(
                  color: _playing ? widget.item.color : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
