import 'package:flutter/material.dart';

/// Canonical identifier for every supported network. Using an enum instead
/// of matching on raw display strings everywhere means the chat list, the
/// connect-networks screen, and the disconnect/wipe service can never
/// silently drift out of sync with each other again.
enum NetworkId { whatsapp, instagram, messenger, discord, x, slack, telegram }

class NetworkMeta {
  final NetworkId id;
  final String displayName;
  final String? asset; // brand glyph image (assets/images/...)
  final IconData? icon; // fallback glyph when there's no asset
  final Color brandColor;
  final String description;
  final bool available; // false = "coming soon", no bridge bot wired up yet

  /// The word used to find this network's bridge-bot management room, e.g.
  /// a room named "WhatsApp bridge bot" is found via the alias "whatsapp".
  /// Also doubles as the fragment expected inside the bot's own mxid
  /// (e.g. @whatsappbot:yourserver), which is the most reliable signal for
  /// classifying a *portal* room — it doesn't depend on room-naming
  /// conventions at all.
  final String botAlias;

  /// The short tag some bridges append to room names, e.g. "(WA)". Used as
  /// a fast secondary signal alongside the participant-mxid check.
  final String nameTag;

  /// Extra lowercase substrings (beyond the standard alias/tag rules) that
  /// always mean "this room belongs to this network" — e.g. WhatsApp's
  /// "status broadcast" room, which carries neither a "(WA)" tag nor the
  /// "_whatsapp_" room-id fragment. Add bridge-specific quirks here instead
  /// of hard-coding them into the classifier, so there's exactly one place
  /// that knows about them.
  final List<String> extraNameSignals;

  /// The `protocol.id` values a mautrix/matrix bridge advertises in its
  /// `m.bridge` (and `uk.half-shot.bridge`) room-state event. This is the
  /// single most reliable portal signal — it doesn't depend on room names,
  /// aliases or which members happen to be loaded. e.g. mautrix-whatsapp
  /// stamps `protocol: { id: "whatsapp" }` on every portal, groups included.
  final List<String> bridgeProtocols;

  /// Commands sent to the bridge management room to revoke the remote
  /// session, in order. mautrix bridges accept `logout`; bridgev2 builds
  /// also understand `logout all` for multi-login accounts. Platform
  /// services can override per-bridge quirks here.
  final List<String> logoutCommands;

  const NetworkMeta({
    required this.id,
    required this.displayName,
    required this.brandColor,
    required this.description,
    required this.botAlias,
    required this.nameTag,
    this.asset,
    this.icon,
    this.available = true,
    this.extraNameSignals = const [],
    this.bridgeProtocols = const [],
    this.logoutCommands = const ['logout', 'logout all'],
  });

  /// The bridge bot's own Matrix ID on [userDomain], e.g.
  /// "@whatsappbot:example.com". This is the single most reliable way to
  /// recognise the bot's 1:1 management room (the one you run `!wa login`,
  /// `!wa logout`, `list-logins` in): it doesn't depend on the bot's
  /// display name, which can be empty, stale, or just not what you expect
  /// while profiles are still loading.
  String botMxid(String userDomain) => '@${botAlias}bot:$userDomain';
}

/// Single source of truth for every network's branding + bridge-matching
/// rules. The "Connect networks" screen, the chat-list drawer, and the
/// room classifier all read from this list so they can't drift apart.
const List<NetworkMeta> kNetworks = [
  NetworkMeta(
    id: NetworkId.whatsapp,
    displayName: 'WhatsApp',
    asset: 'assets/images/whatsapp.png',
    brandColor: Color(0xFF25D366),
    description: 'Messages and media',
    botAlias: 'whatsapp',
    nameTag: 'wa',
    extraNameSignals: ['status broadcast'],
    bridgeProtocols: ['whatsapp'],
  ),
  NetworkMeta(
    id: NetworkId.instagram,
    displayName: 'Instagram',
    asset: 'assets/images/instagram.png',
    brandColor: Color(0xFFE1306C),
    description: 'Direct messages',
    botAlias: 'instagram',
    nameTag: 'ig',
    bridgeProtocols: ['instagram', 'instagramgo'],
  ),
  NetworkMeta(
    id: NetworkId.messenger,
    displayName: 'Messenger',
    asset: 'assets/images/messenger.png',
    brandColor: Color(0xFF006FFF),
    description: 'Facebook conversations',
    botAlias: 'messenger',
    nameTag: 'fb',
    bridgeProtocols: ['facebook', 'messenger', 'facebookgo'],
  ),
  NetworkMeta(
    id: NetworkId.discord,
    displayName: 'Discord',
    asset: 'assets/images/discord.png',
    brandColor: Color(0xFF5865F2),
    description: 'Servers and direct messages',
    botAlias: 'discord',
    nameTag: 'discord',
    bridgeProtocols: ['discord', 'discordgo'],
  ),
  NetworkMeta(
    id: NetworkId.x,
    displayName: 'X',
    asset: 'assets/images/x.png',
    brandColor: Color(0xFF14171A),
    description: 'Posts and direct messages',
    botAlias: 'twitter',
    nameTag: 'x',
    bridgeProtocols: ['twitter', 'x'],
  ),
  NetworkMeta(
    id: NetworkId.slack,
    displayName: 'Slack',
    asset: 'assets/images/slack.png',
    brandColor: Color(0xFFECB22E),
    description: 'Workspace channels',
    botAlias: 'slack',
    nameTag: 'slack',
    bridgeProtocols: ['slack', 'slackgo'],
  ),
  NetworkMeta(
    id: NetworkId.telegram,
    displayName: 'Telegram',
    icon: Icons.send_rounded,
    brandColor: Color(0xFF29A9EA),
    description: 'Cloud messaging',
    botAlias: 'telegram',
    nameTag: 'tg',
    available: true, // flip to true once the bridge actually ships
    bridgeProtocols: ['telegram'],
  ),
];

NetworkMeta metaFor(NetworkId id) => kNetworks.firstWhere((n) => n.id == id);

/// Maps a bridge's advertised `protocol.id` (from an `m.bridge` state event)
/// to the Allora network it belongs to, or null if unknown/ambiguous.
NetworkId? networkForBridgeProtocol(String protocolId) {
  final id = protocolId.toLowerCase().trim();
  for (final n in kNetworks) {
    if (n.bridgeProtocols.contains(id)) return n.id;
  }
  return null;
}
