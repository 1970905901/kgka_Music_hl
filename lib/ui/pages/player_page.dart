import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../design_tokens.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/lyric_converter.dart';
import '../widgets/audio_effects_sheet.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/artwork.dart';
import '../widgets/playback_speed_sheet.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/song_action_sheets.dart';
import '../widgets/toast.dart';
import 'artist_detail_page.dart';
import 'comment_page.dart';
import 'desktop_lyrics_settings_page.dart';
import 'rhythm_game/rhythm_game_page.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.player,
    required this.auth,
  });

  final PlayerController player;
  final AuthController auth;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const _screenChannel = MethodChannel('kgka_music_hl/screen');

  @override
  void initState() {
    super.initState();
    unawaited(_setKeepScreenOn(true));
    // 不在此处调用 setPreferredOrientations：方向策略由 ThemeController 全局管理。
    // 如果这里解锁方向，即使用户在设置里没开横屏模式，旋转手机时播放页也会
    // 跟着旋转，影响竖屏体验。
  }

  @override
  void dispose() {
    unawaited(_setKeepScreenOn(false));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    try {
      await _screenChannel.invokeMethod<void>('setKeepScreenOn', enabled);
    } on MissingPluginException {
      // Non-Android targets can ignore this page-level screen setting.
    } on PlatformException {
      // Keeping playback usable is more important than failing the page open.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final song = widget.player.currentSong;
        if (song == null) {
          return const Scaffold(body: SizedBox.shrink());
        }

        return _PlayerBody(
          player: widget.player,
          auth: widget.auth,
          song: song,
          onClose: () => Navigator.of(context).pop(),
          onQueue: () => _showQueue(context),
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return AnimatedBuilder(
          animation: widget.player,
          builder: (context, _) {
            return ListView.builder(
              itemCount: widget.player.queue.length,
              itemBuilder: (context, index) {
                final song = widget.player.queue[index];
                final active = widget.player.currentSong?.hash == song.hash;
                return ListTile(
                  selected: active,
                  leading: Artwork(url: song.coverUrl, size: 44),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.player.playSong(song, queue: widget.player.queue);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PlayerBody extends StatefulWidget {
  const _PlayerBody({
    required this.player,
    required this.auth,
    required this.song,
    required this.onClose,
    required this.onQueue,
  });

  final PlayerController player;
  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final VoidCallback onQueue;

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

Future<void> _showAudioQualityPicker(
  BuildContext context,
  PlayerController player,
) async {
  final quality = await showAudioQualitySheet(
    context: context,
    selected: player.audioQuality,
    title: '切换音质',
    subtitle: '会重新加载当前歌曲并尽量保持播放进度',
  );
  if (quality == null) {
    return;
  }

  await player.setAudioQuality(quality, reloadCurrent: true);
  Toast.success('已切换到 ${quality.label}');
}

class _PlayerBodyState extends State<_PlayerBody> {
  final _pageController = PageController();
  var _page = 0;
  var _pageScrolling = false;
  bool? _lastSystemUiLandscape;

  bool get _lyricPageVisible => _page == 1 || _pageScrolling;

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.height < 150 || size.width < 150) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    final landscape = size.width > size.height;
    _syncSystemUi(landscape);
    // 横屏分栏布局是车机专属，普通横屏仍用竖屏的翻页布局。
    final isCarLayout = landscape && ThemeController.instance.carModeEnabled;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _ArtworkBackground(song: widget.song),
            SafeArea(
              // 横屏时同样需要处理顶部状态栏和底部系统导航栏（如车机空调控制栏）的遮挡。
              // 竖屏已由外层 Scaffold 处理，这里对所有方向统一保留 SafeArea。
              child: Column(
                children: [
                  if (!isCarLayout)
                    _TopBar(
                      player: widget.player,
                      auth: widget.auth,
                      song: widget.song,
                      onClose: widget.onClose,
                      onArtistTap: _openArtist,
                    ),
                  Expanded(
                    child: isCarLayout
                        ? ExcludeSemantics(
                            child: _LandscapePlayerContent(
                              player: widget.player,
                              auth: widget.auth,
                              song: widget.song,
                              onClose: widget.onClose,
                              onQueue: widget.onQueue,
                              onArtistTap: _openArtist,
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: _handlePageScrollNotification,
                            child: PageView(
                              controller: _pageController,
                              allowImplicitScrolling: true,
                              onPageChanged: (value) =>
                                  _setPageState(page: value),
                              children: [
                                _PosterPlayerPage(
                                  key: const PageStorageKey(
                                    'poster-player-page',
                                  ),
                                  player: widget.player,
                                  song: widget.song,
                                  onQueue: widget.onQueue,
                                ),
                                _LyricPlayerPage(
                                  key: const PageStorageKey(
                                    'lyric-player-page',
                                  ),
                                  player: widget.player,
                                  song: widget.song,
                                  isPageVisible: _lyricPageVisible,
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (!isCarLayout) _PageDots(page: _page),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncSystemUi(bool landscape) {
    if (_lastSystemUiLandscape == landscape) {
      return;
    }
    _lastSystemUiLandscape = landscape;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  bool _handlePageScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _setPageState(scrolling: true);
    } else if (notification is ScrollEndNotification) {
      final page = (_pageController.page ?? _page.toDouble()).round().clamp(
        0,
        1,
      );
      _setPageState(page: page, scrolling: false);
    }
    return false;
  }

  void _setPageState({int? page, bool? scrolling}) {
    final nextPage = page ?? _page;
    final nextScrolling = scrolling ?? _pageScrolling;

    if (nextPage == _page && nextScrolling == _pageScrolling) {
      return;
    }

    setState(() {
      _page = nextPage;
      _pageScrolling = nextScrolling;
    });
  }

  Future<void> _openArtist(Song song) async {
    if (song.source != SongSource.kugou) {
      Toast.info('其他平台歌曲暂不支持查看歌手');
      return;
    }
    final artists = song.artists;
    if (artists.isEmpty) {
      Toast.info('暂无歌手详情');
      return;
    }

    ArtistRef? selected;
    if (artists.length == 1) {
      selected = artists.first;
    } else {
      selected = await showModalBottomSheet<ArtistRef>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) {
          return SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: artists.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final artist = artists[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: artist.avatarUrl == null
                        ? null
                        : NetworkImage(artist.avatarUrl!),
                    child: artist.avatarUrl == null
                        ? const Icon(Icons.person_rounded)
                        : null,
                  ),
                  title: Text(artist.name),
                  onTap: () => Navigator.of(context).pop(artist),
                );
              },
            ),
          );
        },
      );
    }

    if (selected == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistDetailPage(
          api: widget.player.api,
          auth: widget.auth,
          artist: selected!,
          player: widget.player,
        ),
      ),
    );
  }
}

enum _LyricDisplayMode {
  lyricsWithTranslation,
  lyricsOnly,
  lyricsWithRomanization,
}

List<_LyricDisplayMode> _availableLyricDisplayModes(List<LyricLine> lyrics) {
  if (lyrics.isEmpty) {
    return const [];
  }

  final modes = <_LyricDisplayMode>[];
  final hasTranslation = lyrics.any(
    (line) => line.translation != null && line.translation!.isNotEmpty,
  );
  final hasRomanization = lyrics.any(
    (line) => line.romanization != null && line.romanization!.isNotEmpty,
  );

  if (hasTranslation) {
    modes.add(_LyricDisplayMode.lyricsWithTranslation);
  }
  modes.add(_LyricDisplayMode.lyricsOnly);
  if (hasRomanization) {
    modes.add(_LyricDisplayMode.lyricsWithRomanization);
  }
  return modes;
}

String _lyricDisplayModeLabel(_LyricDisplayMode mode) {
  return switch (mode) {
    _LyricDisplayMode.lyricsWithTranslation => '歌词 + 翻译',
    _LyricDisplayMode.lyricsWithRomanization => '歌词 + 音译',
    _LyricDisplayMode.lyricsOnly => '仅歌词',
  };
}

class _ArtworkBackground extends StatefulWidget {
  const _ArtworkBackground({required this.song});

  final Song song;

  @override
  State<_ArtworkBackground> createState() => _ArtworkBackgroundState();
}

class _ArtworkBackgroundState extends State<_ArtworkBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40), // 40 seconds for a full rotation
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = widget.song.coverUrl;
    final size = MediaQuery.sizeOf(context);
    final maxDim = math.max(size.width, size.height);
    final squareSize = maxDim * 1.5;

    // 旋转动画背景是纯装饰性的，排除语义树防止 Windows AXTree 竞态崩溃
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 始终显示渐变兜底背景，避免封面加载期间出现纯黑背景
          const _FallbackBackground(),
          if (coverUrl != null)
            OverflowBox(
              maxWidth: squareSize,
              maxHeight: squareSize,
              minWidth: squareSize,
              minHeight: squareSize,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: RotationTransition(
                  turns: _rotationController,
                  child: Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .32),
                  Colors.black.withValues(alpha: .56),
                  Colors.black.withValues(alpha: .82),
                ],
              ),
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: .12)),
        ],
      ),
    );
  }
}

class _FallbackBackground extends StatelessWidget {
  const _FallbackBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF153D35), Color(0xFF061219), Color(0xFF2C1320)],
        ),
      ),
    );
  }
}

class _LandscapePlayerContent extends StatelessWidget {
  const _LandscapePlayerContent({
    required this.player,
    required this.auth,
    required this.song,
    required this.onClose,
    required this.onQueue,
    required this.onArtistTap,
  });

  final PlayerController player;
  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final VoidCallback onQueue;
  final ValueChanged<Song> onArtistTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 350;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 24,
            compact ? 4 : 10,
            compact ? 16 : 30,
            compact ? 24 : 36,
          ),
          child: Column(
            children: [
              _LandscapeHeader(
                player: player,
                auth: auth,
                song: song,
                onClose: onClose,
                compact: compact,
                onArtistTap: onArtistTap,
              ),
              SizedBox(height: compact ? 2 : 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 9,
                      child: _LandscapeArtworkShowcase(
                        player: player,
                        song: song,
                        compact: compact,
                      ),
                    ),
                    SizedBox(width: compact ? 18 : 34),
                    Expanded(
                      flex: 12,
                      child: _LandscapeRightPanel(
                        player: player,
                        onQueue: onQueue,
                        compact: compact,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LandscapeHeader extends StatelessWidget {
  const _LandscapeHeader({
    required this.player,
    required this.auth,
    required this.song,
    required this.onClose,
    required this.compact,
    required this.onArtistTap,
  });

  final PlayerController player;
  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final bool compact;
  final ValueChanged<Song> onArtistTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final liked = auth.isLiked(song);
        return SizedBox(
          height: compact ? 40 : 48,
          child: Row(
            children: [
              _LandscapeHeaderButton(
                tooltip: '返回',
                size: compact ? 38 : 44,
                iconSize: compact ? 30 : 34,
                onPressed: onClose,
                icon: Icons.keyboard_arrow_left_rounded,
              ),
              SizedBox(width: compact ? 10 : 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .92),
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!compact)
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                              color: Colors.white.withValues(alpha: .7),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                  ],
                ),
              ),
              _LandscapeHeaderButton(
                tooltip: liked ? '取消喜欢' : '喜欢',
                size: compact ? 38 : 44,
                iconSize: compact ? 22 : 24,
                onPressed: song.source == SongSource.kugou
                    ? () => auth.toggleLike(song)
                    : null,
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              SizedBox(width: compact ? 6 : 8),
              _LandscapeHeaderButton(
                tooltip: '更多',
                size: compact ? 38 : 44,
                iconSize: compact ? 22 : 24,
                onPressed: () => _showMoreSheet(context),
                icon: Icons.more_horiz_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    showSongActionSheet(
      context: context,
      song: song,
      actions: [
        SongSheetAction(
          icon: Icons.speed_rounded,
          title: '倍速播放',
          subtitle: player.playbackSpeedLabel,
          onTap: () => showPlaybackSpeedSheet(context: context, player: player),
        ),
        SongSheetAction(
          icon: Icons.high_quality_rounded,
          title: '音质：${player.audioQuality.label}',
          subtitle: '切换当前播放音质',
          onTap: () => _showAudioQualityPicker(context, player),
        ),
        SongSheetAction(
          icon: Icons.auto_awesome_rounded,
          title: '试听高潮',
          subtitle: '播放歌曲高潮片段',
          onTap: () async {
            final ok = await player.playClimaxPreview();
            if (!ok) Toast.error('暂无高潮片段');
          },
        ),
        SongSheetAction(
          icon: Icons.graphic_eq_rounded,
          title: '音效',
          subtitle: player.audioEffectsLabel,
          onTap: () => showAudioEffectsSheet(context: context, player: player),
        ),
        if (song.source == SongSource.kugou)
          SongSheetAction(
            icon: Icons.playlist_add_rounded,
            title: '添加到歌单',
            onTap: () =>
                showAddToPlaylistSheet(context: context, auth: auth, song: song),
          ),
        SongSheetAction(
          icon: Icons.bedtime_rounded,
          title: '定时播放',
          subtitle: player.isSleepTimerActive
              ? '剩余 ${_formatSleepRemaining(player.sleepTimerRemaining)}'
              : player.isSleepFinishCurrentSong
                  ? '播完歌曲后停止'
                  : null,
          onTap: () => showSleepTimerSheet(context: context, player: player),
        ),
        if (player.isDesktopLyricsSupported) ...[
          SongSheetAction(
            icon: player.desktopLyricsEnabled
                ? Icons.lyrics_rounded
                : Icons.lyrics_outlined,
            title: '桌面歌词',
            subtitle: player.desktopLyricsEnabled ? '已开启' : '已关闭',
            onTap: () async {
              Navigator.of(context).pop();
              await player.setDesktopLyricsEnabled(!player.desktopLyricsEnabled);
            },
          ),
          if (player.desktopLyricsEnabled)
            SongSheetAction(
              icon: Icons.tune_rounded,
              title: '歌词设置',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DesktopLyricsSettingsPage(player: player),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _LandscapeHeaderButton extends StatelessWidget {
  const _LandscapeHeaderButton({
    required this.tooltip,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final double size;
  final double iconSize;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.square(
          dimension: size,
          child: IconButton(
            color: Colors.white,
            iconSize: iconSize,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: size, height: size),
            onPressed: onPressed,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _LandscapeArtworkShowcase extends StatefulWidget {
  const _LandscapeArtworkShowcase({
    required this.player,
    required this.song,
    required this.compact,
  });

  final PlayerController player;
  final Song song;
  final bool compact;

  @override
  State<_LandscapeArtworkShowcase> createState() =>
      _LandscapeArtworkShowcaseState();
}

class _LandscapeArtworkShowcaseState extends State<_LandscapeArtworkShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    );
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant _LandscapeArtworkShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.hash != widget.song.hash) {
      _rotationController.value = 0;
    }
    _syncRotation();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _syncRotation() {
    if (widget.player.isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else if (_rotationController.isAnimating) {
      _rotationController.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0.0;
        if (velocity < -200) {
          widget.player.next();
        } else if (velocity > 200) {
          widget.player.previous();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = math.min(constraints.maxWidth, constraints.maxHeight);
          final discSize = (available * (widget.compact ? .84 : .9))
              .clamp(150.0, 330.0)
              .toDouble();
          final coverSize = discSize * (widget.compact ? .58 : .70);

          return Center(
            // 旋转唱片是纯装饰动画，排除语义树防止 Windows AXTree 竞态崩溃
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: discSize,
                child: AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotationController.value * math.pi * 2,
                      child: child,
                    );
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withValues(alpha: .88),
                              Colors.white.withValues(alpha: .58),
                              Colors.white.withValues(alpha: .22),
                            ],
                            stops: const [0, .62, 1],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .26),
                              blurRadius: 30,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: const SizedBox.expand(),
                      ),
                      for (final ratio in const [.36, .52, .68, .82])
                        SizedBox.square(
                          dimension: discSize * ratio,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .16),
                              ),
                            ),
                          ),
                        ),
                      ClipOval(
                        child: Artwork(
                          url: widget.song.coverUrl,
                          size: coverSize,
                          borderRadius: coverSize,
                        ),
                      ),
                      SizedBox.square(
                        dimension: discSize * .08,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .82),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LandscapeRightPanel extends StatelessWidget {
  const _LandscapeRightPanel({
    required this.player,
    required this.onQueue,
    required this.compact,
  });

  final PlayerController player;
  final VoidCallback onQueue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final song = player.currentSong;
    return LayoutBuilder(
      builder: (context, constraints) {
        final veryTight = constraints.maxHeight < 250;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (song != null)
              Padding(
                padding: EdgeInsets.only(
                  bottom: veryTight ? 6.0 : 12.0,
                  top: veryTight ? 2.0 : 6.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white.withValues(alpha: .92),
                            fontSize: compact ? 18 : 22,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .6),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _LandscapeLyricPanel(
                player: player,
                songHash: song?.hash ?? '',
                lyrics: player.lyrics,
                compact: compact || veryTight,
              ),
            ),
            SizedBox(height: veryTight ? 2 : 6),
            _Progress(player: player, bright: true, compact: true),
            SizedBox(height: veryTight ? 0 : 4),
            _Controls(
              player: player,
              bright: true,
              onQueue: onQueue,
              compactOverride: true,
              denseOverride: veryTight,
            ),
          ],
        );
      },
    );
  }
}

class _LandscapeLyricPanel extends StatefulWidget {
  const _LandscapeLyricPanel({
    required this.player,
    required this.songHash,
    required this.lyrics,
    required this.compact,
  });

  final PlayerController player;
  final String songHash;
  final List<LyricLine> lyrics;
  final bool compact;

  @override
  State<_LandscapeLyricPanel> createState() => _LandscapeLyricPanelState();
}

class _LandscapeLyricPanelState extends State<_LandscapeLyricPanel> {
  late final LyricController _lyricController;
  late final Ticker _ticker;
  bool _isUserSelecting = false;

  @override
  void initState() {
    super.initState();
    _lyricController = LyricController();
    _lyricController.setOnTapLineCallback((position) {
      widget.player.seek(position);
    });
    _lyricController.isSelectingNotifier.addListener(_onSelectingChanged);
    _syncLyrics();
    _ticker = Ticker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _LandscapeLyricPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songHash != widget.songHash ||
        oldWidget.lyrics != widget.lyrics) {
      _syncLyrics();
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _lyricController.isSelectingNotifier.removeListener(_onSelectingChanged);
    _ticker.dispose();
    _lyricController.dispose();
    super.dispose();
  }

  void _onSelectingChanged() {
    _isUserSelecting = _lyricController.isSelectingNotifier.value;
    _syncTicker();
  }

  void _syncLyrics() {
    final lyrics = widget.lyrics;
    if (lyrics.isNotEmpty) {
      final model = convertToFlutterLyricModel(lyrics);
      _lyricController.loadLyricModel(model);
    }
  }

  void _syncTicker() {
    final shouldTick =
        widget.player.isPlaying &&
        widget.lyrics.isNotEmpty &&
        !widget.player.isScrubbing &&
        !_isUserSelecting;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || widget.player.isScrubbing) {
      return;
    }
    _lyricController.setProgress(widget.player.smoothPosition);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final lyrics = widget.lyrics;
    if (lyrics.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          player.isPreparing ? '正在准备音乐...' : '暂无歌词',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white.withValues(alpha: .82),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    final fontSize = widget.compact ? 26.0 : 34.0;
    final inactiveFontSize = widget.compact ? 18.0 : 24.0;

    return ExcludeSemantics(
      // 歌词视图高频更新会触发 Windows AXTree 竞态崩溃，排除语义树
      child: LyricView(
        controller: _lyricController,
        style: LyricStyles.default1.copyWith(
          textStyle: Theme.of(context).textTheme.titleLarge!.copyWith(
            color: Colors.white.withValues(alpha: .34),
            fontSize: inactiveFontSize,
            height: 1.18,
            fontWeight: FontWeight.w800,
          ),
          activeStyle: Theme.of(context).textTheme.headlineMedium!.copyWith(
            color: Colors.white.withValues(alpha: .34),
            fontSize: fontSize,
            height: 1.18,
            fontWeight: FontWeight.w900,
          ),
          lineGap: widget.compact ? 10 : 16,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: widget.compact ? 20 : 40,
          ),
          fadeRange: FadeRange(top: 40, bottom: 40),
          textAlign: TextAlign.left,
          contentAlignment: CrossAxisAlignment.start,
          activeHighlightColor: Colors.white,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.player,
    required this.auth,
    required this.song,
    required this.onClose,
    required this.onArtistTap,
  });

  final PlayerController player;
  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final ValueChanged<Song> onArtistTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final liked = auth.isLiked(song);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                color: Colors.white,
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .82),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _GlassIconButton(
                tooltip: liked ? '取消喜欢' : '喜欢',
                onPressed: song.source == SongSource.kugou
                    ? () => auth.toggleLike(song)
                    : null,
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              const SizedBox(width: 8),
              _GlassIconButton(
                tooltip: '更多',
                onPressed: () => _showMoreSheet(context),
                icon: Icons.more_horiz_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    showSongActionSheet(
      context: context,
      song: song,
      actions: [
        // Grid actions
        SongSheetAction(
          icon: Icons.speed_rounded,
          title: '倍速',
          subtitle: player.playbackSpeedLabel,
          isGrid: true,
          onTap: () => showPlaybackSpeedSheet(context: context, player: player),
        ),
        SongSheetAction(
          icon: Icons.high_quality_rounded,
          title: '音质',
          subtitle: player.audioQuality.badge,
          isGrid: true,
          onTap: () => _showAudioQualityPicker(context, player),
        ),
        SongSheetAction(
          icon: Icons.graphic_eq_rounded,
          title: '音效',
          isGrid: true,
          onTap: () => showAudioEffectsSheet(context: context, player: player),
        ),
        SongSheetAction(
          icon: Icons.auto_awesome_rounded,
          title: '高潮',
          isGrid: true,
          onTap: () async {
            final ok = await player.playClimaxPreview();
            if (!ok) Toast.error('暂无高潮片段');
          },
        ),
        SongSheetAction(
          icon: Icons.bedtime_rounded,
          title: '定时',
          isGrid: true,
          onTap: () => showSleepTimerSheet(context: context, player: player),
        ),

        if (player.isDesktopLyricsSupported) ...[
          SongSheetAction(
            icon: player.desktopLyricsEnabled
                ? Icons.lyrics_rounded
                : Icons.lyrics_outlined,
            title: '桌面歌词',
            isGrid: true,
            onTap: () async {
              Navigator.of(context).pop();
              await player.setDesktopLyricsEnabled(!player.desktopLyricsEnabled);
            },
          ),
          if (player.desktopLyricsEnabled)
            SongSheetAction(
              icon: Icons.tune_rounded,
              title: '歌词设置',
              isGrid: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DesktopLyricsSettingsPage(player: player),
                ),
              ),
            ),
        ],
        SongSheetAction(
          icon: Icons.queue_music_rounded,
          title: '下一首',
          isGrid: true,
          onTap: () => addSongToQueueWithFeedback(
            context: context,
            player: player,
            song: song,
          ),
        ),
        // List actions
        if (song.source == SongSource.kugou)
          SongSheetAction(
            icon: Icons.playlist_add_rounded,
            title: '添加到歌单',
            onTap: () =>
                showAddToPlaylistSheet(context: context, auth: auth, song: song),
          ),
      ],
    );
  }
}

String _formatSleepRemaining(Duration? remaining) {
  if (remaining == null || remaining <= Duration.zero) return '';
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds.remainder(60);
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class _PosterPlayerPage extends StatefulWidget {
  const _PosterPlayerPage({
    super.key,
    required this.player,
    required this.song,
    required this.onQueue,
  });

  final PlayerController player;
  final Song song;
  final VoidCallback onQueue;

  @override
  State<_PosterPlayerPage> createState() => _PosterPlayerPageState();
}

class _PosterPlayerPageState extends State<_PosterPlayerPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final artworkMaxWidth = compact ? 250.0 : 330.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
          child: Column(
            children: [
              const Spacer(),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: artworkMaxWidth),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Hero(
                    tag: 'player_cover',
                    child: Artwork(
                    url: widget.song.coverUrl,
                    size: double.infinity,
                    borderRadius: 8,
                  ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 14 : 26),
              _PosterLyricPreview(player: widget.player),
              if (!compact) const SizedBox(height: 4),
              _CommentEntry(player: widget.player, song: widget.song),
              const Spacer(),
              _Progress(player: widget.player, bright: true),
              const SizedBox(height: 10),
              _Controls(
                player: widget.player,
                bright: true,
                onQueue: widget.onQueue,
              ),
            ],
          ),
        );
      },
    );
  }
}

int _activeLyricIndexFor(List<LyricLine> lyrics, Duration position) {
  if (lyrics.isEmpty) return -1;
  var index = 0;
  for (var i = 0; i < lyrics.length; i++) {
    if (position >= lyrics[i].time) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}

class _PosterLyricPreview extends StatefulWidget {
  const _PosterLyricPreview({required this.player});

  final PlayerController player;

  @override
  State<_PosterLyricPreview> createState() => _PosterLyricPreviewState();
}

class _PosterLyricPreviewState extends State<_PosterLyricPreview> {
  late final Ticker _ticker;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _position = widget.player.smoothPosition;
    _ticker = Ticker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _PosterLyricPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.player.isScrubbing) {
      _position = widget.player.smoothPosition;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final shouldTick =
        widget.player.isPlaying &&
        widget.player.lyrics.isNotEmpty &&
        !widget.player.isScrubbing;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || widget.player.isScrubbing) {
      return;
    }
    setState(() => _position = widget.player.smoothPosition);
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.player.lyrics;
    if (lyrics.isEmpty) {
      return SizedBox(
        height: 104,
        child: Center(
          child: Text(
            widget.player.isPreparing ? '歌词加载中...' : '暂无歌词',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white.withValues(alpha: .78),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    final index = _activeLyricIndexFor(lyrics, _position);
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;
    final currentStyle = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: Colors.white,
      fontSize: 22,
      height: 1.22,
      fontWeight: FontWeight.w900,
    );
    final nextStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
      color: Colors.white.withValues(alpha: .46),
      height: 1.18,
      fontWeight: FontWeight.w700,
    );

    // 歌词预览每帧更新位置，用 ExcludeSemantics 防止 Windows AXTree 竞态崩溃
    return ExcludeSemantics(
      child: SizedBox(
        height: 96,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: Column(
            key: ValueKey(current.time.inMilliseconds),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 36,
                child: _MarqueeSingleLine(
                  textKey: current.time.inMilliseconds,
                  child: _LyricText(
                    line: current,
                    active: true,
                    position: _position,
                    styleOverride: currentStyle,
                    textAlign: TextAlign.center,
                    singleLine: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 25,
                child: _MarqueeSingleLine(
                  textKey: current.translation != null && current.translation!.isNotEmpty
                      ? current.time.inMilliseconds
                      : (next?.time.inMilliseconds ?? -1),
                  child: Text(
                    current.translation != null && current.translation!.isNotEmpty
                        ? current.translation!
                        : (next?.text ?? ''),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: nextStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarqueeSingleLine extends StatefulWidget {
  const _MarqueeSingleLine({required this.child, required this.textKey});

  final Widget child;
  final Object textKey;

  @override
  State<_MarqueeSingleLine> createState() => _MarqueeSingleLineState();
}

class _MarqueeSingleLineState extends State<_MarqueeSingleLine>
    with SingleTickerProviderStateMixin {
  final _viewportKey = GlobalKey();
  final _contentKey = GlobalKey();
  late final AnimationController _controller;
  double _overflow = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _MarqueeSingleLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textKey != widget.textKey) {
      _controller
        ..stop()
        ..reset();
      _overflow = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) {
      return;
    }
    final viewport = _viewportKey.currentContext?.size?.width ?? 0;
    final content = _contentKey.currentContext?.size?.width ?? 0;
    final overflow = math.max(0.0, content - viewport);
    if ((overflow - _overflow).abs() < 1) {
      return;
    }
    setState(() => _overflow = overflow);
    if (overflow > 0) {
      _controller
        ..duration = Duration(milliseconds: (overflow * 42).round() + 2600)
        ..repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          key: _viewportKey,
          child: SizedBox(
            width: constraints.maxWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = _overflow <= 0
                    ? 0.0
                    : -_overflow * _controller.value;
                return Align(
                  alignment: _overflow <= 0
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  ),
                );
              },
              child: OverflowBox(
                minWidth: 0,
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: RepaintBoundary(key: _contentKey, child: widget.child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LyricPlayerPage extends StatefulWidget {
  const _LyricPlayerPage({
    super.key,
    required this.player,
    required this.song,
    required this.isPageVisible,
  });

  final PlayerController player;
  final Song song;
  final bool isPageVisible;

  @override
  State<_LyricPlayerPage> createState() => _LyricPlayerPageState();
}

class _LyricPlayerPageState extends State<_LyricPlayerPage>
    with AutomaticKeepAliveClientMixin {
  late _LyricDisplayMode _displayMode;

  /// 歌词字体缩放倍率（持久化）。
  static const _lyricScaleKey = 'settings.lyric_scale';
  double _lyricScale = 1.0;

  @override
  void initState() {
    super.initState();
    _displayMode = _initialLyricDisplayMode(widget.player.lyrics);
    _loadLyricScale();
  }

  Future<void> _loadLyricScale() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _lyricScale = prefs.getDouble(_lyricScaleKey) ?? 1.0);
    }
  }

  Future<void> _setLyricScale(double scale) async {
    final clamped = scale.clamp(0.7, 1.6);
    setState(() => _lyricScale = clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lyricScaleKey, clamped);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _LyricPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.hash != widget.song.hash ||
        oldWidget.player.lyrics != widget.player.lyrics) {
      _displayMode = _normalizeLyricDisplayMode(
        widget.player.lyrics,
        _displayMode,
      );
    }
  }

  _LyricDisplayMode _initialLyricDisplayMode(List<LyricLine> lyrics) {
    final availableModes = _availableLyricDisplayModes(lyrics);
    return availableModes.isNotEmpty
        ? availableModes.first
        : _LyricDisplayMode.lyricsOnly;
  }

  _LyricDisplayMode _normalizeLyricDisplayMode(
    List<LyricLine> lyrics,
    _LyricDisplayMode currentMode,
  ) {
    final availableModes = _availableLyricDisplayModes(lyrics);
    if (availableModes.contains(currentMode)) {
      return currentMode;
    }
    return availableModes.isNotEmpty
        ? availableModes.first
        : _LyricDisplayMode.lyricsOnly;
  }

  void _toggleLyricDisplayMode() {
    final availableModes = _availableLyricDisplayModes(widget.player.lyrics);
    if (availableModes.length <= 1) {
      return;
    }

    final currentIndex = availableModes.indexOf(_displayMode);
    final nextIndex = currentIndex >= 0
        ? (currentIndex + 1) % availableModes.length
        : 0;
    setState(() => _displayMode = availableModes[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final availableModes = _availableLyricDisplayModes(widget.player.lyrics);
    final canToggleLyricDisplayMode = availableModes.length > 1;
    final displayMode = _normalizeLyricDisplayMode(
      widget.player.lyrics,
      _displayMode,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Stack(
        children: [
          _LyricViewport(
            player: widget.player,
            lyrics: widget.player.lyrics,
            activeIndex: widget.player.activeLyricIndex,
            isPreparing: widget.player.isPreparing,
            displayMode: displayMode,
            isPageVisible: widget.isPageVisible,
            lyricScale: _lyricScale,
          ),
          // 字体大小调节按钮（左侧底部）
          Positioned(
            left: 0,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GlassIconButton(
                  tooltip: '缩小歌词',
                  onPressed: () => _setLyricScale(_lyricScale - 0.1),
                  icon: Icons.text_decrease_rounded,
                ),
                const SizedBox(width: 8),
                _GlassIconButton(
                  tooltip: '放大歌词',
                  onPressed: () => _setLyricScale(_lyricScale + 0.1),
                  icon: Icons.text_increase_rounded,
                ),
              ],
            ),
          ),
          if (canToggleLyricDisplayMode)
            Positioned(
              right: 0,
              bottom: 16,
              child: _GlassIconButton(
                tooltip: '切换歌词模式（当前：${_lyricDisplayModeLabel(displayMode)}）',
                onPressed: _toggleLyricDisplayMode,
                icon: switch (displayMode) {
                  _LyricDisplayMode.lyricsWithTranslation =>
                    Icons.translate_rounded,
                  _LyricDisplayMode.lyricsWithRomanization =>
                    Icons.record_voice_over_rounded,
                  _LyricDisplayMode.lyricsOnly => Icons.lyrics_rounded,
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LyricViewport extends StatefulWidget {
  const _LyricViewport({
    required this.player,
    required this.lyrics,
    required this.activeIndex,
    required this.isPreparing,
    required this.displayMode,
    required this.isPageVisible,
    required this.lyricScale,
  });

  final PlayerController player;
  final List<LyricLine> lyrics;
  final int activeIndex;
  final bool isPreparing;
  final _LyricDisplayMode displayMode;
  final bool isPageVisible;
  final double lyricScale;

  @override
  State<_LyricViewport> createState() => _LyricViewportState();
}

class _LyricViewportState extends State<_LyricViewport>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _LyricViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final shouldTick =
        widget.isPageVisible &&
        widget.player.isPlaying &&
        widget.lyrics.isNotEmpty &&
        !widget.player.isScrubbing;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || widget.player.isScrubbing) {
      return;
    }
    // 卡拉OK渐变填充逐帧跟随播放进度刷新
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    if (lyrics.isEmpty) {
      return Center(
        child: Text(
          widget.isPreparing ? '正在准备音乐...' : '暂无歌词',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final activeIndex = widget.activeIndex.clamp(0, lyrics.length - 1);
    final showTranslation =
        widget.displayMode == _LyricDisplayMode.lyricsWithTranslation;
    final showRomanization =
        widget.displayMode == _LyricDisplayMode.lyricsWithRomanization;

    return ExcludeSemantics(
      // 歌词视图高频更新会触发 Windows AXTree 竞态崩溃，排除语义树
      child: _LyricsStage3D(
        player: widget.player,
        lyrics: lyrics,
        activeIndex: activeIndex,
        showSubtitle: showTranslation || showRomanization,
        useRomanization: showRomanization,
        lyricScale: widget.lyricScale,
      ),
    );
  }
}

/// 竖屏歌词页 3D 舞台：还原 HTML 的非线性层级、透视、模糊与上下淡出遮罩，
/// 并支持像列表一样上下滑动查看完整歌词。
class _LyricsStage3D extends StatefulWidget {
  const _LyricsStage3D({
    required this.player,
    required this.lyrics,
    required this.activeIndex,
    required this.showSubtitle,
    required this.useRomanization,
    required this.lyricScale,
  });

  final PlayerController player;
  final List<LyricLine> lyrics;
  final int activeIndex;
  final bool showSubtitle;
  final bool useRomanization;
  final double lyricScale;

  @override
  State<_LyricsStage3D> createState() => _LyricsStage3DState();
}

class _LyricsStage3DState extends State<_LyricsStage3D>
    with SingleTickerProviderStateMixin {
  static const double _perspective = 1000;
  static const double _contentPadding = 20;
  static const int _desiredVisibleLines = 9;
  static const double _lineGap = 10;
  static const double _anchorFraction = 260 / 600;
  static const Curve _followCurve = Cubic(0.16, 1.0, 0.3, 1.0);

  // 行高缓存：仅在歌词/显示模式/字号/内容宽度变化时重建。
  final Map<int, double> _heightCache = {};
  List<LyricLine>? _cacheLyrics;
  bool? _cacheShowSubtitle;
  bool? _cacheUseRomanization;
  double? _cacheLyricScale;
  double? _cacheContentWidth;

  // 文档布局（每次 build 由视口尺寸重算）。
  double _viewportHeight = 0;
  double _contentWidth = 0;
  double _lineWidth = 0;
  double _anchorY = 0;
  double _baseStep = 0;
  List<double> _docTops = const [];
  double _docHeight = 0;
  bool _layoutDirty = true;

  // 滚动：_scrollY 为文档顶部在视口中的位置。
  late final AnimationController _scrollAnim;
  late final CurvedAnimation _scrollCurve;
  double _scrollY = 0;
  double _scrollFrom = 0;
  double _scrollTo = 0;
  bool _isDragging = false;
  bool _isFollowing = true;

  @override
  void initState() {
    super.initState();
    _scrollAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scrollCurve = CurvedAnimation(parent: _scrollAnim, curve: _followCurve);
    _scrollAnim.addListener(_onScrollTick);
  }

  @override
  void didUpdateWidget(covariant _LyricsStage3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics ||
        oldWidget.showSubtitle != widget.showSubtitle ||
        oldWidget.useRomanization != widget.useRomanization ||
        oldWidget.lyricScale != widget.lyricScale) {
      // 歌词/模式/字号变化：重建布局并回到跟随当前行。
      _scrollAnim.stop();
      _isDragging = false;
      _isFollowing = true;
      _layoutDirty = true;
    } else if (oldWidget.activeIndex != widget.activeIndex) {
      // 播放推进到下一句：跟随模式下非线性平滑滚动到新位置。
      if (_isFollowing && !_isDragging) {
        _animateScrollTo(_followTarget);
      }
    }
  }

  @override
  void dispose() {
    _scrollAnim.removeListener(_onScrollTick);
    _scrollCurve.dispose();
    _scrollAnim.dispose();
    super.dispose();
  }

  double get _maxScroll => math.max(0.0, _docHeight - _viewportHeight);

  double get _followTarget {
    if (_docTops.isEmpty) return 0;
    final index = widget.activeIndex.clamp(0, _docTops.length - 1);
    return (_docTops[index] - _anchorY).clamp(0.0, _maxScroll);
  }

  void _onScrollTick() {
    if (!mounted) return;
    setState(() {
      _scrollY = _scrollFrom + (_scrollTo - _scrollFrom) * _scrollCurve.value;
    });
  }

  void _animateScrollTo(double target) {
    final clamped = target.clamp(0.0, _maxScroll);
    if ((clamped - _scrollY).abs() < 0.5) return;
    _scrollFrom = _scrollY;
    _scrollTo = clamped;
    _scrollAnim.forward(from: 0);
  }

  TextStyle get _mainStyle => TextStyle(
    fontSize: 38.0 * widget.lyricScale,
    height: 1.24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  TextStyle get _subtitleStyle => TextStyle(
    fontSize: 22.0 * widget.lyricScale,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  /// 单行（主歌词 + 翻译/音译）的整块参考高度，用于判断某行是否换行变高。
  double get _singleLineBlockHeight {
    var height = _mainStyle.fontSize! * (_mainStyle.height ?? 1.0);
    if (widget.showSubtitle) {
      height += 6 + _subtitleStyle.fontSize! * (_subtitleStyle.height ?? 1.0);
    }
    return height;
  }

  void _ensureCache(double contentWidth) {
    if (_cacheLyrics == widget.lyrics &&
        _cacheShowSubtitle == widget.showSubtitle &&
        _cacheUseRomanization == widget.useRomanization &&
        _cacheLyricScale == widget.lyricScale &&
        _cacheContentWidth == contentWidth) {
      return;
    }
    _cacheLyrics = widget.lyrics;
    _cacheShowSubtitle = widget.showSubtitle;
    _cacheUseRomanization = widget.useRomanization;
    _cacheLyricScale = widget.lyricScale;
    _cacheContentWidth = contentWidth;
    _heightCache.clear();
  }

  double _textHeight(String text, TextStyle style, double maxWidth) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  /// 主歌词 + 翻译/音译（含 6px 间距）的整块渲染高度。
  double _blockHeight(int index, double contentWidth) {
    final cached = _heightCache[index];
    if (cached != null) return cached;
    final line = widget.lyrics[index];
    var height = _textHeight(line.text, _mainStyle, contentWidth);
    final subtitle = widget.useRomanization ? line.romanization : line.translation;
    if (widget.showSubtitle && subtitle != null && subtitle.isNotEmpty) {
      height += 6 + _textHeight(subtitle, _subtitleStyle, contentWidth);
    }
    _heightCache[index] = height;
    return height;
  }

  /// 文档中相邻两行的间距：普通单行用基础行距（9 行撑满一屏），
  /// 换行长句按实际高度 + 间隙兜底，避免压到上下句。
  double _spacing(int a, int b) {
    final hA = _blockHeight(a, _contentWidth);
    final hB = _blockHeight(b, _contentWidth);
    final tallA = hA > _singleLineBlockHeight + 2;
    final tallB = hB > _singleLineBlockHeight + 2;
    if (!tallA && !tallB) return _baseStep;
    // 换行长句不按整块高度完全撑开，否则英文长句（普遍换行成两行）会把
    // 高亮行与上下行的间距拉得过大；取 80% 高度 + 间隙折中，
    // 保留基本阅读间距，同时避免文本明显重叠。
    return math.max(
      _baseStep,
      math.max(hA, hB) * 0.8 + _lineGap,
    ).toDouble();
  }

  /// 把所有歌词排成完整文档：首行上方与末行下方各留出锚点距离，
  /// 保证任意一句都能滚动到 43.3% 的锚点位置。
  void _computeLayout() {
    final n = widget.lyrics.length;
    _docTops = List<double>.filled(n, 0);
    var top = _anchorY;
    for (var i = 0; i < n; i++) {
      _docTops[i] = top;
      if (i + 1 < n) {
        top += _spacing(i, i + 1);
      }
    }
    _docHeight = n == 0
        ? _viewportHeight
        : top + _blockHeight(n - 1, _contentWidth) + (_viewportHeight - _anchorY);
  }

  int _firstVisibleIndex(double threshold) {
    final n = widget.lyrics.length;
    var lo = 0;
    var hi = n;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_docTops[mid] + _blockHeight(mid, _contentWidth) <= threshold) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _scrollAnim.stop();
    _isDragging = true;
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _scrollY = (_scrollY - details.delta.dy).clamp(0.0, _maxScroll);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDragging = false;
    final diff = (_scrollY - _followTarget).abs();
    _isFollowing = diff < _baseStep * 0.6;
    if (_isFollowing) {
      _animateScrollTo(_followTarget);
    }
    setState(() {});
  }

  void _onVerticalDragCancel() {
    _isDragging = false;
    setState(() {});
  }

  void _backToCurrent() {
    _isFollowing = true;
    _animateScrollTo(_followTarget);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lyrics = widget.lyrics;
        _viewportHeight = constraints.maxHeight;
        _contentWidth = constraints.maxWidth - _contentPadding * 2;
        _lineWidth = constraints.maxWidth;
        _anchorY = _viewportHeight * _anchorFraction;
        _ensureCache(_contentWidth);

        // 行距：9 行撑满顶栏以下的可视高度，保持 pow(距离, 0.82) 的层次。
        final halfLines = (_desiredVisibleLines - 1) / 2;
        _baseStep =
            (constraints.maxHeight * 0.42 / math.pow(halfLines, 0.82))
                    .toDouble() *
                widget.lyricScale;

        _computeLayout();

        if (_layoutDirty) {
          _layoutDirty = false;
          _scrollY = _followTarget;
        }

        if (lyrics.isEmpty) {
          return const SizedBox.shrink();
        }

        final start = _firstVisibleIndex(_scrollY - 160);
        final endY = _scrollY + _viewportHeight + 160;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onVerticalDragCancel: _onVerticalDragCancel,
          child: ClipRect(
            child: Stack(
              children: [
                ShaderMask(
                  // 对应 HTML mask-image: 上下边缘渐变淡出。
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.18, 0.82, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.srcIn,
                  child: Transform(
                    // 对应 HTML 容器 perspective: 1000px。
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, -1 / _perspective),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var index = start;
                            index < lyrics.length &&
                                _docTops[index] <= endY;
                            index++)
                          _buildLine(index),
                      ],
                    ),
                  ),
                ),
                // 滚动位置指示条
                if (_docHeight > _viewportHeight)
                  Positioned(
                    left: 3,
                    top: _scrollIndicatorTop,
                    child: Container(
                      width: 3,
                      height: _scrollIndicatorHeight,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                // 浏览状态下的“回到当前歌词”按钮（与放大/缩小歌词同款玻璃圆钮）
                if (!_isFollowing)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: _GlassIconButton(
                        tooltip: '回到当前歌词',
                        onPressed: _backToCurrent,
                        icon: Icons.my_location_rounded,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  double get _scrollIndicatorHeight {
    final height = _viewportHeight * _viewportHeight / _docHeight;
    return height.clamp(24.0, _viewportHeight - 16);
  }

  double get _scrollIndicatorTop {
    if (_maxScroll <= 0) return _anchorY;
    final free = _viewportHeight - _scrollIndicatorHeight;
    return (_scrollY / _maxScroll) * free;
  }

  Widget _buildLine(int index) {
    final line = widget.lyrics[index];
    final screenY = _docTops[index] - _scrollY;
    final distance = (screenY - _anchorY) / _baseStep;
    final abs = distance.abs();
    final placement = _LinePlacement(
      y: screenY,
      // translateZ = -abs * 40
      translateZ: -abs * 40.0,
      // rotateX = distance * -2.5deg
      rotateX: distance * -2.5,
      // scale: 锚点行 1.04，其余 max(0.55, 1 / (1 + abs * 0.16))，
      // 缩小高亮行与普通行的大小差，避免差距过大。
      scale: abs < 0.01
          ? 1.04
          : math.max(0.55, 1 / (1 + abs * 0.16)).toDouble(),
      // opacity: 锚点行 1，其余 max(0.04, pow(0.52, abs))
      opacity: abs < 0.01
          ? 1.0
          : math.max(0.04, math.pow(0.52, abs).toDouble()).toDouble(),
      // blur: 锚点行 0，其余 min(pow(abs, 1.3) * 1.2, 7)
      blur: abs < 0.01
          ? 0.0
          : math.min(math.pow(abs, 1.3) * 1.2, 7.0).toDouble(),
    );
    final subtitle = widget.useRomanization ? line.romanization : line.translation;
    final hasSubtitle =
        widget.showSubtitle && subtitle != null && subtitle.isNotEmpty;

    return Positioned(
      key: ValueKey('lyric-line-$index'),
      left: 0,
      top: 0,
      child: SizedBox(
        width: _lineWidth,
        child: _LyricLine3D(
          placement: placement,
          absDistance: abs,
          animateTransition: !_isDragging && !_scrollAnim.isAnimating,
          text: line.text,
          subtitle: hasSubtitle ? subtitle : null,
          mainStyle: _mainStyle,
          subtitleStyle: _subtitleStyle,
          progress: _lineProgress(index),
          isActive: index == widget.activeIndex,
          isPast: index < widget.activeIndex,
          onTap: () => widget.player.seek(line.time),
        ),
      ),
    );
  }

  double _lineProgress(int index) {
    final position = widget.player.smoothPosition;
    final line = widget.lyrics[index];
    final startMs = line.time.inMilliseconds;
    final explicitMs = line.duration?.inMilliseconds ?? 0;
    var endMs = explicitMs > 0 ? startMs + explicitMs : startMs;
    if (endMs <= startMs) {
      endMs = index + 1 < widget.lyrics.length
          ? widget.lyrics[index + 1].time.inMilliseconds
          : startMs + 5000;
    }
    final durationMs = endMs - startMs;
    if (durationMs <= 0) return 1.0;
    final elapsedMs = position.inMilliseconds - startMs;
    // 对应 HTML startKaraokeLineFill 的 ease-in-out 缓动，填充动画非线性。
    final linear = (elapsedMs / durationMs).clamp(0.0, 1.0).toDouble();
    if (linear < 0.5) {
      return 2 * linear * linear;
    }
    return 1 - math.pow(-2 * linear + 2, 2).toDouble() / 2;
  }
}

/// 单行歌词：主歌词 + 翻译/音译，支持卡拉OK渐变填充和 750ms 过渡。
class _LyricLine3D extends StatefulWidget {
  const _LyricLine3D({
    required this.placement,
    required this.absDistance,
    required this.animateTransition,
    required this.text,
    required this.subtitle,
    required this.mainStyle,
    required this.subtitleStyle,
    required this.progress,
    required this.isActive,
    required this.isPast,
    required this.onTap,
  });

  final _LinePlacement placement;
  final double absDistance;
  final bool animateTransition;
  final String text;
  final String? subtitle;
  final TextStyle mainStyle;
  final TextStyle subtitleStyle;
  final double progress;
  final bool isActive;
  final bool isPast;
  final VoidCallback onTap;

  @override
  State<_LyricLine3D> createState() => _LyricLine3DState();
}

class _LyricLine3DState extends State<_LyricLine3D>
    with SingleTickerProviderStateMixin {
  // 对应 CSS transition: transform/opacity/filter .75s cubic-bezier(.16,1,.3,1)
  static const Duration _transition = Duration(milliseconds: 750);
  static const Curve _transitionCurve = Cubic(0.16, 1.0, 0.3, 1.0);

  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  late _LinePlacement _from;
  late _LinePlacement _to;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _transition,
      // 初始值直接落在目标位置，避免入场动画。
      value: 1.0,
    );
    _curved = CurvedAnimation(parent: _controller, curve: _transitionCurve);
    _from = widget.placement;
    _to = widget.placement;
  }

  @override
  void didUpdateWidget(covariant _LyricLine3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement) {
      if (widget.animateTransition) {
        // 离散变化（模式/字号/歌词切换）：从中断时的当前值平滑过渡。
        _from = _LinePlacementTween(begin: _from, end: _to).lerp(_curved.value);
        _to = widget.placement;
        _controller.forward(from: 0);
      } else {
        // 滚动/跟随动画期间：直接落在目标位置，避免逐帧重启过渡造成拖影。
        _from = widget.placement;
        _to = widget.placement;
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _curved,
        builder: (context, _) {
          final animated = _LinePlacementTween(begin: _from, end: _to)
              .lerp(_curved.value);
          Widget content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KaraokeGradientText(
                  text: widget.text,
                  style: widget.mainStyle,
                  progress: widget.progress,
                  isActive: widget.isActive,
                  isPast: widget.isPast,
                  brightColor: Colors.white,
                  dimColor: Colors.white.withValues(alpha: .30),
                  pastColor: Colors.white.withValues(alpha: .45),
                ),
                if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _KaraokeGradientText(
                    text: widget.subtitle!,
                    style: widget.subtitleStyle,
                    progress: widget.progress,
                    isActive: widget.isActive,
                    isPast: widget.isPast,
                    brightColor: Colors.white.withValues(alpha: .95),
                    dimColor: Colors.white.withValues(alpha: .25),
                    pastColor: Colors.white.withValues(alpha: .35),
                  ),
                ],
              ],
            ),
          );

          // 较远且几乎不可见的行不做高斯模糊，降低逐帧渲染开销。
          if (animated.blur >= 0.5 && widget.absDistance <= 4) {
            content = ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: animated.blur,
                sigmaY: animated.blur,
              ),
              child: content,
            );
          }

          return Opacity(
            opacity: animated.opacity,
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..translateByDouble(0.0, animated.y, animated.translateZ, 1.0)
                ..rotateX(animated.rotateX * math.pi / 180)
                ..scaleByDouble(
                  animated.scale,
                  animated.scale,
                  animated.scale,
                  1.0,
                ),
              child: content,
            ),
          );
        },
      ),
    );
  }
}

/// 卡拉OK渐变文字：已唱行整行变暗色，当前行按进度白→暗硬切填充。
class _KaraokeGradientText extends StatelessWidget {
  const _KaraokeGradientText({
    required this.text,
    required this.style,
    required this.progress,
    required this.isActive,
    required this.isPast,
    required this.brightColor,
    required this.dimColor,
    required this.pastColor,
  });

  final String text;
  final TextStyle style;
  final double progress;
  final bool isActive;
  final bool isPast;
  final Color brightColor;
  final Color dimColor;
  final Color pastColor;

  @override
  Widget build(BuildContext context) {
    if (isPast) {
      return Text(text, style: style.copyWith(color: pastColor));
    }
    if (!isActive) {
      return Text(text, style: style.copyWith(color: dimColor));
    }
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= 0) {
      return Text(text, style: style.copyWith(color: dimColor));
    }
    if (p >= 1) {
      return Text(text, style: style.copyWith(color: brightColor));
    }
    // 多行时按字序逐行填充：先填满第一行，再从左到右填第二行，
    // 而不是从整块文字的最左端一刀切导致两行同时被渲染。
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = _LineFillPainter(
          text: text,
          style: style,
          brightColor: brightColor,
          dimColor: dimColor,
          progress: p,
          textDirection: Directionality.of(context),
          maxWidth: constraints.maxWidth,
        );
        return CustomPaint(
          size: Size(painter.width, painter.height),
          painter: painter,
        );
      },
    );
  }
}

/// 逐行卡拉OK填充：按字符顺序从左到右扫过每一行（换行后继续下一行）。
class _LineFillPainter extends CustomPainter {
  _LineFillPainter({
    required this.text,
    required this.style,
    required this.brightColor,
    required this.dimColor,
    required this.progress,
    required this.textDirection,
    required this.maxWidth,
  }) : _brightPainter = TextPainter(
         text: TextSpan(text: text, style: style.copyWith(color: brightColor)),
         textDirection: textDirection,
       )..layout(maxWidth: maxWidth),
       _dimPainter = TextPainter(
         text: TextSpan(text: text, style: style.copyWith(color: dimColor)),
         textDirection: textDirection,
       )..layout(maxWidth: maxWidth);

  final String text;
  final TextStyle style;
  final Color brightColor;
  final Color dimColor;
  final double progress;
  final TextDirection textDirection;
  final double maxWidth;
  final TextPainter _brightPainter;
  final TextPainter _dimPainter;

  double get width => _brightPainter.width;
  double get height => _brightPainter.height;

  @override
  void paint(Canvas canvas, Size size) {
    _dimPainter.paint(canvas, Offset.zero);

    final totalChars = text.length;
    if (totalChars == 0) return;
    final filledChars = progress * totalChars;

    var lineStart = 0;
    while (lineStart < totalChars) {
      final boundary = _brightPainter.getLineBoundary(
        TextPosition(offset: lineStart),
      );
      final lineEnd = boundary.end;
      final lineChars = lineEnd - lineStart;
      if (lineChars <= 0) {
        break;
      }
      final lineFilled = filledChars - lineStart;
      if (lineFilled > 0) {
        final boxes = _brightPainter.getBoxesForSelection(
          TextSelection(baseOffset: lineStart, extentOffset: lineEnd),
        );
        if (boxes.isNotEmpty) {
          final box = boxes.first;
          final fraction = (lineFilled / lineChars).clamp(0.0, 1.0);
          if (fraction > 0) {
            canvas.save();
            canvas.clipRect(
              Rect.fromLTWH(
                box.left,
                box.top,
                (box.right - box.left) * fraction,
                box.bottom - box.top,
              ),
            );
            _brightPainter.paint(canvas, Offset.zero);
            canvas.restore();
          }
        }
      }
      lineStart = lineEnd;
    }
  }

  @override
  bool shouldRepaint(covariant _LineFillPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.maxWidth != maxWidth ||
        oldDelegate.textDirection != textDirection;
  }
}

class _LinePlacement {
  const _LinePlacement({
    required this.y,
    required this.translateZ,
    required this.rotateX,
    required this.scale,
    required this.opacity,
    required this.blur,
  });

  final double y;
  final double translateZ;
  final double rotateX;
  final double scale;
  final double opacity;
  final double blur;

  @override
  bool operator ==(Object other) {
    return other is _LinePlacement &&
        other.y == y &&
        other.translateZ == translateZ &&
        other.rotateX == rotateX &&
        other.scale == scale &&
        other.opacity == opacity &&
        other.blur == blur;
  }

  @override
  int get hashCode => Object.hash(y, translateZ, rotateX, scale, opacity, blur);
}

class _LinePlacementTween extends Tween<_LinePlacement> {
  _LinePlacementTween({
    required _LinePlacement begin,
    required _LinePlacement end,
  }) : super(begin: begin, end: end);

  @override
  _LinePlacement lerp(double t) {
    final b = begin!;
    final e = end!;
    return _LinePlacement(
      y: b.y + (e.y - b.y) * t,
      translateZ: b.translateZ + (e.translateZ - b.translateZ) * t,
      rotateX: b.rotateX + (e.rotateX - b.rotateX) * t,
      scale: b.scale + (e.scale - b.scale) * t,
      opacity: b.opacity + (e.opacity - b.opacity) * t,
      blur: b.blur + (e.blur - b.blur) * t,
    );
  }
}

class _LyricText extends StatelessWidget {
  const _LyricText({
    required this.line,
    required this.active,
    required this.position,
    this.styleOverride,
    this.textAlign = TextAlign.start,
    this.singleLine = false,
  });

  final LyricLine line;
  final bool active;
  final Duration position;
  final TextStyle? styleOverride;
  final TextAlign textAlign;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final style =
        styleOverride ??
        Theme.of(context).textTheme.headlineMedium!.copyWith(
          color: Colors.white,
          fontSize: active ? 34 : 27,
          height: 1.24,
          fontWeight: active ? FontWeight.w900 : FontWeight.w800,
        );

    if (!active || line.words.isEmpty) {
      if (singleLine) {
        return Text(
          line.text,
          textAlign: textAlign,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: style,
        );
      }
      return Text(line.text, textAlign: textAlign, style: style);
    }

    if (singleLine) {
      final painter = _KaraokeLinePainter(
        line: line,
        position: position,
        style: style,
        baseColor: Colors.white.withValues(alpha: .34),
        activeColor: Colors.white,
        textDirection: Directionality.of(context),
        textAlign: textAlign,
        maxLines: 1,
        maxWidth: double.infinity,
      );
      return CustomPaint(
        size: Size(painter.width, painter.height),
        painter: painter,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = _KaraokeLinePainter(
          line: line,
          position: position,
          style: style,
          baseColor: Colors.white.withValues(alpha: .34),
          activeColor: Colors.white,
          textDirection: Directionality.of(context),
          textAlign: textAlign,
          maxLines: null,
          maxWidth: constraints.maxWidth,
        );
        return CustomPaint(
          size: Size(constraints.maxWidth, painter.height),
          painter: painter,
        );
      },
    );
  }
}

class _KaraokeLinePainter extends CustomPainter {
  _KaraokeLinePainter({
    required this.line,
    required this.position,
    required this.style,
    required this.baseColor,
    required this.activeColor,
    required this.textDirection,
    required this.textAlign,
    required this.maxLines,
    required this.maxWidth,
  }) {
    _textPainter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: baseColor),
      ),
      textDirection: textDirection,
      textAlign: textAlign,
      maxLines: maxLines,
    )..layout(maxWidth: maxLines == 1 ? double.infinity : maxWidth);
  }

  final LyricLine line;
  final Duration position;
  final TextStyle style;
  final Color baseColor;
  final Color activeColor;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final int? maxLines;
  final double maxWidth;
  late final TextPainter _textPainter;

  double get width => _textPainter.width;
  double get height => _textPainter.height;

  @override
  void paint(Canvas canvas, Size size) {
    _textPainter.paint(canvas, Offset.zero);

    var start = 0;
    for (final word in line.words) {
      final end = start + word.text.length;
      final progress = _wordProgress(word);
      if (progress > 0) {
        _paintWordProgress(canvas, start, end, progress);
      }
      start = end;
    }
  }

  double _wordProgress(LyricWord word) {
    if (position < word.time) return 0;
    final durationMs = word.duration.inMilliseconds;
    if (durationMs <= 0) return 1;
    final elapsed = position.inMilliseconds - word.time.inMilliseconds;
    return (elapsed / durationMs).clamp(0, 1).toDouble();
  }

  void _paintWordProgress(Canvas canvas, int start, int end, double progress) {
    final selection = TextSelection(baseOffset: start, extentOffset: end);
    final boxes = _textPainter.getBoxesForSelection(selection);
    if (boxes.isEmpty) return;

    final highlightPainter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: activeColor),
      ),
      textDirection: textDirection,
      textAlign: textAlign,
      maxLines: maxLines,
    )..layout(maxWidth: maxLines == 1 ? double.infinity : maxWidth);

    for (final box in boxes) {
      final rect = box.toRect();
      final clipWidth = rect.width * progress.clamp(0, 1);
      if (clipWidth <= 0) continue;

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(rect.left, rect.top, clipWidth, rect.height));
      highlightPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KaraokeLinePainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.line != line ||
        oldDelegate.style != style ||
        oldDelegate.maxWidth != maxWidth;
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.player,
    this.bright = false,
    this.compact = false,
  });

  final PlayerController player;
  final bool bright;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final max = player.duration.inMilliseconds <= 0
        ? 1.0
        : player.duration.inMilliseconds.toDouble();
    final value = player.smoothPosition.inMilliseconds
        .clamp(0, max.toInt())
        .toDouble();
    final textColor = bright
        ? Colors.white.withValues(alpha: .64)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    // 高潮片段时间点（进度条小圆点），无高潮或无效时为空。
    final climax = player.climax;
    final climaxFraction = climax != null &&
            climax.isValid &&
            max > 0 &&
            climax.startTime.inMilliseconds <= max.toInt()
        ? climax.startTime.inMilliseconds / max
        : null;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final thumbRadius = compact ? 4.0 : 5.0;
            final dotSize = compact ? 7.0 : 8.0;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: compact ? 3 : 5,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: compact ? 4 : 5,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: compact ? 10 : 14,
                    ),
                    activeTrackColor: bright
                        ? Colors.white.withValues(alpha: .86)
                        : Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: bright
                        ? Colors.white.withValues(alpha: .25)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    max: max,
                    onChanged: (value) =>
                        player.previewSeek(
                            Duration(milliseconds: value.round())),
                    onChangeEnd: (value) =>
                        player.seek(Duration(milliseconds: value.round())),
                  ),
                ),
                if (climaxFraction != null)
                  Positioned(
                    left: thumbRadius +
                        climaxFraction * (width - 2 * thumbRadius) -
                        dotSize / 2,
                    top: 24 - dotSize / 2,
                    child: IgnorePointer(
                      child: Container(
                        width: dotSize,
                        height: dotSize,
                        decoration: BoxDecoration(
                          color: bright
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: bright
                                ? Colors.black.withValues(alpha: .4)
                                : Colors.white,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
          child: Row(
            children: [
              Text(
                formatDuration(player.smoothPosition),
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 12 : null,
                ),
              ),
              const Spacer(),
              Text(
                formatDuration(player.duration),
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 12 : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.player,
    required this.onQueue,
    this.bright = false,
    this.compactOverride = false,
    this.denseOverride = false,
  });

  final PlayerController player;
  final VoidCallback onQueue;
  final bool bright;
  final bool compactOverride;
  final bool denseOverride;

  @override
  Widget build(BuildContext context) {
    final color = bright
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = compactOverride || constraints.maxWidth < 360;
        final dense = denseOverride;
        // 超大按钮仅在车机模式开启时使用，普通横屏用标准尺寸。
        final isCar = isLandscape && ThemeController.instance.carModeEnabled;
        final edgeButtonSize = dense ? 34.0 : (isCar ? 56.0 : (compact ? 40.0 : 44.0));
        final edgeIconSize = dense ? 21.0 : (isCar ? 34.0 : (compact ? 24.0 : 27.0));
        final skipButtonSize = dense ? 42.0 : (isCar ? 72.0 : (compact ? 50.0 : 56.0));
        final skipIconSize = dense ? 33.0 : (isCar ? 54.0 : (compact ? 40.0 : 46.0));
        final playButtonSize = dense ? 58.0 : (isCar ? 96.0 : (compact ? 72.0 : 82.0));
        final playIconSize = dense ? 46.0 : (isCar ? 72.0 : (compact ? 56.0 : 64.0));
        final gap = dense ? 3.0 : (isCar ? 24.0 : (compact ? 5.0 : 9.0));

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: edgeButtonSize,
              child: IconButton(
                tooltip: player.playbackModeLabel,
                color: color,
                iconSize: edgeIconSize,
                padding: EdgeInsets.zero,
                onPressed: () {
                  player.cyclePlaybackMode();
                  Toast.show(
                    '已切换到${player.playbackModeLabel}',
                    duration: const Duration(milliseconds: 1100),
                  );
                },
                icon: Icon(_playbackModeIcon(player.playbackMode)),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: skipButtonSize,
              child: IconButton(
                tooltip: '上一首',
                color: color,
                iconSize: skipIconSize,
                padding: EdgeInsets.zero,
                onPressed: player.previous,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: playButtonSize,
              child: IconButton(
                tooltip: player.isPlaying ? '暂停' : '播放',
                color: color,
                padding: EdgeInsets.zero,
                onPressed: player.isPreparing ? null : player.togglePlay,
                iconSize: playIconSize,
                icon: player.isPreparing
                    ? SizedBox.square(
                        dimension: isCar ? 36 : (compact ? 24 : 28),
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: skipButtonSize,
              child: IconButton(
                tooltip: '下一首',
                color: color,
                iconSize: skipIconSize,
                padding: EdgeInsets.zero,
                onPressed: player.next,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: edgeButtonSize,
              child: IconButton(
                tooltip: '播放列表',
                color: color,
                iconSize: edgeIconSize,
                padding: EdgeInsets.zero,
                onPressed: onQueue,
                icon: const Icon(Icons.queue_music_rounded),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _playbackModeIcon(PlaybackMode mode) {
    return switch (mode) {
      PlaybackMode.playlistLoop => Icons.repeat_rounded,
      PlaybackMode.shuffle => Icons.shuffle_rounded,
      PlaybackMode.singleLoop => Icons.repeat_one_rounded,
    };
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          color: Colors.white,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _CommentEntry extends StatelessWidget {
  const _CommentEntry({required this.player, required this.song});

  final PlayerController player;
  final Song song;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 评论按钮（在左侧）
          if (song.source == SongSource.kugou)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  final mixsongid = song.albumAudioId ?? song.id;
                  if (mixsongid.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CommentPage(api: player.api, mixsongid: mixsongid),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Icon(
                    Icons.comment_outlined,
                    size: 20,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),

          if (song.source == SongSource.kugou) const SizedBox(width: 4),

          // 音乐游戏按钮（在评论按钮右侧）
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RhythmGamePage(player: player),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Icon(
                  Icons.sports_esports_outlined,
                  size: 22,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(2, (index) {
          final active = index == page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: active ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: active ? .86 : .32),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}
