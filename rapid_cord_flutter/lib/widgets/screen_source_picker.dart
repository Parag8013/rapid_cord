import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../theme/app_colors.dart';

/// Shows a Discord-themed dialog letting the user pick a screen or window
/// to share.  Returns a record with the selected source and whether to share
/// system audio, or `null` if the user cancelled.
Future<({DesktopCapturerSource source, bool shareAudio})?>
showScreenSourcePicker(BuildContext context) async {
  return showDialog<({DesktopCapturerSource source, bool shareAudio})>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const _SourcePickerDialog(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _SourcePickerDialog extends StatefulWidget {
  const _SourcePickerDialog();

  @override
  State<_SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<_SourcePickerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Map<String, DesktopCapturerSource> _sources = {};
  DesktopCapturerSource? _selected;
  bool _shareAudio = true;
  bool _loading = true;
  Timer? _refreshTimer;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) _reload();
      });

    _subs.add(
      desktopCapturer.onAdded.stream.listen((s) {
        if (mounted) setState(() => _sources[s.id] = s);
      }),
    );
    _subs.add(
      desktopCapturer.onRemoved.stream.listen((s) {
        if (mounted) setState(() => _sources.remove(s.id));
      }),
    );
    _subs.add(
      desktopCapturer.onThumbnailChanged.stream.listen((_) {
        if (mounted) setState(() {});
      }),
    );

    _reload();
  }

  SourceType get _currentType =>
      _tabController.index == 0 ? SourceType.Screen : SourceType.Window;

  Future<void> _reload() async {
    _refreshTimer?.cancel();
    if (mounted) setState(() => _loading = true);
    try {
      final sources = await desktopCapturer.getSources(
        types: [_currentType],
        thumbnailSize: ThumbnailSize(320, 180),
      );
      if (!mounted) return;
      _sources.clear();
      for (final s in sources) {
        _sources[s.id] = s;
      }
      _selected = null;
      _loading = false;
      setState(() {});
      // Refresh thumbnails every 2 s while the dialog is open.
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        desktopCapturer.updateSources(types: [_currentType]);
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _tabController.dispose();
    super.dispose();
  }

  void _confirm() {
    _refreshTimer?.cancel();
    Navigator.of(context).pop((source: _selected!, shareAudio: _shareAudio));
  }

  void _cancel() {
    _refreshTimer?.cancel();
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources.values.toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 660,
        height: 520,
        decoration: BoxDecoration(
          color: AppColors.sidebarBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
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
                          'Choose what to share',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select a screen or application window',
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
                    onTap: _cancel,
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

            // ── Tabs ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.purple,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Entire Screen'),
                  Tab(text: 'Application Window'),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),

            // ── Source grid ──────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.purple),
                    )
                  : sources.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.desktop_windows_outlined,
                            size: 48,
                            color: AppColors.textMuted.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No sources found',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.4,
                            ),
                        itemCount: sources.length,
                        itemBuilder: (_, i) => _SourceTile(
                          source: sources[i],
                          selected: _selected?.id == sources[i].id,
                          onTap: (s) => setState(() => _selected = s),
                        ),
                      ),
                    ),
            ),

            const Divider(color: AppColors.divider, height: 1),
            // ── Audio Toggle + Actions ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.audiotrack_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Share system audio',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Switch(
                    value: _shareAudio,
                    onChanged: (v) => setState(() => _shareAudio = v),
                    activeThumbColor: AppColors.purple,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            // ── Actions ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _selected != null
                          ? AppColors.purple
                          : AppColors.textMuted.withValues(alpha: 0.3),
                    ),
                    icon: const Icon(Icons.screen_share_rounded, size: 18),
                    label: const Text('Share'),
                    onPressed: _selected != null ? _confirm : null,
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

// ─────────────────────────────────────────────────────────────────────────────

class _SourceTile extends StatefulWidget {
  final DesktopCapturerSource source;
  final bool selected;
  final void Function(DesktopCapturerSource) onTap;

  const _SourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends State<_SourceTile> {
  Uint8List? _thumb;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _thumb = widget.source.thumbnail;
    _subs.add(
      widget.source.onThumbnailChanged.stream.listen((t) {
        if (mounted) setState(() => _thumb = t);
      }),
    );
    _subs.add(
      widget.source.onNameChanged.stream.listen((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: widget.selected
            ? AppColors.purple.withValues(alpha: 0.15)
            : AppColors.channelHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.selected ? AppColors.purple : AppColors.divider,
          width: widget.selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => widget.onTap(widget.source),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
                child: _thumb != null
                    ? Image.memory(
                        _thumb!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        color: AppColors.serverBar,
                        child: Icon(
                          widget.source.type == SourceType.Screen
                              ? Icons.monitor_rounded
                              : Icons.web_asset_rounded,
                          size: 32,
                          color: AppColors.textMuted.withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ),
            // Name label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                widget.source.name,
                style: TextStyle(
                  color: widget.selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
