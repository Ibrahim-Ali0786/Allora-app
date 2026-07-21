// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:pinput/pinput.dart';

import '../networks/network_connection_cache.dart';
import '../networks/network_meta.dart';
import '../bridge/bridge_room_classifier.dart';

// ─── BRAND COLORS ────────────────────────────────────────────────────────────
const Color kTelegramBlue = Color(0xFF29A9EA);

final List<Map<String, String>> _allCountries = [
  {"name": "Australia", "code": "+61", "flag": "🇦🇺"},
  {"name": "Brazil", "code": "+55", "flag": "🇧🇷"},
  {"name": "Canada", "code": "+1", "flag": "🇨🇦"},
  {"name": "France", "code": "+33", "flag": "🇫🇷"},
  {"name": "Germany", "code": "+49", "flag": "🇩🇪"},
  {"name": "India", "code": "+91", "flag": "🇮🇳"},
  {"name": "United States", "code": "+1", "flag": "🇺🇸"},
];

enum TelegramStep { phone, loading, code, password, success }

void showTelegramConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onConnected,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => TelegramConnectSheet(
      client: client,
      onConnected: onConnected,
    ),
  );
}

class TelegramConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onConnected;

  const TelegramConnectSheet({
    super.key,
    required this.client,
    this.onConnected,
  });

  @override
  State<TelegramConnectSheet> createState() => _TelegramConnectSheetState();
}

class _TelegramConnectSheetState extends State<TelegramConnectSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  StreamSubscription<Event>? _activeSub;
  Room? _botRoom;

  TelegramStep _currentStep = TelegramStep.phone;
  String? _sheetError;
  String _loadingMessage = 'Connecting to Telegram...';
  String _selectedCountryCode = "+91";
  String _selectedCountryFlag = "🇮🇳";

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureBotRoom() async {
    if (_botRoom != null) return;
    for (final room in widget.client.rooms) {
      if (room.displayname.toLowerCase().contains('telegram') ||
          (room.directChatMatrixID ?? '').contains('telegram')) {
        _botRoom = room;
        break;
      }
    }
    if (_botRoom == null) {
      final userDomain = widget.client.userID!.split(':').last;
      final botMxid = '@telegrambot:$userDomain';
      final roomId = await widget.client.createRoom(
        invite: [botMxid],
        isDirect: true,
        preset: CreateRoomPreset.trustedPrivateChat,
      );
      int retries = 0;
      while (_botRoom == null && retries < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        _botRoom = widget.client.getRoomById(roomId);
        retries++;
      }
      if (_botRoom == null) {
        throw Exception("Could not connect to Telegram Bridge.");
      }
    }
  }

  void _listenToBot() {
    _activeSub?.cancel();
    _activeSub = widget.client.onTimelineEvent.stream.listen((Event event) {
      if (_botRoom == null ||
          event.roomId != _botRoom!.id ||
          event.senderId == widget.client.userID) {
        return;
      }

      final body =
          (event.content['body'] as String? ?? '').trim().toLowerCase();
      if (body.isEmpty) return;

      if (body.contains('logged in') || body.contains('success')) {
        HapticFeedback.heavyImpact();
        _handleSuccessfulConnection();
        return;
      }
      if (body.contains('code')) {
        HapticFeedback.mediumImpact();
        setState(() {
          _currentStep = TelegramStep.code;
          _sheetError = null;
        });
        return;
      }
      if (body.contains('password') || body.contains('2fa')) {
        HapticFeedback.mediumImpact();
        setState(() {
          _currentStep = TelegramStep.password;
          _sheetError = null;
        });
        return;
      }
      if (body.contains('invalid') ||
          body.contains('error') ||
          body.contains('fail') ||
          body.contains('incorrect')) {
        HapticFeedback.heavyImpact();
        setState(() {
          _sheetError = event.content['body'] as String?;
          if (_currentStep == TelegramStep.loading) {
            _currentStep = TelegramStep.phone;
          }
        });
      }
    });
  }

  Future<void> _submitPhone() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final rawNumber = _phoneController.text.trim();
    if (rawNumber.isEmpty) return;

    setState(() {
      _sheetError = null;
      _currentStep = TelegramStep.loading;
      _loadingMessage = 'Requesting login code...';
    });

    try {
      await _ensureBotRoom();
      _listenToBot();

      String cleanInput = rawNumber.replaceAll(RegExp(r'[^\d]'), '');
      String codeOnly = _selectedCountryCode.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanInput.startsWith(codeOnly) && cleanInput.length > 10) {
        cleanInput = cleanInput.substring(codeOnly.length);
      }
      final sanitizedNumber = '+$codeOnly$cleanInput';

      await _botRoom!.sendTextEvent('login phone $sanitizedNumber');
    } catch (e) {
      setState(() {
        _currentStep = TelegramStep.phone;
        _sheetError = "Failed to communicate with the server.";
      });
    }
  }

  Future<void> _submitCode(String code) async {
    setState(() {
      _sheetError = null;
      _currentStep = TelegramStep.loading;
      _loadingMessage = 'Verifying code...';
    });
    await _botRoom?.sendTextEvent(code);
  }

  Future<void> _submitPassword() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final pw = _passwordController.text.trim();
    if (pw.isEmpty) return;

    setState(() {
      _sheetError = null;
      _currentStep = TelegramStep.loading;
      _loadingMessage = 'Verifying password...';
    });
    await _botRoom?.sendTextEvent(pw);
  }

  Future<void> _handleSuccessfulConnection() async {
    _activeSub?.cancel();
    setState(() {
      _currentStep = TelegramStep.success;
      _sheetError = null;
    });

    await NetworkConnectionCache.markConnected(
      NetworkId.telegram,
      force: true,
      accountLabel: 'Connected',
      lastSynced: 'Syncing',
    );
    BridgeRoomClassifier.clearCache();

    unawaited(widget.client.sync());
    widget.onConnected?.call();

    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.pop(context);
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

  Widget _buildTopDragHandle() => Center(
        child: Container(
          width: 40,
          height: 5,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10)),
        ),
      );

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

  @override
  Widget build(BuildContext context) {
    // FIXED: Safely configured the Pinput theme manually to avoid older version copyWith errors
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 64,
      textStyle: GoogleFonts.inter(
          fontSize: 24, color: Colors.black87, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white),
    );

    final focusedPinTheme = PinTheme(
      width: 56,
      height: 64,
      textStyle: GoogleFonts.inter(
          fontSize: 24, color: Colors.black87, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
          border: Border.all(color: kTelegramBlue, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white),
    );

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
            Align(
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
                  child: const Icon(Icons.close_rounded,
                      color: Colors.black87, size: 16),
                ),
              ),
            ),
            if (_currentStep != TelegramStep.success) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: const Color(0xFF0052FF),
                        borderRadius: BorderRadius.circular(16)),
                    child: Image.asset('assets/images/app_icon.png',
                        width: 56, height: 56),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Icon(Icons.sync_alt_rounded,
                        color: Colors.grey, size: 32),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: kTelegramBlue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.send_rounded,
                        color: kTelegramBlue, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
            if (_sheetError != null) ...[
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
                                fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_currentStep == TelegramStep.success) ...[
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                          color: kTelegramBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: kTelegramBlue.withOpacity(0.3), width: 2)),
                      child: const Center(
                          child: Icon(Icons.send_rounded,
                              color: kTelegramBlue, size: 40)),
                    ),
                    const SizedBox(height: 24),
                    Text('Connected',
                        style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 8),
                    Text('Your Telegram chats are now syncing.',
                        style: GoogleFonts.inter(
                            fontSize: 15, color: Colors.grey.shade600)),
                    const SizedBox(height: 48),
                    _buildPillButton("Done", () => Navigator.pop(context)),
                  ],
                ),
              ),
            ] else if (_currentStep == TelegramStep.loading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: CircularProgressIndicator(color: kTelegramBlue),
                ),
              ),
              Center(
                  child: Text(_loadingMessage,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: Colors.grey.shade600, fontSize: 14))),
              const SizedBox(height: 24),
            ] else if (_currentStep == TelegramStep.code) ...[
              Text('Enter Code',
                  style: GoogleFonts.inter(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Enter the 5-digit code sent to your Telegram app.',
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 32),
              Center(
                child: Pinput(
                  length: 5,
                  autofocus: true,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  onCompleted: _submitCode,
                ),
              ),
              const SizedBox(height: 32),
            ] else if (_currentStep == TelegramStep.password) ...[
              Text('Two-Step Verification',
                  style: GoogleFonts.inter(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Enter your Telegram 2FA password.',
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.black87, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Password',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: kTelegramBlue, width: 2)),
                ),
              ),
              const SizedBox(height: 32),
              _buildPillButton("Submit", _submitPassword),
            ] else ...[
              Text('Connect Telegram',
                  style: GoogleFonts.inter(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Enter your phone number to log in via Telegram.',
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
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildPillButton("Continue", _submitPhone),
            ]
          ],
        ),
      ),
    );
  }
}
