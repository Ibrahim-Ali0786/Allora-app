// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ChatScreen extends StatefulWidget {
  final Room room;
  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  late final Timeline _timeline;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initTimeline();
  }

  Future<void> _initTimeline() async {
    _timeline = await widget.room.getTimeline(onChange: (timeline) {
      if (mounted) setState(() {});
    });
    setState(() => _isLoading = false);
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    try {
      await widget.room.sendTextEvent(text);
    } catch (e) {
      debugPrint('Error sending message: $e');
      // In Enterprise, show a SnackBar or inline error here
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.room.avatar != null
                  ? NetworkImage(widget.room.avatar!
                      .getThumbnail(widget.room.client, width: 50, height: 50)
                      .toString())
                  : null,
              child: widget.room.avatar == null
                  ? Text(widget.room.displayname[0].toUpperCase())
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.room.displayname,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      reverse: true, // Start at bottom like WhatsApp/Beeper
                      itemCount: _timeline.events.length,
                      itemBuilder: (context, index) {
                        final event = _timeline.events[index];
                        if (event.type != EventTypes.Message) {
                          return const SizedBox.shrink();
                        }

                        final isMe =
                            event.senderId == widget.room.client.userID;
                        final body = event.content['body'] ?? '';

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                                color: isMe
                                    ? const Color(0xFF007AFF)
                                    : Colors.white,
                                borderRadius:
                                    BorderRadius.circular(18).copyWith(
                                  bottomRight:
                                      isMe ? const Radius.circular(4) : null,
                                  bottomLeft:
                                      !isMe ? const Radius.circular(4) : null,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1))
                                ]),
                            child: Text(
                              body,
                              style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontSize: 15),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF1F1F2),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF007AFF),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: _sendMessage,
            ),
          )
        ],
      ),
    );
  }
}
