import 'package:flutter/material.dart';

import 'engine/project_session.dart';
import 'engine/editor_engine.dart';
import 'media_thumbnail.dart';

/// Both the home library and editor picker use the same persisted draft list.
class DraftList extends StatefulWidget {
  const DraftList({super.key, required this.session, required this.onOpen,
    this.allowManage = true});
  final ProjectSession session;
  final Future<void> Function(String id) onOpen;
  final bool allowManage;

  @override
  State<DraftList> createState() => _DraftListState();
}

class _DraftListState extends State<DraftList> {
  late Future<List<ProjectDraft>> _drafts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _drafts = widget.session.listDrafts();
    widget.session.libraryRevision.addListener(_reload);
  }

  @override
  void dispose() {
    widget.session.libraryRevision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final drafts = widget.session.listDrafts();
    setState(() {
      _drafts = drafts;
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update project: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ProjectDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${draft.name}"?'),
        content: const Text('This removes the draft and its edits from your projects. Original videos are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await widget.session.deleteDraft(draft.id);
  }

  Future<void> _rename(ProjectDraft draft) async {
    var name = draft.name;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project'),
        content: TextFormField(
          initialValue: name, autofocus: true, maxLength: 100,
          decoration: const InputDecoration(labelText: 'Project name'),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, name), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) await widget.session.renameDraft(draft.id, result);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProjectDraft>>(
    future: _drafts,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load drafts: ${snapshot.error}'),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ]);
      }
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final drafts = snapshot.data!;
      if (drafts.isEmpty) return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No drafts yet. Start a new video to create one.'),
      );
      return Column(children: [
        for (final draft in drafts)
          ListTile(
            leading: SizedBox(width: 56, height: 48, child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: draft.firstFrame == null ? const Icon(Icons.video_library_outlined)
                  : MediaThumbnail(path: draft.firstFrame!.$1,
                      positionMs: draft.firstFrame!.$2,
                      enabled: EngineScope.previewEnabledOf(context)))),
            title: Text(draft.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('Edited ${MaterialLocalizations.of(context).formatShortDate(draft.updatedAt.toLocal())} '
                '${TimeOfDay.fromDateTime(draft.updatedAt.toLocal()).format(context)}'),
            onTap: _busy ? null : () => _perform(() => widget.onOpen(draft.id)),
            trailing: widget.allowManage ? PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: 'Manage ${draft.name}',
              onSelected: (action) => _perform(() async {
                if (action == 'delete') { await _delete(draft); }
                else if (action == 'duplicate') { await widget.session.duplicateDraft(draft.id); }
                else { await _rename(draft); }
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ) : const Icon(Icons.chevron_right),
          ),
      ]);
    },
  );
}

Future<String?> pickDraft(BuildContext context, ProjectSession session) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Open project', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DraftList(session: session, allowManage: false,
              onOpen: (id) async => Navigator.pop(context, id)),
          ]),
        )),
      )),
    );
