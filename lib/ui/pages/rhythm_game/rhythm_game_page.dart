import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../design_tokens.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../controllers/player_controller.dart';
import '../../widgets/artwork.dart';
import 'rhythm_beat_engine.dart';

/// 炫酷赛博朋克音游主页面（支持随时中途无缝进入、真实 24 频段 FFT 频谱、Fever 暴走、长键 Hold、金币 Bonus）
class RhythmGamePage extends StatefulWidget {
  const RhythmGamePage({
    super.key,
    required this.player,
  });

  final PlayerController player;

  @override
  State<RhythmGamePage> createState() => _RhythmGamePageState();
}

class _RhythmGamePageState extends State<RhythmGamePage>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<BeatNode> _beats;
  late List<Float32List> _spectrumFrames;

  // 连贯时间轴
  double _gameTimeMs = 0.0;
  Duration _lastFrameTime = Duration.zero;

  // Fever 暴走模式系统
  double _feverEnergy = 0.0; // 0.0 ~ 1.0
  bool _isFeverActive = false;
  double _feverTimeMs = 0.0; // 剩余暴走时间 (ms)
  static const double _maxFeverTimeMs = 8000.0;

  // 当前正在持握的长键
  BeatNode? _activeHoldNode;

  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _totalHits = 0;
  int _perfectCount = 0;
  int _greatCount = 0;
  int _goodCount = 0;
  int _missCount = 0;

  String? _lastJudgment;
  Color _lastJudgmentColor = Colors.white;
  double _judgmentScale = 1.0;

  // 屏幕震动位移
  Offset _shakeOffset = Offset.zero;

  // 特效系统
  final List<_ShockwaveRing> _shockwaves = [];
  final List<_Particle> _particles = [];
  final List<_Star> _stars = [];
  final math.Random _random = math.Random();

  bool _isPaused = false;
  bool _isGameOver = false;

  final double _speedPxPerMs = 0.65;

  @override
  void initState() {
    super.initState();
    final initialAudioMs = widget.player.position.inMilliseconds;
    _gameTimeMs = initialAudioMs.toDouble();

    _loadSongAndSpectrum(initialAudioMs);

    // 初始化星空背景粒子
    for (int i = 0; i < 40; i++) {
      _stars.add(_Star(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.001 + _random.nextDouble() * 0.003,
        size: 1.0 + _random.nextDouble() * 2.5,
      ));
    }

    _ticker = createTicker(_onTick);
    _ticker.start();

    if (!widget.player.isPlaying) {
      widget.player.play();
    }
  }

  void _loadSongAndSpectrum(int currentAudioMs) {
    final song = widget.player.currentSong;
    if (song != null) {
      _beats = RhythmBeatEngine.generateBeats(song);
      _spectrumFrames = RhythmBeatEngine.generateAudioSpectrum(song, _beats);

      // 【随时中途进入核心逻辑】：静默标记在此时间之前已播放过的旧音符，确保零失误提示、零卡顿！
      for (final node in _beats) {
        if (node.timeMs < currentAudioMs - 220) {
          node.hit = true;
          node.holdFinished = true;
        }
      }
    } else {
      _beats = [];
      _spectrumFrames = [];
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = _lastFrameTime == Duration.zero
        ? 0.016
        : (elapsed - _lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = elapsed;

    if (_isPaused || _isGameOver) return;

    final clampedDt = dt.clamp(0.0, 0.05);
    final realAudioMs = widget.player.position.inMilliseconds;

    // 平滑时间轴更新：每帧累加，微调 2% 消除长时漂移
    if (widget.player.isPlaying) {
      _gameTimeMs += clampedDt * 1000.0 * widget.player.playbackSpeed;
      final drift = realAudioMs - _gameTimeMs;
      if (drift.abs() > 500) {
        _gameTimeMs = realAudioMs.toDouble();
      } else {
        _gameTimeMs += drift * 0.02;
      }
    } else {
      _gameTimeMs = realAudioMs.toDouble();
    }

    final currentMsInt = _gameTimeMs.round();
    final totalDuration = widget.player.duration.inMilliseconds;

    // 1. Fever 暴走状态倒计时处理
    if (_isFeverActive) {
      _feverTimeMs -= clampedDt * 1000.0;
      _feverEnergy = (_feverTimeMs / _maxFeverTimeMs).clamp(0.0, 1.0);
      if (_feverTimeMs <= 0) {
        _isFeverActive = false;
        _feverEnergy = 0.0;
      }
    }

    // 2. 长键 (Hold Note) 持续按压得分逻辑
    if (_activeHoldNode != null) {
      final holdNode = _activeHoldNode!;
      if (currentMsInt <= holdNode.endMs) {
        final multiplier = _isFeverActive ? 2 : 1;
        _score += 8 * multiplier;
        _addFeverEnergy(0.003);

        final hitLineY = MediaQuery.of(context).size.height * 0.78;
        final nodeX = MediaQuery.of(context).size.width * holdNode.xRatio;
        _spawnParticles(Offset(nodeX, hitLineY), count: 2, isSuper: _isFeverActive);
      } else {
        holdNode.holdFinished = true;
        _activeHoldNode = null;
        final multiplier = _isFeverActive ? 2 : 1;
        _score += 300 * multiplier;
        _combo++;
        if (_combo > _maxCombo) _maxCombo = _combo;
        _addFeverEnergy(0.05);
        _lastJudgment = '完成!';
        _lastJudgmentColor = const Color(0xFF00FFCC);
        _judgmentScale = 1.3;
        HapticFeedback.mediumImpact();
      }
    }

    // 3. MISS 判定检测 (只针对进入游戏后滑过的未击中音符)
    for (final node in _beats) {
      if (!node.hit && currentMsInt - node.timeMs > 220) {
        node.hit = true;
        node.judgment = '失误';
        _onMiss();
      }
    }

    // 更新星空与特效
    _updateEffects(clampedDt);

    // 衰减屏幕震动
    _shakeOffset = _shakeOffset * 0.85;

    // 4. 到达歌曲尾端触发关卡完成
    if (totalDuration > 0 && currentMsInt >= totalDuration - 500) {
      _finishGame();
    }

    setState(() {});
  }

  void _addFeverEnergy(double amount) {
    if (_isFeverActive) return;

    _feverEnergy = (_feverEnergy + amount).clamp(0.0, 1.0);
    if (_feverEnergy >= 1.0) {
      _isFeverActive = true;
      _feverTimeMs = _maxFeverTimeMs;
      _triggerShake(12.0);

      final center = Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);
      _shockwaves.add(_ShockwaveRing(position: center, color: const Color(0xFF00FFCC), maxRadius: 400));
      _shockwaves.add(_ShockwaveRing(position: center, color: const Color(0xFFFF007F), maxRadius: 300));
      HapticFeedback.vibrate();
    }
  }

  void _onMiss() {
    _combo = 0;
    _missCount++;
    _totalHits++;
    _lastJudgment = '失误';
    _lastJudgmentColor = const Color(0xFFFF3366);
    _judgmentScale = 1.35;
    _triggerShake(6.0);
    if (_activeHoldNode != null) {
      _activeHoldNode = null;
    }
  }

  void _triggerShake(double intensity) {
    _shakeOffset = Offset(
      (_random.nextDouble() - 0.5) * intensity * 2,
      (_random.nextDouble() - 0.5) * intensity * 2,
    );
  }

  void _updateEffects(double dt) {
    final starSpeedMult = _isFeverActive ? 2.5 : 1.0;
    for (final star in _stars) {
      star.y += star.speed * starSpeedMult;
      if (star.y > 1.0) {
        star.y = 0.0;
        star.x = _random.nextDouble();
      }
    }

    _shockwaves.removeWhere((s) => s.isDead);
    for (final s in _shockwaves) {
      s.update();
    }

    _particles.removeWhere((p) => p.isDead);
    for (final p in _particles) {
      p.update();
    }
  }

  void _handleTap(TapDownDetails details) {
    if (_isPaused || _isGameOver) return;

    final currentMs = _gameTimeMs.round();
    final tapPos = details.localPosition;

    BeatNode? closestNode;
    int minDelta = 999999;

    for (final node in _beats) {
      if (!node.hit) {
        final delta = (node.timeMs - currentMs).abs();
        if (delta < minDelta) {
          minDelta = delta;
          closestNode = node;
        }
      }
    }

    if (closestNode == null || minDelta > 220) {
      _shockwaves.add(_ShockwaveRing(position: tapPos, color: Colors.white24, maxRadius: 30));
      HapticFeedback.selectionClick();
      return;
    }

    closestNode.hit = true;
    _totalHits++;

    final nodeX = MediaQuery.of(context).size.width * closestNode.xRatio;
    final hitLineY = MediaQuery.of(context).size.height * 0.78;
    final hitPoint = Offset(nodeX, hitLineY);

    final multiplier = _isFeverActive ? 2 : 1;

    if (closestNode.noteType == NoteType.bonus) {
      _score += 1000 * multiplier;
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      _perfectCount++;
      _addFeverEnergy(0.12);

      _lastJudgment = '奖励! +1000';
      _lastJudgmentColor = const Color(0xFFFFD700);
      _judgmentScale = 1.5;
      _triggerShake(7.0);

      _shockwaves.add(_ShockwaveRing(position: hitPoint, color: const Color(0xFFFFD700), maxRadius: 100));
      _spawnParticles(hitPoint, count: 28, isSuper: true);
      HapticFeedback.heavyImpact();
      return;
    }

    if (closestNode.noteType == NoteType.hold) {
      _activeHoldNode = closestNode;
      _score += 300 * multiplier;
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      _addFeverEnergy(0.04);

      _lastJudgment = '按住!';
      _lastJudgmentColor = const Color(0xFF00FFCC);
      _judgmentScale = 1.35;

      _shockwaves.add(_ShockwaveRing(position: hitPoint, color: const Color(0xFF00FFCC), maxRadius: 75));
      _spawnParticles(hitPoint, count: 18, isSuper: _isFeverActive);
      HapticFeedback.mediumImpact();
      return;
    }

    if (minDelta <= 60) {
      _score += (500 + (_combo * 10)) * multiplier;
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      _perfectCount++;
      _addFeverEnergy(0.04);

      _lastJudgment = '完美!';
      _lastJudgmentColor = const Color(0xFF00FFCC);
      _judgmentScale = 1.45;
      _triggerShake(8.0);

      _shockwaves.add(_ShockwaveRing(position: hitPoint, color: const Color(0xFF00FFCC), maxRadius: 90));
      _spawnParticles(hitPoint, count: 22, isSuper: _isFeverActive);
      HapticFeedback.heavyImpact();
    } else if (minDelta <= 130) {
      _score += (300 + (_combo * 5)) * multiplier;
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      _greatCount++;
      _addFeverEnergy(0.025);

      _lastJudgment = '优秀!';
      _lastJudgmentColor = const Color(0xFFFFD700);
      _judgmentScale = 1.25;
      _triggerShake(4.0);

      _shockwaves.add(_ShockwaveRing(position: hitPoint, color: const Color(0xFFFFD700), maxRadius: 65));
      _spawnParticles(hitPoint, count: 15, isSuper: false);
      HapticFeedback.mediumImpact();
    } else if (minDelta <= 200) {
      _score += 100 * multiplier;
      _combo++;
      if (_combo > _maxCombo) _maxCombo = _combo;
      _goodCount++;
      _addFeverEnergy(0.015);

      _lastJudgment = '良好';
      _lastJudgmentColor = const Color(0xFF4DEEEA);
      _judgmentScale = 1.15;

      _shockwaves.add(_ShockwaveRing(position: hitPoint, color: const Color(0xFF4DEEEA), maxRadius: 45));
      _spawnParticles(hitPoint, count: 10, isSuper: false);
      HapticFeedback.lightImpact();
    } else {
      _onMiss();
      HapticFeedback.vibrate();
    }
  }

  void _spawnParticles(Offset position, {required int count, required bool isSuper}) {
    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = (isSuper ? 3.5 : 2.0) + _random.nextDouble() * 6.0;
      final colors = [
        const Color(0xFF00FFCC),
        const Color(0xFFFF007F),
        const Color(0xFFFFD700),
        const Color(0xFF7000FF),
      ];
      _particles.add(_Particle(
        position: position,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        color: colors[i % colors.length],
        size: isSuper ? 4.5 : 3.0,
      ));
    }
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        widget.player.pause();
      } else {
        widget.player.play();
      }
    });
  }

  void _finishGame() {
    if (_isGameOver) return;
    setState(() {
      _isGameOver = true;
      _isPaused = true;
    });
    widget.player.pause();
  }

  double get _accuracy {
    if (_totalHits == 0) return 100.0;
    final weighted = (_perfectCount * 1.0 + _greatCount * 0.75 + _goodCount * 0.4) / _totalHits;
    return (weighted * 100).clamp(0.0, 100.0);
  }

  String get _grade {
    final acc = _accuracy;
    if (acc >= 95) return 'S';
    if (acc >= 85) return 'A';
    if (acc >= 75) return 'B';
    if (acc >= 60) return 'C';
    return 'D';
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.player.currentSong;

    return Scaffold(
      backgroundColor: const Color(0xFF06070C),
      body: Transform.translate(
        offset: _shakeOffset,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _handleTap,
          child: Stack(
            children: [
              // 1. 全粒子与 3D 跑道 Canvas 画布 (传入真实 24 频段音频 FFT 频谱数组)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RhythmGamePainter(
                    beats: _beats,
                    spectrumFrames: _spectrumFrames,
                    gameTimeMs: _gameTimeMs,
                    speedPxPerMs: _speedPxPerMs,
                    stars: _stars,
                    shockwaves: _shockwaves,
                    particles: _particles,
                    combo: _combo,
                    isFeverActive: _isFeverActive,
                  ),
                ),
              ),

              // 2. 顶栏：返回、歌曲信息、暂停
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF00FFCC), width: 0.8),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    if (song != null) ...[
                      Artwork(url: song.coverUrl, size: 40, borderRadius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(color: Color(0xFF00FFCC), blurRadius: 8)],
                              ),
                            ),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFFF007F), width: 0.8),
                      ),
                      icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      onPressed: _togglePause,
                    ),
                  ],
                ),
              ),

              // 3. 霓虹仪表盘（得分 & 准确率 & 暴走能量条）
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '得分',
                                  style: TextStyle(
                                    color: Color(0xFF00FFCC),
                                    fontSize: 12,
                                    letterSpacing: 2.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_isFeverActive) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF007F),
                                      borderRadius: BorderRadius.circular(AppRadius.xs),
                                      boxShadow: const [BoxShadow(color: Color(0xFFFF007F), blurRadius: 8)],
                                    ),
                                    child: const Text(
                                      '暴走 2X',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              _score.toString().padLeft(6, '0'),
                              style: TextStyle(
                                color: _isFeverActive ? const Color(0xFFFFD700) : Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                                shadows: [
                                  Shadow(
                                    color: _isFeverActive ? const Color(0xFFFFD700) : const Color(0xFF00FFCC),
                                    blurRadius: 12,
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              '准确率',
                              style: TextStyle(
                                color: Color(0xFFFF007F),
                                fontSize: 12,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${_accuracy.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(color: Color(0xFFFF007F), blurRadius: 12)],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 暴走能量条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: Container(
                        height: 8,
                        color: Colors.white12,
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: _feverEnergy,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: _isFeverActive
                                        ? [const Color(0xFFFF007F), const Color(0xFFFFD700), const Color(0xFF00FFCC)]
                                        : [const Color(0xFF00FFCC), const Color(0xFFFF007F)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isFeverActive ? const Color(0xFFFF007F) : const Color(0xFF00FFCC),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. 连击数 Combo 霓虹爆发
              if (_combo > 1)
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.26,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        '$_combo',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: _isFeverActive ? const Color(0xFFFFD700) : const Color(0xFF00FFCC),
                          shadows: [
                            Shadow(
                              color: _isFeverActive ? const Color(0xFFFF007F) : const Color(0xFF00FFCC),
                              blurRadius: 20,
                            ),
                            const Shadow(color: Color(0xFFFF007F), blurRadius: 40),
                          ],
                        ),
                      ),
                      const Text(
                        '连 击',
                        style: TextStyle(
                          fontSize: 15,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [Shadow(color: Color(0xFF00FFCC), blurRadius: 10)],
                        ),
                      ),
                    ],
                  ),
                ),

              // 5. 击打判定浮动提示 (完美 / 优秀 / 奖励! / 失误)
              if (_lastJudgment != null)
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.54,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedScale(
                      scale: _judgmentScale,
                      duration: const Duration(milliseconds: 90),
                      onEnd: () => setState(() => _judgmentScale = 1.0),
                      child: Text(
                        _lastJudgment!,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: _lastJudgmentColor,
                          shadows: [
                            Shadow(color: _lastJudgmentColor, blurRadius: 24),
                            const Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // 6. 底部触控提示
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: const Text(
                  '— 点击屏幕任意位置击打 —',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 7. 结算/暂停 Overlay
              if (_isPaused || _isGameOver)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101422),
                        borderRadius: BorderRadius.circular(AppRadius.xxl),
                        border: Border.all(color: const Color(0xFF00FFCC), width: 1.2),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFF00FFCC), blurRadius: 24, spreadRadius: -4),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isGameOver ? '关卡完成' : '游戏暂停',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: _isGameOver ? const Color(0xFF00FFCC) : Colors.white,
                              letterSpacing: 3,
                              shadows: [
                                Shadow(
                                  color: _isGameOver ? const Color(0xFF00FFCC) : Colors.cyanAccent,
                                  blurRadius: 16,
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isGameOver) ...[
                            Text(
                              _grade,
                              style: TextStyle(
                                fontSize: 80,
                                fontWeight: FontWeight.w900,
                                color: _grade == 'S'
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xFF00FFCC),
                                shadows: [
                                  Shadow(
                                    color: _grade == 'S'
                                        ? const Color(0xFFFFD700)
                                        : const Color(0xFF00FFCC),
                                    blurRadius: 30,
                                  ),
                                ],
                              ),
                            ),
                            Text('最终得分: $_score',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('最高连击: $_maxCombo',
                                style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            Text('准确率: ${_accuracy.toStringAsFixed(1)}%',
                                style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            Text('完美: $_perfectCount | 优秀: $_greatCount | 良好: $_goodCount | 失误: $_missCount',
                                style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            const SizedBox(height: 22),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white12,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.exit_to_app_rounded),
                                label: const Text('退出'),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00FFCC),
                                  foregroundColor: Colors.black,
                                  elevation: 8,
                                  shadowColor: const Color(0xFF00FFCC),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                                ),
                                onPressed: () {
                                  final initialMs = widget.player.position.inMilliseconds;
                                  setState(() {
                                    _score = 0;
                                    _combo = 0;
                                    _maxCombo = 0;
                                    _totalHits = 0;
                                    _perfectCount = 0;
                                    _greatCount = 0;
                                    _goodCount = 0;
                                    _missCount = 0;
                                    _feverEnergy = 0.0;
                                    _isFeverActive = false;
                                    _feverTimeMs = 0.0;
                                    _activeHoldNode = null;
                                    _isPaused = false;
                                    _isGameOver = false;
                                    _gameTimeMs = initialMs.toDouble();
                                    _lastJudgment = null;
                                    for (final b in _beats) {
                                      b.hit = false;
                                      b.holdFinished = false;
                                      b.judgment = null;
                                    }
                                  });
                                  widget.player.seek(Duration.zero);
                                  widget.player.play();
                                },
                                icon: const Icon(Icons.replay_rounded),
                                label: Text(_isGameOver ? '再玩一次' : '重新开始'),
                              ),
                            ],
                          ),
                        ],
                      ),
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

/// 炫酷赛博朋克 Canvas 渲染器 (对齐真实 24 频段音频 FFT 频谱能量、长键 Hold 拖尾、金币 Bonus 星芒)
class _RhythmGamePainter extends CustomPainter {
  _RhythmGamePainter({
    required this.beats,
    required this.spectrumFrames,
    required this.gameTimeMs,
    required this.speedPxPerMs,
    required this.stars,
    required this.shockwaves,
    required this.particles,
    required this.combo,
    required this.isFeverActive,
  });

  final List<BeatNode> beats;
  final List<Float32List> spectrumFrames;
  final double gameTimeMs;
  final double speedPxPerMs;
  final List<_Star> stars;
  final List<_ShockwaveRing> shockwaves;
  final List<_Particle> particles;
  final int combo;
  final bool isFeverActive;

  static final Paint _starPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _gridPaint = Paint()
    ..color = const Color(0xFF00FFCC).withValues(alpha: 0.10)
    ..strokeWidth = 1.0;

  static final Paint _laserLinePaint = Paint()
    ..color = const Color(0xFF00FFCC)
    ..strokeWidth = 3.5;

  static final Paint _laserGlowPaint = Paint()
    ..color = const Color(0xFF00FFCC).withValues(alpha: 0.4)
    ..strokeWidth = 10.0;

  static final Paint _normalPlatformPaint = Paint()
    ..color = const Color(0xFF00FFCC)
    ..style = PaintingStyle.fill;

  static final Paint _highPitchPlatformPaint = Paint()
    ..color = const Color(0xFFFF007F)
    ..style = PaintingStyle.fill;

  static final Paint _bonusPlatformPaint = Paint()
    ..color = const Color(0xFFFFD700)
    ..style = PaintingStyle.fill;

  static final Paint _hitPlatformPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.15)
    ..style = PaintingStyle.fill;

  static final Paint _glowHaloPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _spectrumBarPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _holdBeamPaint = Paint()..style = PaintingStyle.fill;

  static final Float32List _defaultSpectrum = Float32List(24);

  @override
  void paint(Canvas canvas, Size size) {
    final hitLineY = size.height * 0.78;
    final vanishingPoint = Offset(size.width * 0.5, size.height * 0.12);

    // 1. 背景深空星粒子 (Starfield)
    for (final star in stars) {
      _starPaint.color = isFeverActive
          ? const Color(0xFFFF007F).withValues(alpha: 0.4 + star.size * 0.2)
          : Colors.white.withValues(alpha: 0.2 + star.size * 0.15);
      canvas.drawCircle(Offset(star.x * size.width, star.y * size.height), star.size, _starPaint);
    }

    // 2. 3D 赛博网格跑道
    final gridColor = isFeverActive ? const Color(0xFFFF007F) : const Color(0xFF00FFCC);
    _gridPaint.color = gridColor.withValues(alpha: 0.12);

    final laneRatios = [0.12, 0.30, 0.50, 0.70, 0.88];
    for (final r in laneRatios) {
      final bottomX = size.width * r;
      canvas.drawLine(vanishingPoint, Offset(bottomX, size.height), _gridPaint);
    }

    // 3. 真实音频 24 频段 FFT 频谱能量柱 (与全曲重音和乐器 100% 对应!)
    const barCount = 24;
    final barWidth = size.width / barCount;

    final frameIndex = (gameTimeMs / 20).floor();
    final Float32List currentSpectrum;
    if (frameIndex >= 0 && frameIndex < spectrumFrames.length) {
      currentSpectrum = spectrumFrames[frameIndex];
    } else {
      currentSpectrum = _defaultSpectrum;
    }

    for (int i = 0; i < barCount; i++) {
      final amplitude = currentSpectrum[i];
      final height = 12.0 + (amplitude * 75.0);
      final x = i * barWidth;
      final y = size.height - height;

      final Color color;
      if (isFeverActive) {
        color = HSVColor.fromAHSV(1.0, (i * 15 + gameTimeMs * 0.4) % 360, 0.9, 1.0).toColor();
      } else {
        color = Color.lerp(
          const Color(0xFF00FFCC),
          const Color(0xFFFF007F),
          i / barCount,
        )!;
      }

      _spectrumBarPaint.color = color.withValues(alpha: isFeverActive ? 0.55 : 0.30);
      canvas.drawRect(Rect.fromLTWH(x + 2, y, barWidth - 4, height), _spectrumBarPaint);
    }

    // 4. 激光判定线 (Neon Laser Line)
    _laserLinePaint.color = isFeverActive ? const Color(0xFFFFD700) : const Color(0xFF00FFCC);
    _laserGlowPaint.color = (isFeverActive ? const Color(0xFFFF007F) : const Color(0xFF00FFCC)).withValues(alpha: 0.5);

    canvas.drawLine(Offset(0, hitLineY), Offset(size.width, hitLineY), _laserGlowPaint);
    canvas.drawLine(Offset(0, hitLineY), Offset(size.width, hitLineY), _laserLinePaint);

    // 5. 音符/平台节点 (包含 Hold 长键光束与 Bonus 金币星芒)
    const platformWidth = 82.0;
    const platformHeight = 18.0;

    for (final node in beats) {
      if (node.hit && node.judgment == '失误' && node.noteType != NoteType.hold) continue;
      if (node.holdFinished) continue;

      final startDeltaMs = node.timeMs - gameTimeMs;
      final startY = hitLineY - (startDeltaMs * speedPxPerMs);

      final nodeX = size.width * node.xRatio;

      if (node.noteType == NoteType.hold) {
        final endDeltaMs = node.endMs - gameTimeMs;
        final endY = hitLineY - (endDeltaMs * speedPxPerMs);

        if (endY < size.height + 60 && startY > -60) {
          final beamTop = math.min(startY, endY);
          final beamBottom = math.max(startY, endY);
          final beamHeight = math.max(10.0, beamBottom - beamTop);

          final beamRect = Rect.fromCenter(
            center: Offset(nodeX, beamTop + beamHeight / 2),
            width: platformWidth * 0.65,
            height: beamHeight,
          );

          _holdBeamPaint.shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF00FFCC).withValues(alpha: 0.8),
              const Color(0xFF7000FF).withValues(alpha: 0.5),
            ],
          ).createShader(beamRect);

          canvas.drawRRect(RRect.fromRectAndRadius(beamRect, const Radius.circular(AppRadius.xs)), _holdBeamPaint);
        }
      }

      if (startY < -40 || startY > size.height + 40) continue;

      final Paint mainPaint;
      if (node.hit) {
        mainPaint = _hitPlatformPaint;
      } else {
        mainPaint = switch (node.noteType) {
          NoteType.bonus => _bonusPlatformPaint,
          NoteType.highPitch => _highPitchPlatformPaint,
          _ => _normalPlatformPaint,
        };
      }

      if (node.noteType == NoteType.bonus && !node.hit) {
        final starRadius = platformHeight * 0.9;
        canvas.drawCircle(Offset(nodeX, startY), starRadius + 4, Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.35));
        canvas.drawCircle(Offset(nodeX, startY), starRadius, mainPaint);
      } else {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(nodeX, startY), width: platformWidth, height: platformHeight),
          const Radius.circular(9),
        );

        if (!node.hit) {
          final haloRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(nodeX, startY), width: platformWidth + 8, height: platformHeight + 8),
            const Radius.circular(AppRadius.md),
          );
          _glowHaloPaint.color = (node.noteType == NoteType.highPitch
                  ? const Color(0xFFFF007F)
                  : const Color(0xFF00FFCC))
              .withValues(alpha: 0.35);
          canvas.drawRRect(haloRect, _glowHaloPaint);
        }

        canvas.drawRRect(rect, mainPaint);
      }
    }

    // 6. 击打冲击波圈
    for (final s in shockwaves) {
      final ringPaint = Paint()
        ..color = s.color.withValues(alpha: s.alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;

      canvas.drawCircle(s.position, s.radius, ringPaint);
    }

    // 7. 击打高能爆炸粒子
    for (final p in particles) {
      final particlePaint = Paint()
        ..color = p.color.withValues(alpha: p.alpha)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p.position, p.size, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RhythmGamePainter oldDelegate) => true;
}

/// 星空粒子
class _Star {
  _Star({required this.x, required this.y, required this.speed, required this.size});
  double x;
  double y;
  double speed;
  double size;
}

/// 冲击波环实体
class _ShockwaveRing {
  _ShockwaveRing({required this.position, required this.color, required this.maxRadius});

  final Offset position;
  final Color color;
  final double maxRadius;
  double radius = 10.0;
  double alpha = 1.0;

  bool get isDead => alpha <= 0 || radius >= maxRadius;

  void update() {
    radius += (maxRadius - radius) * 0.22 + 2.0;
    alpha -= 0.06;
    if (alpha < 0) alpha = 0;
  }
}

/// 爆炸粒子实体
class _Particle {
  _Particle({required this.position, required this.velocity, required this.color, this.size = 3.5});

  Offset position;
  Offset velocity;
  Color color;
  double size;
  double alpha = 1.0;

  bool get isDead => alpha <= 0;

  void update() {
    position += velocity;
    velocity *= 0.94; // 阻力
    alpha -= 0.035;
    size = math.max(0, size - 0.06);
    if (alpha < 0) alpha = 0;
  }
}
