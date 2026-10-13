import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// What the user asked for on the export-complete screen, returned to the editor.
enum ExportDoneResult { openSettings, newProject }

/// Simulated export progress. There is no render/encode pipeline yet, so this
/// only plays the UI flow and writes no file.
class ExportProgressDialog extends StatefulWidget {
  const ExportProgressDialog({super.key});
  @override
  State<ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<ExportProgressDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) Navigator.of(context).pop();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: editorSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Exporting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${(_c.value * 100).round()}%', style: const TextStyle(color: editorMuted, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _c.value,
                  minHeight: 5,
                  color: accentCyan,
                  backgroundColor: const Color(0xFF3A3A3D),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ExportDoneScreen extends StatefulWidget {
  const ExportDoneScreen({super.key});
  @override
  State<ExportDoneScreen> createState() => _ExportDoneScreenState();
}

class _ExportDoneScreenState extends State<ExportDoneScreen> {
  final PageController _promo = PageController(viewportFraction: .92);
  int _promoPage = 0;

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  void _soon(String what) => toast(context, '$what is not connected yet');

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: doneBg,
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _shareCard(),
                    const SizedBox(height: 22),
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Text('Quick actions', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 12),
                    _quickActions(),
                    const SizedBox(height: 18),
                    _promoCarousel(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
    height: 56,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.chevron_left_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Expanded(
          child: Text(
            'Export complete',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: Color(0xFFC3D3D8), fontWeight: FontWeight.w500),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 6),
      ],
    ),
  );

  Widget _shareCard() => Container(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
    decoration: BoxDecoration(color: doneCard, borderRadius: BorderRadius.circular(28)),
    child: Column(
      children: [
        _thumbnail(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: () => _soon('Sharing'),
            icon: const Icon(Icons.music_note_rounded, size: 20),
            label: const Text('Share to TikTok', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _shareTarget(Icons.camera_alt_outlined, 'Instagram'),
              _shareTarget(Icons.add_circle_outline_rounded, 'Stories'),
              _shareTarget(Icons.smart_display_rounded, 'YouTube'),
              _shareTarget(Icons.chat_rounded, 'WhatsApp'),
              _shareTarget(Icons.facebook, 'Facebook'),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _thumbnail() => Container(
    width: 85,
    height: 151,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF6C7F95), Color(0xFF2C3745)],
      ),
    ),
    child: Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .35), shape: BoxShape.circle),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
      ),
    ),
  );

  Widget _shareTarget(IconData icon, String label) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _soon('Sharing to $label'),
    child: SizedBox(
      width: 78,
      child: Column(
        children: [
          Icon(icon, size: 30),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFFB9CCD2))),
        ],
      ),
    ),
  );

  Widget _quickActions() => SizedBox(
    height: 112,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        _quick(Icons.add_box_outlined, 'New project', () => Navigator.of(context).pop(ExportDoneResult.newProject)),
        _quick(Icons.file_upload_outlined, 'Export options', () => Navigator.of(context).pop(ExportDoneResult.openSettings)),
        _quick(Icons.hd_outlined, 'Video quality', () => Navigator.of(context).pop(ExportDoneResult.openSettings)),
        _quick(Icons.view_carousel_outlined, 'Video to carousel', () => _soon('Carousel export')),
        _quick(Icons.edit_outlined, 'Edit cover', () => _soon('Cover editing')),
      ],
    ),
  );

  Widget _quick(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: 80,
      margin: const EdgeInsets.only(right: 9),
      child: Column(
        children: [
          Container(
            height: 60,
            width: 80,
            decoration: BoxDecoration(color: doneTile, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, size: 26),
          ),
          const SizedBox(height: 7),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 14, height: 1.1)),
        ],
      ),
    ),
  );

  Widget _promoCarousel() => Column(
    children: [
      SizedBox(
        height: 116,
        child: PageView(
          controller: _promo,
          padEnds: false,
          onPageChanged: (i) => setState(() => _promoPage = i),
          children: const [
            _PromoCard(title: 'Want stunning visuals?\nTry Filters.', collage: true),
            _PromoCard(title: 'Templates', subtitle: 'Try the hottest templates'),
            _PromoCard(title: 'Cover maker', subtitle: 'Design a cover for your video'),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _promoPage ? Colors.white : Colors.white30,
              ),
            ),
        ],
      ),
    ],
  );
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.title, this.subtitle, this.collage = false});
  final String title;
  final String? subtitle;
  final bool collage;

  static const _tiles = [Color(0xFF3A5A8C), Color(0xFF7A4F6D), Color(0xFF4F6F5E), Color(0xFF8C6A3A)];

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: doneTile, borderRadius: BorderRadius.circular(22)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.15)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(fontSize: 13, color: Color(0xFFB9CCD2))),
              ],
            ],
          ),
        ),
        if (collage)
          SizedBox(
            width: 84,
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final c in _tiles)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white54, width: 1),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
