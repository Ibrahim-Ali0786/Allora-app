import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

class _EmojiCategory {
  final String name;
  final IconData icon;
  final List<String> emojis;
  const _EmojiCategory(this.name, this.icon, this.emojis);
}

const _categories = <_EmojiCategory>[
  _EmojiCategory('Smileys', Icons.emoji_emotions_outlined, [
    '😀','😃','😄','😁','😆','😅','😂','🤣','🥲','😊','😇','🙂','😉','😌',
    '😍','🥰','😘','😗','😋','😛','🤪','😝','🤑','🤗','🤭','🤫','🤔','🫡',
    '😐','😑','😶','😏','😒','🙄','😬','😮‍💨','🤥','😌','😔','😪','🤤','😴',
    '😷','🤒','🤕','🤢','🤮','🥵','🥶','😵','🤯','🥳','😎','🤓','🧐','😕',
    '😟','🙁','😮','😯','😲','😳','🥺','😦','😨','😰','😥','😢','😭','😱',
    '😖','😣','😞','😓','😩','😫','🥱','😤','😡','😠','🤬','💀','💩','🤡',
  ]),
  _EmojiCategory('Gestures', Icons.waving_hand_outlined, [
    '👋','🤚','✋','🖖','👌','🤌','🤏','✌️','🤞','🫰','🤟','🤘','🤙','👈',
    '👉','👆','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','🫶','👐',
    '🤲','🤝','🙏','💪','🦾','✍️','💅','🤳','💋','🫂','👀','🧠','❣️','💯',
  ]),
  _EmojiCategory('Hearts', Icons.favorite_outline, [
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❤️‍🔥','❤️‍🩹','💕',
    '💞','💓','💗','💖','💘','💝','💟','♥️','💌','😻','🥰','😍','💑','💏',
  ]),
  _EmojiCategory('Animals', Icons.pets_outlined, [
    '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸',
    '🐵','🐔','🐧','🐦','🦆','🦅','🦉','🐺','🐗','🐴','🦄','🐝','🦋','🐢',
    '🐍','🦖','🐙','🦀','🐠','🐬','🐳','🦈','🐊','🐘','🦒','🐪','🦩','🦜',
  ]),
  _EmojiCategory('Food', Icons.restaurant_outlined, [
    '🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭',
    '🍍','🥥','🥝','🍅','🥑','🥦','🌽','🥕','🍞','🥐','🥨','🧀','🍳','🥞',
    '🧇','🍗','🍔','🍟','🍕','🌭','🥪','🌮','🌯','🍜','🍣','🍤','🍦','🍩',
    '🍪','🎂','🍰','🧁','🍫','🍿','☕','🍵','🧋','🥤','🍺','🍷','🥂','🍾',
  ]),
  _EmojiCategory('Activity', Icons.sports_soccer_outlined, [
    '⚽','🏀','🏈','⚾','🎾','🏐','🏉','🎱','🏓','🏸','🥅','⛳','🏹','🎣',
    '🥊','🥋','🎽','⛸️','🛹','🎿','🏂','🏋️','🤸','⛹️','🤺','🤾','🏌️','🏇',
    '🧘','🏄','🏊','🤽','🚴','🚵','🎯','🎮','🎲','🧩','🎸','🥁','🎤','🎧',
  ]),
  _EmojiCategory('Objects', Icons.lightbulb_outline, [
    '⌚','📱','💻','⌨️','🖥️','🖨️','🖱️','💽','💾','💿','📷','🎥','📞','📟',
    '📺','🧭','⏰','⏳','📡','🔋','🔌','💡','🔦','🕯️','💸','💵','💳','💎',
    '🔧','🔨','⚙️','🧲','🔫','💣','🔪','🛡️','🚬','⚰️','🔮','🧿','💈','🔭',
  ]),
  _EmojiCategory('Symbols', Icons.tag, [
    '✅','❌','❓','❗','💤','🎉','🎊','🎈','🎁','🏆','🥇','🥈','🥉','⭐',
    '🌟','✨','⚡','🔥','💥','☀️','🌙','🌈','☁️','❄️','💧','🌊','♻️','⚠️',
    '🚫','💢','🔞','📵','🆗','🆒','🆕','🆓','🔴','🟠','🟡','🟢','🔵','🟣',
  ]),
];

/// Compact, dependency-free emoji picker with a persisted "Recents" row.
/// Returns the chosen emoji, or null when dismissed.
Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _EmojiPickerSheet(),
  );
}

class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet();

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  static const _recentsKey = 'allora_recent_emojis_v1';
  int _tab = 0;
  List<String> _recents = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recents = prefs.getStringList(_recentsKey) ?? []);
  }

  Future<void> _pick(String emoji) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [emoji, ..._recents.where((e) => e != emoji)];
    await prefs.setStringList(_recentsKey, next.take(24).toList());
    if (mounted) Navigator.pop(context, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final showRecents = _recents.isNotEmpty;
    final emojis = _tab == 0 && showRecents
        ? _recents
        : _categories[showRecents ? _tab - 1 : _tab].emojis;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.45,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (showRecents)
                  _tabButton(0, Icons.history_rounded, 'Recent'),
                for (var i = 0; i < _categories.length; i++)
                  _tabButton(showRecents ? i + 1 : i, _categories[i].icon,
                      _categories[i].name),
              ],
            ),
          ),
          Divider(color: c.outline),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8),
              itemCount: emojis.length,
              itemBuilder: (context, i) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pick(emojis[i]),
                child: Center(
                  child: Text(emojis[i], style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String tooltip) {
    final c = context.allora;
    final selected = _tab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        onPressed: () => setState(() => _tab = index),
        icon: Icon(icon, size: 21, color: selected ? c.accent : c.textTertiary),
        style: IconButton.styleFrom(
          backgroundColor:
              selected ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
        ),
      ),
    );
  }
}
