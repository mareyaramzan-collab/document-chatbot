import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String kChatEndpoint = 'http://127.0.0.1:8000/chat';


void main() => runApp(const ChatApp());

// ───────────────────────── App + Theme ─────────────────────────

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F6B63), // deep teal
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1412) : const Color(0xFFF4F6F4),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        foregroundColor: scheme.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Chatbot',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const ChatScreen(),
    );
  }
}

// ───────────────────────── Model ─────────────────────────

enum Sender { user, bot }

class ChatMessage {
  ChatMessage({
    required this.text,
    required this.sender,
    this.isError = false,
    this.retryQuestion,
  }) : time = DateTime.now();

  final String text;
  final Sender sender;
  final bool isError;
  final String? retryQuestion;
  final DateTime time;
}

// ───────────────────────── Screen ─────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _hasText = false;

  static const _suggestions = [
    'Summarize this document',
    'What are the key points?',
    'List any important dates or numbers',
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _isLoading) return;

    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(ChatMessage(text: question, sender: Sender.user));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToEnd();

    try {
      final response = await http
          .post(
            Uri.parse(kChatEndpoint),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'question': question}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final answer = (data['answer'] ?? '').toString().trim();
      _addBot(answer.isEmpty ? 'I couldn’t find an answer in the document.' : answer);
    }      catch (e) {
      _addBot(
        'Error: $e',
        isError: true,
        retryQuestion: question,
      );
    }
      
  }

  void _addBot(String text, {bool isError = false, String? retryQuestion}) {
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        sender: Sender.bot,
        isError: isError,
        retryQuestion: retryQuestion,
      ));
      _isLoading = false;
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Row(
          children: [
            const SizedBox(width: 16),
            _BotAvatar(size: 40, icon: Icons.menu_book_rounded),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Document Chatbot',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isLoading ? Colors.amber : const Color(0xFF2FB67C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isLoading ? 'Reading your document…' : 'Ready',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outlineVariant.withOpacity(.5)),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(
                      suggestions: _suggestions,
                      onPick: _send,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _messages.length) {
                          return const _TypingBubble();
                        }
                        final msg = _messages[i];
                        return _MessageRow(
                          key: ValueKey(msg.time.microsecondsSinceEpoch),
                          message: msg,
                          onRetry: msg.retryQuestion == null
                              ? null
                              : () => _send(msg.retryQuestion!),
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _controller,
              focusNode: _focus,
              canSend: _hasText && !_isLoading,
              onSend: () => _send(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Message UI ─────────────────────────

class _MessageRow extends StatelessWidget {
  const _MessageRow({super.key, required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.sender == Sender.user;
    final isError = message.isError;
    final isFresh = DateTime.now().difference(message.time).inMilliseconds < 700;

    final bubbleColor = isUser
        ? scheme.primary
        : isError
            ? scheme.errorContainer
            : scheme.surfaceContainerHigh;
    final textColor = isUser
        ? scheme.onPrimary
        : isError
            ? scheme.onErrorContainer
            : scheme.onSurface;

    final bubble = GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.text));
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Copied'),
            duration: Duration(seconds: 1),
          ));
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 20),
          ),
          border: isUser
              ? null
              : Border.all(color: scheme.outlineVariant.withOpacity(.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 15.5, height: 1.45),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 18, color: textColor),
                      const SizedBox(width: 6),
                      Text('Try again',
                          style: TextStyle(
                              color: textColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                const _BotAvatar(size: 28),
                const SizedBox(width: 8),
              ],
              Flexible(child: bubble),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: 4, left: isUser ? 0 : 36),
            child: Text(
              _time(message.time),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    if (!isFresh) return row;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: row,
    );
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar({required this.size, this.icon = Icons.auto_stories_rounded});

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer,
      ),
      child: Icon(icon, size: size * 0.5, color: scheme.onPrimaryContainer),
    );
  }
}

// ───────────────────────── Typing indicator ─────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _BotAvatar(size: 28),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border.all(color: scheme.outlineVariant.withOpacity(.45)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final phase = (_anim.value - i * 0.15) * 2 * math.pi;
                  final lift = (math.sin(phase) + 1) / 2; // 0..1
                  return Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 5, bottom: lift * 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withOpacity(.35 + lift * .55),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Empty state ─────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.suggestions, required this.onPick});

  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(Icons.menu_book_rounded,
                  size: 40, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              'Ask your document anything',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Get answers with the context already in the file. Type a question or start with one of these.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => onPick(s),
                    labelStyle: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    backgroundColor: scheme.surface,
                    side: BorderSide(color: scheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Composer ─────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.only(left: 18, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withOpacity(.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (canSend) onSend();
                    focusNode.requestFocus();
                  },
                  style: const TextStyle(fontSize: 16, height: 1.35),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Ask about the document',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: canSend ? scheme.primary : scheme.surfaceContainerHighest,
              ),
              child: IconButton(
                onPressed: canSend ? onSend : null,
                tooltip: 'Send',
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: canSend ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}