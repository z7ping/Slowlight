import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ai/ai_provider.dart';
import '../ai/ai_service.dart';
import '../ai/xiaweis_context_store.dart';
import '../ai/xiaweis_service.dart';
import '../services/data_service.dart';
import '../ui/widgets/fx_page_header.dart';
import 'ai_settings_screen.dart';

/// Slowlight 的轻量个人 AI 入口。不会改变「今天 / 回顾」两条主线。
/// 首版对话仅在当前页面内存中存在；个人上下文由用户主动维护。
class XiaweisScreen extends StatefulWidget {
  const XiaweisScreen({super.key});

  @override
  State<XiaweisScreen> createState() => _XiaweisScreenState();
}

class _XiaweisScreenState extends State<XiaweisScreen> {
  final _ai = XiaweisService();
  final _store = XiaweisContextStore();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _history = [];

  String _personalContext = '';
  String? _error;
  bool _loadingProfile = true;
  bool _aiEnabled = false;
  bool _sending = false;
  bool _attachProfile = false;
  bool _attachTasks = false;
  bool _savedAnItem = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    String profile = '';
    String? error;
    bool enabled = false;
    try {
      profile = await _store.read();
    } catch (_) {
      error = '个人资料读取失败，请检查设备安全存储。';
    }
    try {
      enabled = await AiService().isEnabled();
    } catch (_) {
      error ??= 'AI 配置读取失败，请检查 AI 设置。';
    }
    if (!mounted) return;
    setState(() {
      _personalContext = profile;
      _aiEnabled = enabled;
      _loadingProfile = false;
      _error = error;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _editProfile() async {
    final controller = TextEditingController(text: _personalContext);
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('夏维斯 · 个人资料'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '可粘贴 my-lifeos 中的个人介绍或目标摘要，不必逐项填写。'
                '只保存在本设备；仅打开「引用我的资料」时才会发送给已配置的模型。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 10,
                maxLength: XiaweisContextStore.maxLength,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '职业背景、长期目标、沟通偏好……',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (submitted == null || !mounted) return;
    try {
      await _store.save(submitted);
      if (!mounted) return;
      setState(() {
        _personalContext = submitted.trim();
        if (_personalContext.isEmpty) _attachProfile = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('个人资料已保存到本设备')),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败；资料未更新。');
    }
  }

  Future<void> _openAiSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _sending || _loadingProfile) return;
    if (!_aiEnabled) {
      setState(() => _error = '请先在 AI 设置中启用并配置模型。');
      return;
    }
    _input.clear();
    setState(() {
      _history.add(AiMessage.user(question));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final response = await _ai.reply(
        history: List<AiMessage>.unmodifiable(_history),
        personalContext: _attachProfile ? _personalContext : '',
        includeTodayTasks: _attachTasks,
      );
      if (!mounted) return;
      setState(() => _history.add(AiMessage.assistant(response.text)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '发送失败：' + error.toString());
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  String _suggestTitle(String answer) {
    final first = answer.split('\n').map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final cleaned = first.replaceFirst(RegExp(r'^[#*>0-9.\-\s]+'), '').trim();
    if (cleaned.isEmpty) return '';
    return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
  }

  Future<void> _saveToInbox(String answer) async {
    final controller = TextEditingController(text: _suggestTitle(answer));
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存到 Slowlight 收集箱'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请将建议编辑成一条明确的待办事项。确认前不会写入任何任务。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 120,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '待办标题',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || !mounted) return;

    try {
      await DataService().quickAddToInbox(title);
      if (!mounted) return;
      setState(() => _savedAnItem = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到 Slowlight 收集箱')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = '收集箱保存失败：' + error.toString());
      }
    }
  }

  Widget _welcome() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 22, 10, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.sparkles, size: 27, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('我是夏维斯', style: theme.textTheme.titleLarge),
          const SizedBox(height: 5),
          const Text('可以聊目标、回顾、选择和行动。先说问题，不需要学习命令。'),
          const SizedBox(height: 12),
          Text(
            _personalContext.isEmpty
                ? '个人资料尚未设置；你可以随时添加。'
                : '个人资料已保存，是否引用由你决定。',
            style: theme.textTheme.bodySmall,
          ),
          if (!_aiEnabled && !_loadingProfile) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openAiSettings,
              child: const Text('先配置 AI 模型'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bubble(AiMessage message) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);
    final background = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLow;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 650),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: SelectableText(message.content),
              ),
            ),
            if (!isUser)
              TextButton.icon(
                onPressed: () => _saveToInbox(message.content),
                icon: const Icon(LucideIcons.listPlus, size: 16),
                label: const Text('存为行动项'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('引用我的资料'),
                selected: _attachProfile,
                onSelected: (selected) {
                  if (selected && _personalContext.isEmpty) {
                    _editProfile();
                    return;
                  }
                  setState(() => _attachProfile = selected);
                },
              ),
              FilterChip(
                label: const Text('引用今天任务'),
                selected: _attachTasks,
                onSelected: (value) => setState(() => _attachTasks = value),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: '和夏维斯聊聊…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '发送',
                onPressed: _sending || !_aiEnabled ? null : _send,
                icon: const Icon(LucideIcons.arrowUp),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '仅勾选的资料会发送给当前 AI 模型；对话关闭后不保留。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '夏维斯',
              onBack: () => Navigator.pop(context, _savedAnItem),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '个人资料',
                    onPressed: _editProfile,
                    icon: const Icon(LucideIcons.userRound, size: 20),
                  ),
                  IconButton(
                    tooltip: 'AI 设置',
                    onPressed: _openAiSettings,
                    icon: const Icon(LucideIcons.settings2, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _history.length + 1 + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == 0) return _welcome();
                      if (index <= _history.length) {
                        return _bubble(_history[index - 1]);
                      }
                      return const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text('夏维斯正在回复…'),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: _composer(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
