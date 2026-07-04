import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart' show sharedPrefsProvider;

/// A user-defined conversation label (Family, Work, Important, …).
@immutable
class Label {
  final String id;
  final String name;
  final int colorValue;

  /// Index into [kLabelIconChoices]. Stored as an index (not a raw code
  /// point) so every rendered [IconData] stays *const* — required for
  /// Flutter's release-build icon tree-shaking to succeed.
  final int iconIndex;
  final int order;

  const Label({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconIndex,
    required this.order,
  });

  Color get color => Color(colorValue);
  IconData get icon =>
      kLabelIconChoices[iconIndex.clamp(0, kLabelIconChoices.length - 1)];

  Label copyWith({String? name, int? colorValue, int? iconIndex, int? order}) =>
      Label(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        iconIndex: iconIndex ?? this.iconIndex,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'iconIndex': iconIndex,
        'order': order,
      };

  factory Label.fromJson(Map<String, dynamic> j) => Label(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Label',
        colorValue: j['color'] as int? ?? 0xFF3A6FF8,
        iconIndex: j['iconIndex'] as int? ?? 0,
        order: j['order'] as int? ?? 0,
      );
}

/// Palette + glyphs offered by the label editor.
const kLabelColors = <int>[
  0xFF3A6FF8, 0xFF7C5CFC, 0xFF00A3AD, 0xFFE45794, 0xFFE8930C,
  0xFF1FA45B, 0xFFDB5C5C, 0xFF5C7CDB, 0xFFEC4899, 0xFF14B8A6,
  0xFFF59E0B, 0xFF8B5CF6,
];

/// Icon choices for labels (kept as IconData for tree-shaking friendliness).
const List<IconData> kLabelIconChoices = [
  Icons.label_rounded,
  Icons.family_restroom_rounded,
  Icons.group_rounded,
  Icons.work_rounded,
  Icons.business_center_rounded,
  Icons.star_rounded,
  Icons.flight_rounded,
  Icons.shopping_bag_rounded,
  Icons.person_rounded,
  Icons.push_pin_rounded,
  Icons.auto_awesome_rounded,
  Icons.favorite_rounded,
  Icons.school_rounded,
  Icons.sports_esports_rounded,
  Icons.restaurant_rounded,
  Icons.health_and_safety_rounded,
  Icons.attach_money_rounded,
  Icons.local_shipping_rounded,
  Icons.celebration_rounded,
  Icons.priority_high_rounded,
];

/// State: the ordered label list + per-room assignments (roomId → labelIds).
@immutable
class LabelsState {
  final List<Label> labels;
  final Map<String, Set<String>> assignments;

  const LabelsState({this.labels = const [], this.assignments = const {}});

  List<Label> get sorted =>
      [...labels]..sort((a, b) => a.order.compareTo(b.order));

  Set<String> labelIdsFor(String roomId) =>
      assignments[roomId] ?? const <String>{};

  List<Label> labelsFor(String roomId) {
    final ids = labelIdsFor(roomId);
    if (ids.isEmpty) return const [];
    return sorted.where((l) => ids.contains(l.id)).toList();
  }

  int countFor(String labelId) =>
      assignments.values.where((s) => s.contains(labelId)).length;

  LabelsState copyWith({
    List<Label>? labels,
    Map<String, Set<String>>? assignments,
  }) =>
      LabelsState(
        labels: labels ?? this.labels,
        assignments: assignments ?? this.assignments,
      );

  Map<String, dynamic> toJson() => {
        'labels': labels.map((l) => l.toJson()).toList(),
        'assignments':
            assignments.map((k, v) => MapEntry(k, v.toList())),
      };

  factory LabelsState.fromJson(Map<String, dynamic> j) {
    final labels = (j['labels'] as List?)
            ?.whereType<Map>()
            .map((m) => Label.fromJson(Map<String, dynamic>.from(m)))
            .toList() ??
        const <Label>[];
    final assignments = <String, Set<String>>{};
    final rawAssign = j['assignments'];
    if (rawAssign is Map) {
      rawAssign.forEach((k, v) {
        if (v is List) {
          assignments[k.toString()] = v.whereType<String>().toSet();
        }
      });
    }
    return LabelsState(labels: labels, assignments: assignments);
  }
}

class LabelsController extends StateNotifier<LabelsState> {
  static const _prefsKey = 'allora_labels_v1';
  final SharedPreferences _prefs;

  LabelsController(this._prefs) : super(_hydrate(_prefs));

  static LabelsState _hydrate(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return _seed();
      return LabelsState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _seed();
    }
  }

  /// Sensible starter labels so the feature isn't an empty screen on day one.
  static LabelsState _seed() => LabelsState(labels: [
        Label(
            id: 'seed_family',
            name: 'Family',
            colorValue: 0xFF1FA45B,
            iconIndex: 1,
            order: 0),
        Label(
            id: 'seed_work',
            name: 'Work',
            colorValue: 0xFF3A6FF8,
            iconIndex: 3,
            order: 1),
        Label(
            id: 'seed_important',
            name: 'Important',
            colorValue: 0xFFE8930C,
            iconIndex: 19,
            order: 2),
      ]);

  void _commit(LabelsState next) {
    state = next;
    _prefs.setString(_prefsKey, jsonEncode(next.toJson()));
  }

  String create({
    required String name,
    required int colorValue,
    required int iconIndex,
  }) {
    final id = 'lbl_${DateTime.now().microsecondsSinceEpoch}';
    final label = Label(
      id: id,
      name: name.trim().isEmpty ? 'Label' : name.trim(),
      colorValue: colorValue,
      iconIndex: iconIndex,
      order: state.labels.length,
    );
    _commit(state.copyWith(labels: [...state.labels, label]));
    return id;
  }

  void update(String id, {String? name, int? colorValue, int? iconIndex}) {
    _commit(state.copyWith(
      labels: state.labels
          .map((l) => l.id == id
              ? l.copyWith(
                  name: name?.trim(),
                  colorValue: colorValue,
                  iconIndex: iconIndex)
              : l)
          .toList(),
    ));
  }

  void delete(String id) {
    final assignments = <String, Set<String>>{};
    state.assignments.forEach((room, ids) {
      final next = ids.where((x) => x != id).toSet();
      if (next.isNotEmpty) assignments[room] = next;
    });
    _commit(state.copyWith(
      labels: state.labels.where((l) => l.id != id).toList(),
      assignments: assignments,
    ));
  }

  void reorder(int oldIndex, int newIndex) {
    final list = state.sorted;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(order: i);
    }
    _commit(state.copyWith(labels: list));
  }

  void toggleAssignment(String roomId, String labelId) {
    final assignments = Map<String, Set<String>>.from(state.assignments);
    final current = Set<String>.from(assignments[roomId] ?? const {});
    current.contains(labelId)
        ? current.remove(labelId)
        : current.add(labelId);
    if (current.isEmpty) {
      assignments.remove(roomId);
    } else {
      assignments[roomId] = current;
    }
    _commit(state.copyWith(assignments: assignments));
  }

  void forgetRooms(Iterable<String> roomIds) {
    final ids = roomIds.toSet();
    if (ids.isEmpty) return;
    final assignments = Map<String, Set<String>>.from(state.assignments)
      ..removeWhere((k, _) => ids.contains(k));
    _commit(state.copyWith(assignments: assignments));
  }
}

final labelsProvider =
    StateNotifierProvider<LabelsController, LabelsState>(
        (ref) => LabelsController(ref.watch(sharedPrefsProvider)));

/// Active label filter in the inbox (null = no label filter).
final labelFilterProvider = StateProvider<String?>((_) => null);
