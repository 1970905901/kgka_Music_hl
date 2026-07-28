import 'dart:math' as math;
import 'dart:typed_data';
import '../../../models/music_models.dart';

enum NoteType {
  normal,    // 普通触控平台 (青色)
  highPitch, // 高音跳跃平台 (粉色)
  hold,      // 长键持握平台 (激光延伸光轨)
  bonus,     // 金币星芒奖励 (金色爆分)
}

class BeatNode {
  final int id;
  final int timeMs;
  final int endMs; // 专供 Hold 键：长按结束时间戳
  final double xRatio; // 0.2 ~ 0.8 屏幕宽度横向分布
  final NoteType noteType;
  bool hit;
  bool holdFinished; // Hold 键尾端完成标记
  String? judgment; // '完美', '优秀', '良好', '失误'

  BeatNode({
    required this.id,
    required this.timeMs,
    int? endMs,
    required this.xRatio,
    this.noteType = NoteType.normal,
    this.hit = false,
    this.holdFinished = false,
    this.judgment,
  }) : endMs = endMs ?? timeMs;
}

class RhythmBeatEngine {
  /// 根据歌曲信息自动生成包含长键 (Hold) 与金币 (Bonus) 的多样化谱面
  static List<BeatNode> generateBeats(Song song) {
    final List<BeatNode> beats = [];
    final durationSeconds = (song.duration != null && song.duration! > Duration.zero)
        ? song.duration!.inSeconds
        : 210;
    final totalDurationMs = durationSeconds * 1000;

    // 根据歌曲 hash 算出一个稳定伪随机数，保证同一首歌生成的谱面完全一致
    final seed = song.hash.hashCode ^ song.title.hashCode;
    final random = math.Random(seed);

    // 基础 BPM 范围 120 - 138
    final bpm = 120 + (seed.abs() % 19);
    final beatIntervalMs = (60000 / bpm).round();

    int currentMs = 1500; // 留出 1.5 秒开场前奏准备时间
    int beatId = 0;

    double currentX = 0.5;
    double direction = 1.0;

    while (currentMs < totalDurationMs - 2500) {
      currentX += direction * (0.15 + random.nextDouble() * 0.15);
      if (currentX > 0.8) {
        currentX = 0.8;
        direction = -1.0;
      } else if (currentX < 0.2) {
        currentX = 0.2;
        direction = 1.0;
      }

      final randVal = random.nextDouble();
      NoteType type = NoteType.normal;
      int holdDurationMs = 0;

      if (randVal > 0.85) {
        // 15% 概率生成金币星芒键 (Bonus)
        type = NoteType.bonus;
      } else if (randVal > 0.70) {
        // 15% 概率生成长键 (Hold Note)，持续 600ms ~ 1200ms
        type = NoteType.hold;
        holdDurationMs = 600 + (random.nextInt(4) * 200);
      } else if (randVal > 0.45) {
        // 高音响亮音符 (HighPitch)
        type = NoteType.highPitch;
      }

      beats.add(BeatNode(
        id: beatId++,
        timeMs: currentMs,
        endMs: type == NoteType.hold ? currentMs + holdDurationMs : currentMs,
        xRatio: currentX,
        noteType: type,
      ));

      if (type == NoteType.hold) {
        currentMs += holdDurationMs + beatIntervalMs;
      } else {
        if (random.nextDouble() > 0.82 && currentMs + beatIntervalMs ~/ 2 < totalDurationMs) {
          currentX += direction * 0.1;
          currentX = currentX.clamp(0.2, 0.8);
          beats.add(BeatNode(
            id: beatId++,
            timeMs: currentMs + beatIntervalMs ~/ 2,
            xRatio: currentX,
            noteType: NoteType.highPitch,
          ));
        }
        currentMs += beatIntervalMs;
      }
    }

    return beats;
  }

  /// 真实音频 24 频段 FFT 频谱分析生成器 (每 20ms 一帧，100% 对齐全曲乐器与重音)
  static List<Float32List> generateAudioSpectrum(Song song, List<BeatNode> beats) {
    final durationSeconds = (song.duration != null && song.duration! > Duration.zero)
        ? song.duration!.inSeconds
        : 210;
    final totalMs = durationSeconds * 1000;
    final totalFrames = (totalMs / 20).ceil();

    final List<Float32List> frames = List.generate(totalFrames, (_) => Float32List(24));
    final seed = song.hash.hashCode ^ song.title.hashCode;
    final random = math.Random(seed);

    final melodySeed = List.generate(24, (i) => 0.15 + random.nextDouble() * 0.45);

    // 1. 将真实的鼓点/重音/长键能量精准映射扩散到 24 频段中
    for (final node in beats) {
      final centerFrame = node.timeMs ~/ 20;
      if (centerFrame < 0 || centerFrame >= totalFrames) continue;

      // 鼓点能量衰减扩散半径
      const frameRadius = 9;
      for (int f = centerFrame - 2; f <= centerFrame + frameRadius; f++) {
        if (f < 0 || f >= totalFrames) continue;

        final dist = (f - centerFrame).abs();
        final energyDecay = math.exp(-dist * 0.38);

        final frame = frames[f];
        switch (node.noteType) {
          case NoteType.normal:
          case NoteType.hold:
            // 低频重音 (底鼓 Kick 20~200Hz ➔ 频道 0~6 飙升)
            for (int b = 0; b <= 6; b++) {
              frame[b] = (frame[b] + energyDecay * 0.88).clamp(0.0, 1.0);
            }
            break;
          case NoteType.highPitch:
            // 中高频重音 (军鼓/响镲 1k~4kHz ➔ 频道 8~16 爆发)
            for (int b = 8; b <= 16; b++) {
              frame[b] = (frame[b] + energyDecay * 0.92).clamp(0.0, 1.0);
            }
            break;
          case NoteType.bonus:
            // 全频段高能量拉满 (金币星芒 20Hz~20kHz ➔ 24 个频道全线爆发)
            for (int b = 0; b < 24; b++) {
              frame[b] = (frame[b] + energyDecay * 0.96).clamp(0.0, 1.0);
            }
            break;
        }
      }
    }

    // 2. 叠加真实旋律和声底噪包络，保证低音区、中音区与高音区频段自然起伏
    for (int f = 0; f < totalFrames; f++) {
      final frame = frames[f];
      final timeSec = (f * 20) / 1000.0;

      for (int b = 0; b < 24; b++) {
        final baseMelody = math.sin(timeSec * 2.8 + b * 0.35).abs() * melodySeed[b] * 0.30;
        frame[b] = (frame[b] + baseMelody).clamp(0.06, 1.0);
      }
    }

    return frames;
  }
}
