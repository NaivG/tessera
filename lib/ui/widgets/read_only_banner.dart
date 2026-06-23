import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';

/// 当用户在一个非运行中的对话上查看时,显示此条幅提示。
///
/// 触发条件:`runningConversationId != null && conversation.id != runningConversationId`。
/// 即用户已切走到另一个对话,但当前显示的不是运行中的那个对话。
class ReadOnlyBanner extends ConsumerWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(chatProvider);
    final l10n = AppLocalizations.of(context)!;

    // 仅当存在运行中的对话,且当前显示的不是它时显示
    if (!data.isReadOnlyView) {
      return const SizedBox.shrink();
    }

    final runningConv = data.conversationsCache[data.runningConversationId];
    final runningTitle = runningConv?.title ?? '';

    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.bolt,
                size: 18,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.readOnlyBannerMessage(runningTitle),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatProvider.notifier)
                    .setDisplayedConversation(data.runningConversationId!),
                child: Text(l10n.readOnlyJumpToRunning),
              ),
            ],
          ),
        ),
      ),
    );
  }
}