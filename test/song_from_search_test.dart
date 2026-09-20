import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/models/music_models.dart';

void main() {
  /// 构造酷狗 /search 形态的标准歌曲数据。
  Map<String, dynamic> searchSong({
    String fileHash = 'HASH123',
    String fileName = '汪峰 - 春天里',
    String singerName = '汪峰',
    List<Map<String, dynamic>>? singers,
    String? oriSongName = '春天里',
    String suffix = '',
    bool includeFileName = true,
    String? songname,
  }) => {
    'FileHash': fileHash,
    'MixSongID': 32217207,
    if (includeFileName) 'FileName': fileName,
    'SingerName': singerName,
    'Singers': ?singers,
    'OriSongName': ?oriSongName,
    'Suffix': suffix,
    'Duration': 279,
  };

  group('Song.fromSearch（酷狗搜索）', () {
    test('OriSongName + Suffix 拼出完整歌名', () {
      final song = Song.fromSearch(
        searchSong(
          fileName: 'G.E.M.邓紫棋、方大同 - 春天里 (Live)',
          singerName: 'G.E.M.邓紫棋、方大同',
          singers: [
            {'id': 4490, 'name': 'G.E.M.邓紫棋'},
            {'id': 877, 'name': '方大同'},
          ],
          suffix: '(Live)',
        ),
      );
      expect(song.title, '春天里 (Live)');
      expect(song.artist, 'G.E.M.邓紫棋 / 方大同');
    });

    test('Suffix 为空时歌名无多余空格', () {
      final song = Song.fromSearch(searchSong());
      expect(song.title, '春天里');
    });

    test('缺失 OriSongName 时回退 FileName 并剥离歌手前缀', () {
      final song = Song.fromSearch(searchSong(oriSongName: null));
      expect(song.title, '春天里');
    });

    test('兜底剥离不误伤歌名本身含连字符的内容', () {
      final song = Song.fromSearch(
        searchSong(
          fileName: '汪峰 - 爱情 - Live版',
          oriSongName: null,
        ),
      );
      expect(song.title, '爱情 - Live版');
    });

    test('前缀与歌手名不一致时不剥离', () {
      final song = Song.fromSearch(
        searchSong(
          fileName: '旭日阳刚 - 春天里',
          singerName: '汪峰',
          oriSongName: null,
        ),
      );
      expect(song.title, '旭日阳刚 - 春天里');
    });

    test('无 FileName 时回退 songname 等备选字段', () {
      final json = searchSong(oriSongName: null, includeFileName: false)
        ..['songname'] = '春天里';
      expect(Song.fromSearch(json).title, '春天里');
    });

    test('所有歌名字段缺失时回退「未知歌曲」', () {
      final song = Song.fromSearch(
        searchSong(oriSongName: null, includeFileName: false),
      );
      expect(song.title, '未知歌曲');
    });
  });

  group('LatestListenResult.fromJson（最近播放）', () {
    test('历史接口无 OriSongName 时仍能从 FileName 得到干净歌名', () {
      final result = LatestListenResult.fromJson({
        'userid': '123',
        'cursor': 0,
        'has_more': 1,
        'songs': [
          {
            'FileHash': 'HASH_A',
            'FileName': '汪峰 - 春天里',
            'SingerName': '汪峰',
            'Suffix': '',
            'Duration': 279,
          },
          {
            'FileHash': 'HASH_B',
            'FileName': '周杰伦 - 晴天 (Live)',
            'SingerName': '周杰伦',
            'Suffix': '(Live)',
            'Duration': 269,
          },
        ],
      });
      expect(result.songs.map((s) => s.title).toList(), ['春天里', '晴天 (Live)']);
    });

    test('歌名字段全缺的异常条目回退「未知歌曲」而不抛异常', () {
      final result = LatestListenResult.fromJson({
        'songs': [
          {'FileHash': 'HASH_C', 'SingerName': '汪峰'},
        ],
      });
      expect(result.songs.single.title, '未知歌曲');
    });
  });

  group('stripArtistNamePrefix', () {
    test('多歌手分隔写法兼容', () {
      expect(stripArtistNamePrefix('汪峰、李荣浩 - 春天里', '汪峰 / 李荣浩'), '春天里');
      expect(stripArtistNamePrefix('汪峰&李荣浩 - 春天里', '汪峰 / 李荣浩'), '春天里');
      expect(stripArtistNamePrefix('汪峰 / 李荣浩 - 春天里', '汪峰 / 李荣浩'), '春天里');
    });

    test('歌手名含正则特殊字符', () {
      expect(
        stripArtistNamePrefix('G.E.M.邓紫棋 - 光年之外', 'G.E.M.邓紫棋'),
        '光年之外',
      );
    });

    test('空歌手名或空余歌名时原样返回', () {
      expect(stripArtistNamePrefix('汪峰 - 春天里', ''), '汪峰 - 春天里');
      expect(stripArtistNamePrefix('汪峰 - ', '汪峰'), '汪峰 - ');
    });
  });
}
