import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/core.dart';
import '../../services/media_library.dart';
import '../../services/speech_service.dart';

/// 发送参数 — 封装用户发送的内容
class SendPayload {
  /// 文本内容（可为空，如仅发送附件）
  final String text;

  /// 媒体附件列表
  final List<MediaAttachment> attachments;

  const SendPayload({this.text = '', this.attachments = const []});

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
}

/// 多模态消息输入栏
///
/// 布局：
/// ```
/// [文本输入框            ] [🎤] [+] [➤]
/// ```
///
/// - 🎤: 语音输入（Speech-to-Text）
/// - +: 弹出选择菜单（图片 / 相机 / 文件）
/// - ➤: 发送
class MessageInput extends StatefulWidget {
  final bool enabled;
  final ValueChanged<SendPayload> onSend;

  const MessageInput({super.key, this.enabled = true, required this.onSend});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _speechService = SpeechService();
  final _imagePicker = ImagePicker();
  final _mediaLibrary = MediaLibrary.instance;

  /// 本消息已附加的媒体
  final List<MediaAttachment> _attachments = [];

  bool _isListening = false;
  bool _sttAvailable = false;

  bool get _canSend =>
      _controller.text.trim().isNotEmpty || _attachments.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _checkStt();
  }

  Future<void> _checkStt() async {
    final available = await _speechService.isSttAvailable;
    if (mounted) setState(() => _sttAvailable = available);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _sttSub?.cancel();
    _speechService.dispose();
    super.dispose();
  }

  // ── 发送 ──

  void _handleSend() {
    if (!_canSend || !widget.enabled) return;

    final payload = SendPayload(
      text: _controller.text.trim(),
      attachments: List<MediaAttachment>.from(_attachments),
    );
    _controller.clear();
    _attachments.clear();
    _focusNode.requestFocus();
    widget.onSend(payload);
  }

  // ── 语音输入 ──

  StreamSubscription<String>? _sttSub;

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      _sttSub?.cancel();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);

    final stream = _speechService.startListening();
    _sttSub = stream.listen(
      (recognizedWords) {
        if (recognizedWords.isNotEmpty) {
          // 将识别的文字填到输入框末尾
          final current = _controller.text;
          _controller.text = current + recognizedWords;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
      },
      onError: (_) {
        setState(() => _isListening = false);
      },
      onDone: () {
        setState(() => _isListening = false);
      },
    );
  }

  // ── 附件 ──

  Future<void> _showAttachmentMenu() async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.image, color: theme.colorScheme.primary),
                  title: const Text('图片'),
                  subtitle: const Text('从相册选择图片'),
                  onTap: () => Navigator.pop(ctx, 1),
                ),
                ListTile(
                  leading: Icon(
                    Icons.camera_alt,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('相机'),
                  subtitle: const Text('使用相机拍摄'),
                  onTap: () => Navigator.pop(ctx, 2),
                ),
                ListTile(
                  leading: Icon(
                    Icons.attach_file,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('文件'),
                  subtitle: const Text('选择任意文件'),
                  onTap: () => Navigator.pop(ctx, 3),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;

    switch (result) {
      case 1:
        await _pickFromGallery();
        break;
      case 2:
        await _pickFromCamera();
        break;
      case 3:
        await _pickFile();
        break;
    }
  }

  Future<void> _pickFromGallery() async {
    final List<XFile> images = await _imagePicker.pickMultiImage();
    for (final img in images) {
      await _addAttachment(img.path);
    }
  }

  Future<void> _pickFromCamera() async {
    final img = await _imagePicker.pickImage(source: ImageSource.camera);
    if (img != null) {
      await _addAttachment(img.path);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      if (file.path != null) {
        await _addAttachment(file.path!);
      }
    }
  }

  Future<void> _addAttachment(String filePath) async {
    try {
      final attachment = await _mediaLibrary.importFile(filePath);
      setState(() => _attachments.add(attachment));
    } catch (e) {
      // ignore
      debugPrint("Error in adding attachment: $e");
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      final att = _attachments.removeAt(index);
      _mediaLibrary.remove(att.libraryId);
    });
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 附件预览条
          if (_attachments.isNotEmpty) _buildAttachmentBar(theme),
          // 主输入行
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 文本输入框
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              const SizedBox(width: 4),
              // 语音按钮
              if (_sttAvailable)
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    size: 20,
                  ),
                  color: _isListening ? theme.colorScheme.error : null,
                  tooltip: _isListening ? '停止录音' : '语音输入',
                  onPressed: _toggleListening,
                ),
              // 附件按钮
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: '添加附件',
                onPressed: _showAttachmentMenu,
              ),
              // 发送按钮
              IconButton.filled(
                onPressed: _canSend && widget.enabled ? _handleSend : null,
                icon: Icon(
                  widget.enabled ? Icons.send : Icons.hourglass_top,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentBar(ThemeData theme) {
    return Container(
      height: 68,
      margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, i2) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final att = _attachments[index];
          return _AttachmentChip(
            attachment: att,
            onRemove: () => _removeAttachment(index),
          );
        },
      ),
    );
  }
}

/// 附件缩略图 — 模仿主流 LLM 客户端 UI（圆角方形缩略图 + 角标关闭按钮）
class _AttachmentChip extends StatelessWidget {
  final MediaAttachment attachment;
  final VoidCallback onRemove;

  const _AttachmentChip({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lib = MediaLibrary.instance;
    final filePath = lib.filePathFor(attachment.libraryId);

    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 缩略图主体
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _buildThumb(lib, filePath, colorScheme),
            ),
          ),
          // 移除按钮 — 右上角略微溢出
          Positioned(
            top: -5,
            right: -5,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb(
    MediaLibrary lib,
    String? filePath,
    ColorScheme colorScheme,
  ) {
    if (attachment.isImage && filePath != null) {
      return Image.file(
        File(filePath),
        fit: BoxFit.cover,
        width: 58,
        height: 58,
        errorBuilder: (_, error, stack) =>
            Icon(Icons.broken_image, size: 24, color: colorScheme.outline),
      );
    }
    if (attachment.isVideo) {
      return Center(
        child: Icon(
          Icons.play_circle_fill,
          size: 28,
          color: colorScheme.tertiary,
        ),
      );
    }
    if (attachment.isAudio) {
      return Center(
        child: Icon(Icons.audio_file, size: 28, color: colorScheme.secondary),
      );
    }
    return Center(
      child: Icon(
        Icons.insert_drive_file,
        size: 28,
        color: colorScheme.outline,
      ),
    );
  }
}
