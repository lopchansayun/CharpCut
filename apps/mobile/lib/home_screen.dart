import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_screen.dart';
import 'draft_list.dart';
import 'media_library_screen.dart';
import 'engine/editor_engine.dart';
import 'engine/project_session.dart';
import 'theme.dart';

class _Tool {
  const _Tool(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _tools = <_Tool>[
  _Tool('Trim video', Icons.content_cut_rounded),
  _Tool('Retouch', Icons.face_retouching_natural_outlined),
  _Tool('Stickers', Icons.emoji_emotions_outlined),
  _Tool('Photo tools', Icons.photo_library_outlined),
  _Tool('Shoot and record', Icons.camera_outlined),
  _Tool('Auto enhance', Icons.auto_fix_high_outlined),
  _Tool('Cover maker', Icons.crop_portrait_outlined),
  _Tool('Auto captions', Icons.closed_caption_outlined),
  _Tool('Remove background', Icons.layers_clear_outlined),
  _Tool('Photo editor', Icons.photo_filter_outlined),
  _Tool('Space', Icons.cloud_outlined),
  _Tool('Marketing tools', Icons.work_outline_rounded),
];

Future<void> _openEditor(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditorHome()));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildLightTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.white,
          body: IndexedStack(
            index: _tab,
            children: const [
              _EditTab(),
              _PlaceholderTab(title: 'Templates'),
              _ProjectsTab(),
              _PlaceholderTab(title: 'Me'),
            ],
          ),
          bottomNavigationBar: _BottomNav(index: _tab, onChanged: (i) => setState(() => _tab = i)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit tab
// ---------------------------------------------------------------------------

class _EditTab extends StatelessWidget {
  const _EditTab();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SingleChildScrollView(
        child: Stack(
          children: [
            const Positioned(top: 0, left: 0, right: 0, height: 520, child: _HeroBackdrop()),
            Padding(
              padding: EdgeInsets.only(top: top + 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TopRow(),
                  const SizedBox(height: 6),
                  const _HeroVisual(),
                  const _HeroTitle(),
                  const SizedBox(height: 16),
                  const _CreateCards(),
                  const SizedBox(height: 16),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      leading: const Icon(Icons.perm_media_outlined),
                      title: const Text('Media library'),
                      subtitle: const Text('Import videos, audio and images'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MediaLibraryScreen())),
                    )),
                  const _RecentStrip(),
                  const SizedBox(height: 16),
                  const _ToolGrid(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1B52D6), Color(0xFF2F78EE), Color(0xFF8DB8F7), Color(0xFFDCE9FD), Colors.white],
        stops: [0, .32, .6, .85, 1],
      ),
    ),
  );
}

class _TopRow extends StatelessWidget {
  const _TopRow();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: () => toast(context, 'Search is not available yet'),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1A4A).withValues(alpha: .55),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    ),
  );
}

/// Decorative floating "template" cards behind the hero title.
class _HeroVisual extends StatelessWidget {
  const _HeroVisual();

  static const _cards = <_FloatCard>[
    _FloatCard(Alignment(-.92, -.1), 60, 72, -.16, [Color(0xFFFFD9B0), Color(0xFFE08A6B)]),
    _FloatCard(Alignment(-.62, -.95), 42, 44, .10, [Color(0xFF5A3B2E), Color(0xFF2A1A16)]),
    _FloatCard(Alignment(-.22, .35), 72, 84, -.06, [Color(0xFF7FA6E8), Color(0xFF2B4F9A)]),
    _FloatCard(Alignment(.10, -.55), 92, 112, .05, [Color(0xFFFFE3C9), Color(0xFFD99472)]),
    _FloatCard(Alignment(.62, -.95), 52, 58, .12, [Color(0xFFB9D3FF), Color(0xFF4F7FD8)]),
    _FloatCard(Alignment(.94, -.05), 60, 74, -.10, [Color(0xFF9BC0F5), Color(0xFF3B64B8)]),
    _FloatCard(Alignment(.58, .95), 54, 62, .10, [Color(0xFFD7C2FF), Color(0xFF6B53C9)]),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 168,
    child: Stack(
      children: [
        for (final c in _cards)
          Align(
            alignment: c.alignment,
            child: Transform.rotate(
              angle: c.angle,
              child: Container(
                width: c.w,
                height: c.h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: c.colors,
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: .55), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.all(5),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _FloatCard {
  const _FloatCard(this.alignment, this.w, this.h, this.angle, this.colors);
  final Alignment alignment;
  final double w;
  final double h;
  final double angle;
  final List<Color> colors;
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle();
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => toast(context, 'Templates are coming soon'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Template Trends', style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Row(
            children: [
              const Flexible(
                child: Text('Try the Hottest Templates',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .28), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.chevron_right_rounded, size: 14, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CreateCards extends StatelessWidget {
  const _CreateCards();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Expanded(flex: 512, child: _CreateCard(label: 'New video', onTap: () => _openEditor(context))),
        const SizedBox(width: 9),
        Expanded(
          flex: 512,
          child: _CreateCard(
            label: 'Edit photo',
            icon: Icons.image_rounded,
            badge: 'New',
            onTap: () => toast(context, 'Photo editing is coming soon'),
          ),
        ),
      ],
    ),
  );
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({required this.label, required this.onTap, this.icon = Icons.add_rounded, this.badge});
  final String label;
  final IconData icon;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC9DDFF), Color(0xFFE4EEFF)],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: homeInk, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(height: 14),
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: homeInk)),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: 0,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Text(badge!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: homeInk)),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RecentStrip extends StatelessWidget {
  const _RecentStrip();
  @override
  Widget build(BuildContext context) {
    final engine = EngineScope.of(context);
    if (engine is! ProjectSession) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your drafts', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: homeInk)),
        DraftList(session: engine, onOpen: (id) async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EditorHome(draftId: id)));
        }),
      ]),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  const _ToolGrid();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tools.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: 96),
      itemBuilder: (context, i) {
        final tool = _tools[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => toast(context, '${tool.label} is coming soon'),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tool.icon, size: 28, color: homeInk),
              const SizedBox(height: 9),
              Text(
                tool.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: homeInk, height: 1.15),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Other tabs
// ---------------------------------------------------------------------------

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab();
  @override
  Widget build(BuildContext context) {
    final engine = EngineScope.of(context);
    return SafeArea(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Projects', style: TextStyle(fontSize: 24,
            fontWeight: FontWeight.w800, color: homeInk)),
        const SizedBox(height: 12),
        const Text('Each video has its own autosaved draft on this device. Tap a draft to continue, or use its menu to rename, duplicate or delete it.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add), label: const Text('New video')),
        const SizedBox(height: 12),
        if (engine is ProjectSession)
          DraftList(session: engine, onOpen: (id) async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EditorHome(draftId: id)));
          })
        else
          const Text('Project storage is unavailable'),
      ],
    ));
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: homeInk)),
          const SizedBox(height: 6),
          const Text('Coming soon', style: TextStyle(color: homeMuted)),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Bottom navigation
// ---------------------------------------------------------------------------

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <(IconData, String)>[
    (Icons.content_cut_rounded, 'Edit'),
    (Icons.view_agenda_outlined, 'Templates'),
    (Icons.folder_outlined, 'Projects'),
    (Icons.person_outline_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFF0F1F4))),
    ),
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
    child: SizedBox(
      height: 60,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_items[i].$1, size: 26, color: i == index ? homeInk : homeMuted),
                    const SizedBox(height: 3),
                    Text(
                      _items[i].$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                        color: i == index ? homeInk : homeMuted,
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
}
