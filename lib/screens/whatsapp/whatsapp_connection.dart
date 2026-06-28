// ignore_for_file: unnecessary_non_null_assertion, unused_element, curly_braces_in_flow_control_structures, unused_import, unnecessary_string_interpolations, use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import 'whatsapp_disconnect_service.dart';
import '../networks/network_connection_cache.dart';
import '../bridge/bridge_room_classifier.dart';
import 'package:http/http.dart' as http;
import '../networks/network_meta.dart';

// ─── BRAND COLORS ────────────────────────────────────────────────────────────
const Color kBeeperBlue = Color(0xFF0052FF);
const Color kWaGreen = Color(0xFF25D366);

// ─── COUNTRY LIST ─────────────────────────────────────────────────────────────
final List<Map<String, String>> _allCountries = [
  {"name": "Australia", "code": "+61", "flag": "🇦🇺"},
  {"name": "Brazil", "code": "+55", "flag": "🇧🇷"},
  {"name": "Canada", "code": "+1", "flag": "🇨🇦"},
  {"name": "France", "code": "+33", "flag": "🇫🇷"},
  {"name": "Germany", "code": "+49", "flag": "🇩🇪"},
  {"name": "India", "code": "+91", "flag": "🇮🇳"},
  {"name": "Indonesia", "code": "+62", "flag": "🇮🇩"},
  {"name": "Italy", "code": "+39", "flag": "🇮🇹"},
  {"name": "Mexico", "code": "+52", "flag": "🇲🇽"},
  {"name": "Nigeria", "code": "+234", "flag": "🇳🇬"},
  {"name": "Pakistan", "code": "+92", "flag": "🇵🇰"},
  {"name": "Philippines", "code": "+63", "flag": "🇵🇭"},
  {"name": "South Africa", "code": "+27", "flag": "🇿🇦"},
  {"name": "United Arab Emirates", "code": "+971", "flag": "🇦🇪"},
  {"name": "United Kingdom", "code": "+44", "flag": "🇬🇧"},
  {"name": "United States", "code": "+1", "flag": "🇺🇸"},
];

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────
void showWhatsAppConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onPairingCodeReceived,
  VoidCallback? onConnected,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => WhatsAppConnectSheet(
      client: client,
      onPairingCodeReceived: onPairingCodeReceived,
      onConnected: onConnected,
    ),
  );
}

// ─── THE CONNECT SHEET ────────────────────────────────────────────────────────
class WhatsAppConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onPairingCodeReceived;
  final VoidCallback? onConnected;

  const WhatsAppConnectSheet({
    super.key,
    required this.client,
    this.onPairingCodeReceived,
    this.onConnected,
  });

  @override
  State<WhatsAppConnectSheet> createState() => _WhatsAppConnectSheetState();
}

class _WhatsAppConnectSheetState extends State<WhatsAppConnectSheet> {
  final TextEditingController _phoneController = TextEditingController();

  StreamSubscription<Event>? _activeSub;

  bool _sheetLoading = false;
  String? _sheetError;
  String? _generatedPairingCode;

  // New state flag for the success screen
  bool _isConnected = false;

  String _selectedCountryCode = "+91";
  String _selectedCountryFlag = "🇮🇳";

  @override
  void dispose() {
    _phoneController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  // ─── PIPELINE ──────────────────────────────────────────────────────
  Future<void> _executeUnifiedPipeline() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final rawNumber = _phoneController.text.trim();
    if (rawNumber.isEmpty || rawNumber.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid phone number.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _sheetError = null;
      _sheetLoading = true;
      _generatedPairingCode = null;
      _isConnected = false;
    });

    try {
      Room? activeRoom;

      for (final room in widget.client.rooms) {
        if (WhatsAppDisconnectService.isManagementRoom(room)) {
          activeRoom = room;
          break;
        }
      }

      if (activeRoom == null) {
        try {
          final userDomain = widget.client.userID!.split(':').last;
          final botMxid = '@whatsappbot:$userDomain';

          final roomId = await widget.client.createRoom(
            invite: [botMxid],
            isDirect: true,
            preset: CreateRoomPreset.trustedPrivateChat,
          );

          int retries = 0;
          while (activeRoom == null && retries < 10) {
            await Future.delayed(const Duration(milliseconds: 500));
            activeRoom = widget.client.getRoomById(roomId);
            retries++;
          }

          if (activeRoom == null) throw Exception();
        } catch (e) {
          setState(() {
            _sheetError =
                "Could not find or create WhatsApp bridge room. Ensure the bridge is running.";
            _sheetLoading = false;
          });
          return;
        }
      }

      String cleanInput = rawNumber.replaceAll(RegExp(r'[^\d]'), '');
      String codeOnly = _selectedCountryCode.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanInput.startsWith(codeOnly) && cleanInput.length > 10) {
        cleanInput = cleanInput.substring(codeOnly.length);
      }
      final sanitizedNumber = '+$codeOnly$cleanInput';

      _activeSub?.cancel();
      _activeSub = widget.client.onTimelineEvent.stream.listen((Event event) {
        if (event.roomId != activeRoom!.id ||
            event.senderId == widget.client.userID) return;

        final body = (event.content['body'] as String? ?? '').trim();
        if (body.isEmpty) return;

        final lower = body.toLowerCase();

        // 🟢 INSTANT SUCCESS CHECK
        if (lower.contains('logged in') || lower.contains('connected')) {
          HapticFeedback.heavyImpact();
          _activeSub?.cancel();

          if (mounted) {
            // ── STEP 1: Update connection state immediately ──────────────────
            _handleSuccessfulConnection();
          }
          return;
        }

        // 🔵 PAIRING CODE CHECK
        final codeMatch =
            RegExp(r'\b([A-Z0-9]{4}[- ]?[A-Z0-9]{4})\b').firstMatch(body);
        if (codeMatch != null) {
          String rawCode = codeMatch.group(0)!.replaceAll(RegExp(r'[- ]'), '');
          if (rawCode.length == 8) {
            HapticFeedback.mediumImpact();
            setState(() {
              _generatedPairingCode =
                  '${rawCode.substring(0, 4)}-${rawCode.substring(4)}';
              _sheetLoading = false;
            });
            widget.onPairingCodeReceived?.call();
          }
        }

        // 🔴 ERROR CHECK
        if (lower.contains('timeout') ||
            lower.contains('invalid') ||
            lower.contains('error')) {
          HapticFeedback.heavyImpact();
          setState(() {
            _sheetError = "Login failed: $body";
            _sheetLoading = false;
            _generatedPairingCode = null;
          });
        }
      });

      Future.delayed(const Duration(seconds: 45), () {
        if (mounted &&
            _sheetLoading &&
            _generatedPairingCode == null &&
            !_isConnected) {
          setState(() {
            _sheetError = "Timed out waiting for pairing code from the server.";
            _sheetLoading = false;
          });
        }
      });

      await activeRoom.sendTextEvent('!wa cancel');
      await Future.delayed(const Duration(seconds: 1));
      await activeRoom.sendTextEvent('!wa login phone $sanitizedNumber');
    } catch (e) {
      setState(() {
        _sheetLoading = false;
        _sheetError =
            "An unexpected connection error occurred. Please try again.";
      });
    }
  }

  // ─── SUCCESS HANDLER ──────────────────────────────────────────────────────

  Future<void> _handleSuccessfulConnection() async {
    try {
      // ──────────────────────────────────────────────────────────────────────
      // STEP 1: Update UI immediately (show success screen)
      // ──────────────────────────────────────────────────────────────────────
      setState(() {
        _isConnected = true;
        _sheetLoading = false;
        _generatedPairingCode = null;
      });

      // ──────────────────────────────────────────────────────────────────────
      // STEP 2: Update NetworkConnectionCache immediately (button state)
      // ──────────────────────────────────────────────────────────────────────
      await NetworkConnectionCache.markConnected(
        NetworkId.whatsapp,
        force: true,
        accountLabel: 'Connected',
        lastSynced: 'Syncing',
      );
      debugPrint('✅ WhatsApp marked as connected in cache');

      // ──────────────────────────────────────────────────────────────────────
      // STEP 3: Clear classifier cache for fresh room identification
      // ──────────────────────────────────────────────────────────────────────
      BridgeRoomClassifier.clearCache();
      debugPrint('✅ Classifier cache cleared');

      // ──────────────────────────────────────────────────────────────────────
      // STEP 4: Trigger Matrix sync to fetch new WhatsApp rooms
      // ──────────────────────────────────────────────────────────────────────
      _triggerMatrixSync();

      // ──────────────────────────────────────────────────────────────────────
      // STEP 5: Notify Matrix server of connection event
      // ──────────────────────────────────────────────────────────────────────
      _notifyMatrixServerOfConnection();

      // ──────────────────────────────────────────────────────────────────────
      // STEP 6: Call parent callback for UI refresh
      // ──────────────────────────────────────────────────────────────────────
      widget.onConnected?.call();

      // ──────────────────────────────────────────────────────────────────────
      // STEP 7: Wait briefly for success animation, then auto-close sheet
      // ──────────────────────────────────────────────────────────────────────
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Error in success handler: $e');
      if (mounted) {
        setState(() {
          _sheetError = 'An error occurred. Please check your connection.';
          _sheetLoading = false;
        });
      }
    }
  }

  Future<void> _triggerMatrixSync() async {
    try {
      // Start a fresh sync to fetch new WhatsApp rooms from Matrix
      // without blocking the UI. Use syncUpdate() if available, or
      // trigger a full sync in the background.
      unawaited(
        Future.delayed(
          const Duration(milliseconds: 500),
          () => widget.client.sync(),
        ),
      );
      debugPrint('📡 Matrix sync triggered to fetch new rooms');
    } catch (e) {
      debugPrint('⚠️  Could not trigger sync: $e');
    }
  }

  Future<void> _notifyMatrixServerOfConnection() async {
    try {
      // Optional: send webhook/event to Matrix server or backend
      // This can be used for logging, analytics, or triggering additional setup
      final userId = widget.client.userID;
      if (userId != null) {
        debugPrint('📤 WhatsApp connection event for $userId');
        // Could send to a webhook:
        // await http.post(Uri.parse('https://your-backend.com/api/platform-connected'),
        //   headers: {'Content-Type': 'application/json'},
        //   body: jsonEncode({'user': userId, 'platform': 'whatsapp', 'timestamp': DateTime.now().toIso8601String()}),
        // );
      }
    } catch (e) {
      debugPrint('⚠️  Could not notify Matrix server: $e');
      // Non-fatal error, continue anyway
    }
  }

  // ─── UI HELPERS ───────────────────────────────────────────────────────────

  Widget _buildTopDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildTopRightCloseButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {
          _activeSub?.cancel();
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.grey.shade200, shape: BoxShape.circle),
          child:
              const Icon(Icons.close_rounded, color: Colors.black87, size: 16),
        ),
      ),
    );
  }

  Widget _buildConnectionIconsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: const Color(0xFF0052FF),
              borderRadius: BorderRadius.circular(16)),
          child:
              Image.asset('assets/images/app_icon.png', width: 56, height: 56),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Icon(Icons.sync_alt_rounded, color: Colors.grey, size: 32),
        ),
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: kWaGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16)),
          child:
              Image.asset('assets/images/whatsapp.png', width: 44, height: 44),
        ),
      ],
    );
  }

  Widget _buildPillButton(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0),
      child: Text(label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
    );
  }

  Widget _buildInstructionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(
          style: GoogleFonts.inter(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.8),
          children: [
            const TextSpan(text: '1. Open WhatsApp and tap '),
            const WidgetSpan(
                child: Icon(Icons.more_vert_rounded,
                    size: 16, color: Colors.black87),
                alignment: PlaceholderAlignment.middle),
            const TextSpan(text: ' in the top right\n'),
            const TextSpan(text: '2. Tap: '),
            const TextSpan(
                text: '"Linked devices"\n', style: TextStyle(color: kWaGreen)),
            const TextSpan(text: '3. Select: '),
            const TextSpan(
                text: '"Link a device"\n', style: TextStyle(color: kWaGreen)),
            const TextSpan(text: '4. Tap: '),
            const TextSpan(
                text: '"Link with phone number instead"\n',
                style: TextStyle(color: kWaGreen)),
            const TextSpan(text: '5. Paste the code below'),
          ],
        ),
      ),
    );
  }

  Future<Map<String, String>?> _showCountryPicker() {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(builder: (ctx, setModalState) {
          final filtered = _allCountries
              .where((c) =>
                  c['name']!.toLowerCase().contains(query.toLowerCase()) ||
                  c['code']!.contains(query))
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: TextField(
                    onChanged: (v) => setModalState(() => query = v),
                    style: GoogleFonts.inter(color: Colors.black87),
                    decoration: InputDecoration(
                        hintText: 'Search country...',
                        hintStyle: GoogleFonts.inter(color: Colors.grey),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => ListTile(
                      leading: Text(filtered[i]['flag']!,
                          style: const TextStyle(fontSize: 22)),
                      title: Text(filtered[i]['name']!,
                          style: GoogleFonts.inter(color: Colors.black87)),
                      trailing: Text(filtered[i]['code']!,
                          style: GoogleFonts.inter(color: Colors.grey)),
                      onTap: () => Navigator.pop(ctx, filtered[i]),
                    ),
                  ),
                )
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
          color: Color(0xFFFAFAFA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopDragHandle(),
            _buildTopRightCloseButton(),

            // Do not show connection header if we are on the success screen
            if (!_isConnected) ...[
              const SizedBox(height: 12),
              _buildConnectionIconsHeader(),
              const SizedBox(height: 32),
            ],

            // 🟢 SUCCESS STATE
            if (_isConnected) ...[
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    // Large WhatsApp Icon inside a success halo
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: kWaGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: kWaGreen.withOpacity(0.3), width: 2),
                      ),
                      child: Center(
                        child: Image.asset('assets/images/whatsapp.png',
                            width: 48, height: 48),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Connected',
                        style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 8),
                    Text('Your WhatsApp chats are now syncing.',
                        style: GoogleFonts.inter(
                            fontSize: 15, color: Colors.grey.shade600)),
                    const SizedBox(height: 48),
                    _buildPillButton("Done", () => Navigator.pop(context)),
                  ],
                ),
              ),
            ]

            // 🔴 ERROR STATE
            else if (_sheetError != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: Colors.red.shade400),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_sheetError!,
                          style: GoogleFonts.inter(
                              color: Colors.red.shade800,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildPillButton(
                  "Try Again", () => setState(() => _sheetError = null)),
            ]

            // ⏳ LOADING STATE (Now properly centered)
            else if (_sheetLoading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: ServerRadarAnimation(),
                ),
              ),
              Center(
                child: Text('Requesting pairing code from server...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        color: Colors.grey.shade600, fontSize: 14)),
              ),
              const SizedBox(height: 24),
            ]

            // 🔑 PAIRING CODE GENERATED
            else if (_generatedPairingCode != null) ...[
              Text('Link Device',
                  style: GoogleFonts.inter(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Enter this code in WhatsApp to link your device.',
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 24),
              _buildInstructionCard(),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(
                      ClipboardData(text: _generatedPairingCode!));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied!')));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: kWaGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kWaGreen.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_generatedPairingCode!,
                          style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                              color: kWaGreen)),
                      const SizedBox(width: 12),
                      Icon(Icons.copy_rounded,
                          color: kWaGreen.withOpacity(0.8), size: 24),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Waiting for you to enter the code…',
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
              const SizedBox(height: 32),
            ]

            // ⚪ INITIAL INPUT STATE
            else ...[
              Text('Connect WhatsApp',
                  style: GoogleFonts.inter(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Enter your phone number to receive a secure pairing code.',
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 24),
              Text('Phone Number',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final res = await _showCountryPicker();
                        if (res != null) {
                          setState(() {
                            _selectedCountryCode = res['code']!;
                            _selectedCountryFlag = res['flag']!;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                            border: Border(
                                right:
                                    BorderSide(color: Colors.grey.shade300))),
                        child: Text(
                            '$_selectedCountryFlag $_selectedCountryCode ▾',
                            style: GoogleFonts.inter(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        style: GoogleFonts.inter(
                            color: Colors.black87, fontSize: 16),
                        decoration: InputDecoration(
                            hintText: 'Enter number',
                            hintStyle:
                                GoogleFonts.inter(color: Colors.grey.shade400),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildPillButton("Continue", _executeUnifiedPipeline),
            ]
          ],
        ),
      ),
    );
  }
}

// ─── RADAR ANIMATION ─────────────────────────────────────────────────────────
class ServerRadarAnimation extends StatefulWidget {
  const ServerRadarAnimation({super.key});

  @override
  State<ServerRadarAnimation> createState() => _ServerRadarAnimationState();
}

class _ServerRadarAnimationState extends State<ServerRadarAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      width: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double value = (_controller.value + (index / 3)) % 1.0;
                return Opacity(
                  opacity: (1.0 - value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1.0 + (value * 2.5),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF25D366).withOpacity(0.5),
                              width: 2)),
                    ),
                  ),
                );
              },
            );
          }),
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            child: Image.asset('assets/images/whatsapp.png',
                width: 44, height: 44),
          ),
        ],
      ),
    );
  }
}
