import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/settings/labels.dart';

/// Create, rename, recolour, reorder and delete labels.
class LabelsManagementScreen extends ConsumerStatefulWidget {
  const LabelsManagementScreen({super.key});

  @override
  ConsumerState<LabelsManagementScreen> createState() =>
      _LabelsManagementScreenState();
}

class _LabelsManagementScreenState
    extends ConsumerState<LabelsManagementScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final labelsState = ref.watch(labelsProvider);
    final all = labelsState.sorted;
    final visible = _query.trim().isEmpty
        ? all
        : all
            .where((l) =>
                l.name.toLowerCase().contains(_query.trim().toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: const Text('Labels'),
        actions: [
          IconButton(
            tooltip: 'New label',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showLabelEditor(context, ref),
          ),
        ],
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.label_rounded,
              title: 'No labels yet',
              message:
                  'Create labels like Family, Work or Important to organise '
                  'your inbox and filter conversations.',
              actionLabel: 'Create a label',
              onAction: () => showLabelEditor(context, ref),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search labels…',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
                Expanded(
                  child: _query.trim().isEmpty
                      ? ReorderableListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          onReorder: (o, n) =>
                              ref.read(labelsProvider.notifier).reorder(o, n),
                          itemBuilder: (context, i) => _labelCard(
                              visible[i], labelsState,
                              key: ValueKey(visible[i].id)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          itemBuilder: (context, i) =>
                              _labelCard(visible[i], labelsState),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _labelCard(Label label, LabelsState state, {Key? key}) {
    final c = context.allora;
    final count = state.countFor(label.id);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.outline),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: label.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(label.icon, color: label.color, size: 20),
        ),
        title: Text(label.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(count == 0
            ? 'No chats'
            : '$count ${count == 1 ? 'chat' : 'chats'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_rounded, size: 19, color: c.textSecondary),
              onPressed: () => showLabelEditor(context, ref, existing: label),
            ),
            if (_query.trim().isEmpty)
              Icon(Icons.drag_handle_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet editor for creating or editing a label (name, colour, icon).
void showLabelEditor(BuildContext context, WidgetRef ref, {Label? existing}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _LabelEditor(existing: existing),
    ),
  );
}

class _LabelEditor extends ConsumerStatefulWidget {
  final Label? existing;
  const _LabelEditor({this.existing});

  @override
  ConsumerState<_LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends ConsumerState<_LabelEditor> {
  late final TextEditingController _name;
  late int _color;
  late int _iconIndex;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.colorValue ?? kLabelColors.first;
    _iconIndex = widget.existing?.iconIndex ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final notifier = ref.read(labelsProvider.notifier);
    if (widget.existing != null) {
      notifier.update(widget.existing!.id,
          name: name, colorValue: _color, iconIndex: _iconIndex);
    } else {
      notifier.create(name: name, colorValue: _color, iconIndex: _iconIndex);
    }
    Navigator.pop(context);
  }

  void _confirmDelete() {
    final c = context.allora;
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete label?'),
        content: Text(
            'Remove "${widget.existing!.name}" from all chats. Conversations '
            'are not deleted.',
            style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(labelsProvider.notifier).delete(widget.existing!.id);
              Navigator.pop(dctx);
              Navigator.pop(context);
            },
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(_color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(kLabelIconChoices[_iconIndex],
                      color: Color(_color)),
                ),
                const SizedBox(width: 12),
                Text(widget.existing == null ? 'New label' : 'Edit label',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.text)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Label name'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 18),
            Text('COLOR', style: _lbl(c)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in kLabelColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = color),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              _color == color ? c.text : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: _color == color
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('ICON', style: _lbl(c)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < kLabelIconChoices.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _iconIndex = i),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _iconIndex == i
                            ? Color(_color).withValues(alpha: 0.15)
                            : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _iconIndex == i
                              ? Color(_color)
                              : Colors.transparent,
                        ),
                      ),
                      child: Icon(kLabelIconChoices[i],
                          color: _iconIndex == i
                              ? Color(_color)
                              : c.textSecondary,
                          size: 21),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                if (widget.existing != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.danger,
                        side:
                            BorderSide(color: c.danger.withValues(alpha: 0.4)),
                      ),
                      onPressed: _confirmDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                if (widget.existing != null) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(widget.existing == null ? 'Create' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _lbl(AlloraColors c) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: c.textTertiary);
}

/// Sheet to toggle which labels are applied to a single chat.
void showAssignLabelsSheet(
    BuildContext context, WidgetRef ref, String roomId, String roomName) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AssignLabelsSheet(roomId: roomId, roomName: roomName),
  );
}

class _AssignLabelsSheet extends ConsumerWidget {
  final String roomId;
  final String roomName;
  const _AssignLabelsSheet({required this.roomId, required this.roomName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.allora;
    final state = ref.watch(labelsProvider);
    final assigned = state.labelIdsFor(roomId);
    final labels = state.sorted;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
            child: Row(
              children: [
                Icon(Icons.label_rounded, color: c.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Labels · $roomName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                ),
                TextButton.icon(
                  onPressed: () => showLabelEditor(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          if (labels.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No labels yet — tap "New" to create one.',
                  style: TextStyle(color: c.textSecondary)),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final label in labels)
                    CheckboxListTile(
                      value: assigned.contains(label.id),
                      activeColor: label.color,
                      onChanged: (_) => ref
                          .read(labelsProvider.notifier)
                          .toggleAssignment(roomId, label.id),
                      secondary: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: label.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Icon(label.icon, color: label.color, size: 18),
                      ),
                      title: Text(label.name),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
