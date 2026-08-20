import 'dart:ui';

import 'package:flutter/material.dart';
import '../design_tokens.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../pages/player_page.dart';
import 'artwork.dart';
import 'toast.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.player, required this.auth});

  final PlayerController player;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    // 仅车机模式隐藏（由左侧播放面板替代）；普通横屏仍显示。
    if (isLandscape && ThemeController.instance.carModeEnabled) {
      return const SizedBox.shrink();
    }

    // MiniPlayer 响应 player 重建（进度/状态），高频更新会触发
    // Windows AXTree 竞态崩溃，排除语义树以规避 Flutter Windows 引擎 bug
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final song = player.currentSong;
          if (song == null) {
            return const SizedBox.shrink();
          }

        final progress = player.duration.inMilliseconds == 0
            ? 0.0
            : (player.position.inMilliseconds / player.duration.inMilliseconds)
                  .clamp(0.0, 1.0);
        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest.withValues(alpha: .72)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: .64),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: .38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    PlayerPageRoute(
                      builder: (_) => PlayerPage(player: player, auth: auth),
                    ),
                  ),
                  child: SizedBox(
                    height: 64,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    7,
                                    8,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Hero(
                                      tag: 'player_cover',
                                      child: Artwork(
                                        url: song.coverUrl,
                                        size: 48,
                                        borderRadius: 6,
                                      ),
                                    ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 16,
                                                  ),
                                            ),
                                            Text(
                                              song.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: player.isPlaying ? '暂停' : '播放',
                                        onPressed: player.isPreparing
                                            ? null
                                            : player.togglePlay,
                                        icon: Icon(
                                          player.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: colorScheme.onSurface,
                                          size: 30,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '播放队列',
                                        onPressed: () => _showQueue(context),
                                        icon: Icon(
                                          Icons.queue_music_rounded,
                                          color: colorScheme.onSurface,
                                          size: 29,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 2,
                                color: colorScheme.primary,
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: .12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (player.errorMessage case final message?)
                          Positioned(
                            left: 74,
                            right: 88,
                            bottom: 4,
                            child: Text(
                              message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.error,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        },
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(
                        '播放队列',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${player.queue.length} 首',
                        style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: player.queue.length > 1
                            ? () => _clearQueue(sheetContext)
                            : null,
                        child: Text(
                          '清空',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: AnimatedBuilder(
                    animation: player,
                    builder: (context, _) {
                      if (player.queue.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              '播放队列为空',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: player.queue.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final song = player.queue[index];
                          final active =
                              player.currentSong?.hash == song.hash;
                          return _QueueTile(
                            song: song,
                            index: index + 1,
                            active: active,
                            isPlaying: active && player.isPlaying,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              player.playSong(song, queue: player.queue);
                            },
                            onDelete: player.queue.length > 1
                                ? () => _removeFromQueue(sheetContext, index)
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 从队列中移除指定项（保留当前播放歌曲）。
  void _removeFromQueue(BuildContext sheetContext, int index) {
    final newQueue = List<Song>.of(player.queue);
    if (index < 0 || index >= newQueue.length) return;
    final removed = newQueue.removeAt(index);
    final current = player.currentSong;
    if (current == null) return;

    if (removed.hash == current.hash) {
      // 删除的是当前播放歌曲：切到同位置的新歌
      final nextIndex = index.clamp(0, newQueue.length - 1);
      if (newQueue.isEmpty) {
        Navigator.of(sheetContext).pop();
        player.playSong(current, queue: [current]);
        return;
      }
      Navigator.of(sheetContext).pop();
      player.playSong(newQueue[nextIndex], queue: newQueue);
    } else {
      // 非当前歌曲：仅更新队列，不打断播放
      player.playSong(current, queue: newQueue);
    }
  }

  /// 清空队列（仅保留当前播放歌曲）。
  void _clearQueue(BuildContext sheetContext) {
    final current = player.currentSong;
    if (current == null) return;
    Navigator.of(sheetContext).pop();
    player.playSong(current, queue: [current]);
    Toast.success('已清空播放队列');
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.song,
    required this.index,
    required this.active,
    required this.isPlaying,
    required this.onTap,
    this.onDelete,
  });

  final Song song;
  final int index;
  final bool active;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primary.withValues(alpha: .09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Artwork(url: song.coverUrl, size: 40, borderRadius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: active ? colorScheme.primary : null,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: active
                              ? colorScheme.primary.withValues(alpha: .72)
                              : colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (active)
              Icon(
                isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                tooltip: '从队列移除',
                color: colorScheme.onSurfaceVariant,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
