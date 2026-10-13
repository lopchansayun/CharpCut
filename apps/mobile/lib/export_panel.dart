import 'package:flutter/material.dart';

import 'theme.dart';

/// Export options chosen in the settings panel.
class ExportSettings {
  int resolutionIndex = 1; // 720p
  int fpsIndex = 2; // 30
  bool opticalFlow = false;
  int bitrateIndex = 1; // 10 Mbps (recommended)
  int gifResolutionIndex = 1;
  int gifFpsIndex = 1;

  static const resolutions = ['480p', '720p', '1080p', '2K/4K'];
  static const resolutionNotes = [
    'Low definition - smallest file size',
    'Standard definition - the resolution used for most social videos',
    'Full HD - sharper detail',
    'Ultra HD - largest file size',
  ];
  static const fpsValues = [24, 25, 30, 50, 60];
  static const bitrates = [5, 10, 20, 50, 100];
  static const recommendedBitrate = 10;
  static const gifResolutions = ['240p', '360p', '480p', '720p'];
  static const gifFps = [10, 15, 20, 25, 30];

  /// Short label for the quality pill in the editor's top bar.
  String get pillLabel => resolutions[resolutionIndex];

  /// Rough size from bitrate x duration. It ignores audio and container overhead.
  String estimatedSize(double seconds) {
    final mb = bitrates[bitrateIndex] * seconds / 8;
    if (mb < 0.1) return '<0.1 MB';
    return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
}

const _panelBg = Color(0xFF1C1C1E);
const _trackGray = Color(0xFF3A3A3D);

/// Full-width settings sheet that drops down from the top bar, with a dim
/// scrim over the editor underneath.
class ExportPanel extends StatefulWidget {
  const ExportPanel({
    super.key,
    required this.settings,
    required this.durationSeconds,
    required this.onClose,
    required this.onExport,
    required this.onChanged,
  });

  final ExportSettings settings;
  final double durationSeconds;
  final VoidCallback onClose;
  final VoidCallback onExport;
  final VoidCallback onChanged;

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  bool _gif = false;

  ExportSettings get s => widget.settings;

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: .72)),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: _panelBg,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * .92),
              child: Padding(
                padding: EdgeInsets.only(top: media.padding.top),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                        child: _gif ? _gifBody() : _videoBody(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _tab('video', !_gif, () => setState(() => _gif = false)),
          const SizedBox(width: 20),
          _tab('GIF', _gif, () => setState(() => _gif = true)),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: BoxDecoration(color: editorSurface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_gif ? 'GIF' : s.pillLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_up_rounded, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          ExportButton(onTap: widget.onExport),
        ],
      ),
    ),
  );

  Widget _tab(String label, bool active, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: active ? Colors.white : editorMuted),
        ),
        const SizedBox(height: 4),
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: active ? accentCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    ),
  );

  // -------------------------------------------------------------------------
  // Video tab
  // -------------------------------------------------------------------------

  Widget _videoBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionTitle('Resolution', trailing: ExportSettings.resolutionNotes[s.resolutionIndex], help: true),
      _StopSlider(
        labels: ExportSettings.resolutions,
        index: s.resolutionIndex,
        onChanged: (i) => _changed(() => s.resolutionIndex = i),
      ),
      const SizedBox(height: 20),
      _sectionTitle('Frame rate', trailing: 'Smoother playback'),
      _StopSlider(
        labels: [for (final f in ExportSettings.fpsValues) '$f'],
        index: s.fpsIndex,
        onChanged: (i) => _changed(() => s.fpsIndex = i),
      ),
      const SizedBox(height: 20),
      _toggleRow(
        title: 'Optical flow',
        subtitle: 'Make video playback smoother.',
        value: s.opticalFlow,
        onChanged: (v) => _changed(() => s.opticalFlow = v),
      ),
      const SizedBox(height: 20),
      _sectionTitle('Bitrate (Mbps)', trailing: 'Recommended for this video(${ExportSettings.recommendedBitrate})'),
      _StopSlider(
        labels: [for (final b in ExportSettings.bitrates) '$b'],
        index: s.bitrateIndex,
        onChanged: (i) => _changed(() => s.bitrateIndex = i),
      ),
      const SizedBox(height: 18),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => toast(context, 'Watermark options are coming soon'),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text('Watermark', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Spacer(),
              Text('None', style: TextStyle(color: editorMuted, fontSize: 15)),
              Icon(Icons.chevron_right_rounded, color: editorMuted),
            ],
          ),
        ),
      ),
      const Divider(color: Color(0xFF2E2E31), height: 18),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Estimated file size: ${s.estimatedSize(widget.durationSeconds)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: editorMuted, fontSize: 14),
        ),
      ),
    ],
  );

  // -------------------------------------------------------------------------
  // GIF tab
  // -------------------------------------------------------------------------

  Widget _gifBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      _sectionTitle('Resolution', trailing: 'Smaller sizes share more easily'),
      _StopSlider(
        labels: ExportSettings.gifResolutions,
        index: s.gifResolutionIndex,
        onChanged: (i) => _changed(() => s.gifResolutionIndex = i),
      ),
      const SizedBox(height: 20),
      _sectionTitle('Frame rate', trailing: 'Higher is smoother'),
      _StopSlider(
        labels: [for (final f in ExportSettings.gifFps) '$f'],
        index: s.gifFpsIndex,
        onChanged: (i) => _changed(() => s.gifFpsIndex = i),
      ),
      const SizedBox(height: 12),
    ],
  );

  // -------------------------------------------------------------------------
  // Shared rows
  // -------------------------------------------------------------------------

  Widget _sectionTitle(String title, {required String trailing, bool help = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (help) ...[
          const SizedBox(width: 6),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.help_outline_rounded, size: 17, color: editorMuted),
          ),
        ],
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            style: const TextStyle(color: editorMuted, fontSize: 13, height: 1.25),
          ),
        ),
      ],
    ),
  );

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color subtitleColor = editorMuted,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 13, height: 1.25)),
          ],
        ),
      ),
      const SizedBox(width: 8),
      const Text('|', style: TextStyle(color: _trackGray)),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: () => toast(context, 'Examples are coming soon'),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_outlined, size: 16, color: editorMuted),
            SizedBox(width: 2),
            Text('Example', style: TextStyle(color: editorMuted, fontSize: 13)),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: accentCyan,
        activeThumbColor: Colors.white,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.transparent,
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : editorMuted,
        ),
      ),
    ],
  );
}

/// The cyan "Export" button used in the editor and in the settings panel.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: accentCyan, borderRadius: BorderRadius.circular(10)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.ios_share_rounded, size: 18, color: Color(0xFF0B0B0C)),
          SizedBox(width: 6),
          Text('Export', style: TextStyle(color: Color(0xFF0B0B0C), fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

/// Discrete slider: a track with evenly spaced stops and a label under each.
/// The first and last labels hug the track ends, middle ones are centred.
class _StopSlider extends StatelessWidget {
  const _StopSlider({required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double xOf(int i) => w * i / (n - 1);
        int nearest(double dx) => ((dx / w) * (n - 1)).round().clamp(0, n - 1);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onChanged(nearest(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) => onChanged(nearest(d.localPosition.dx)),
          child: SizedBox(
            height: 62,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 19,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: _trackGray, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 19,
                  width: xOf(index),
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: accentCyan, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                for (var i = 1; i < n - 1; i++)
                  if (i != index)
                    Positioned(
                      left: xOf(i) - 1,
                      top: 15,
                      width: 2,
                      height: 11,
                      child: ColoredBox(color: i < index ? accentCyan : _trackGray),
                    ),
                Positioned(
                  left: xOf(index) - 9,
                  top: 12.5,
                  width: 18,
                  height: 18,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                    ),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: xOf(i),
                    top: 40,
                    child: FractionalTranslation(
                      translation: Offset(i == 0 ? 0 : (i == n - 1 ? -1 : -.5), 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 14,
                              color: i == index ? Colors.white : const Color(0xFFB8B8BD),
                              fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
