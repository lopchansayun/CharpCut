import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/media_library.dart';
import 'media_thumbnail.dart';

/// Device imports can be reused across projects and placed on timeline tracks.
class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key, this.selectVideo = false, this.selectKind, this.initialFilter = 'all'});
  final bool selectVideo;
  final String? selectKind;
  final String initialFilter;
  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  String? get _selectionKind => widget.selectKind ?? (widget.selectVideo ? 'video' : null);
  final _library = MediaLibrary();
  late Future<List<LibraryMedia>> _items;
  late String _filter;
  String _query = '';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _filter = _selectionKind ?? widget.initialFilter;
    _items = _library.list();
  }
  void _refresh() {
    if (!mounted) return;
    final items = _library.list();
    setState(() {
      _items = items;
    });
  }
  void _error(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error is PlatformException ? error.message ?? 'Could not read media' : '$error')));
  }

  Future<void> _import(String kind) async {
    setState(() => _busy = true);
    try {
      final item = await _library.importMedia(kind);
      if (item != null && mounted) {
        setState(() { _filter = kind; });
        _refresh();
        if (_selectionKind == kind) {
          Navigator.pop(context, item);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.name} imported')));
        }
      }
    } catch (error) { _error(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _open(LibraryMedia item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fresh = await _library.inspect(item.path);
      if (!mounted) return;
      if (_selectionKind == fresh.kind) {
        Navigator.pop(context, fresh);
      } else {
        await _details(fresh);
      }
    } catch (error) { _error(error); _refresh(); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _details(LibraryMedia item) async {
    final data = item.data;
    String value(String key, [String suffix = '']) => data[key] == null ? 'Not reported' : '${data[key]}$suffix';
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (context) => SafeArea(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (item.kind != 'audio') SizedBox(height: 180, width: double.infinity,
              child: MediaThumbnail(path: item.path, kind: item.kind)),
          const SizedBox(height: 16),
          Text(item.summary),
          Text('Format: ${value('mime')}'),
          Text('Size: ${((data['size_bytes'] as num? ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB'),
          if (item.kind != 'audio') ...[
            Text('Rotation: ${value('rotation', '°')}'),
            if (data['mirrored'] == true) const Text('Mirrored image'),
          ],
          if (item.kind == 'video') Text('Frame rate: ${value('frame_rate', ' fps')}${data['frame_rate_estimated'] == true ? ' (average)' : ''}'),
          if (item.audioStreams.isEmpty && item.kind != 'image') const Text('No audio stream'),
          for (var i = 0; i < item.audioStreams.length; i++) ...[
            const SizedBox(height: 8),
            Text('Audio ${i + 1}: ${item.audioStreams[i]['codec']}'),
            Text('${item.audioStreams[i]['channels'] ?? '?'} channels • ${item.audioStreams[i]['sample_rate'] ?? '?'} Hz'),
            if (item.audioStreams[i]['bitrate'] != null) Text('${item.audioStreams[i]['bitrate']} bits/s'),
            if (item.audioStreams[i]['decodable'] == false) const Text('This device cannot decode this audio stream.'),
          ],
          const SizedBox(height: 16),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ]),
      ))),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_selectionKind == null ? 'Media library' : 'Add $_selectionKind'), actions: [
      IconButton(tooltip: 'Refresh', onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
    ]),
    body: Column(children: [
      if (_busy) const LinearProgressIndicator(),
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final kind in _selectionKind == null ? ['video', 'audio', 'image'] : [_selectionKind!])
          FilledButton.tonalIcon(onPressed: _busy ? null : () => _import(kind),
            icon: const Icon(Icons.file_upload_outlined), label: Text('Import $kind')),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search imported media'),
        onChanged: (value) => setState(() => _query = value.toLowerCase()),
      )),
      if (_selectionKind == null) Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, children: [
        for (final kind in ['all', 'video', 'audio', 'image'])
          ChoiceChip(label: Text(kind[0].toUpperCase() + kind.substring(1)), selected: _filter == kind,
              onSelected: (_) => setState(() => _filter = kind)),
      ])),
      Expanded(child: FutureBuilder<List<LibraryMedia>>(future: _items, builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Could not load media: ${snapshot.error}'),
            TextButton(onPressed: _refresh, child: const Text('Retry')),
          ])));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!.where((item) => (_filter == 'all' || item.kind == _filter || !item.available)
            && item.name.toLowerCase().contains(_query)).toList();
        if (items.isEmpty) return const Center(child: Text('No media here yet. Import a file above.'));
        return ListView.builder(itemCount: items.length, itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: SizedBox(width: 64, height: 54, child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: MediaThumbnail(key: ValueKey('${item.path}:${item.available}'), path: item.path, kind: item.kind, enabled: item.available))),
            title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.available ? item.summary : item.error ?? 'Media unavailable; import it again'),
            isThreeLine: !item.available,
            trailing: Icon(_selectionKind == item.kind && item.available ? Icons.add_circle_outline : Icons.info_outline),
            onTap: _busy ? null : () => _open(item),
          );
        });
      })),
    ]),
  );
}
