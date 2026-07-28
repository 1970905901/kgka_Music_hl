import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/core/pinyin_utils.dart';

void main() {
  test('Pinyin sorting for artists', () {
    final artists = [
      '周杰伦',
      'Adele',
      '陈奕迅',
      '邓紫棋',
      'Beyoncé',
      '张学友',
    ];

    artists.sort(PinyinUtils.comparePinyin);

    // Expected order by Pinyin / alphabetical:
    // Adele (adele)
    // Beyoncé (beyonce)
    // 陈奕迅 (chenyixun)
    // 邓紫棋 (dengziqi)
    // 张学友 (zhangxueyou)
    // 周杰伦 (zhoujielun)
    expect(artists, [
      'Adele',
      'Beyoncé',
      '陈奕迅',
      '邓紫棋',
      '张学友',
      '周杰伦',
    ]);
  });

  test('Chinese characters sorted by Pinyin vs stroke order', () {
    final artists = ['张三', '安安', '包包'];
    artists.sort(PinyinUtils.comparePinyin);

    // 安安 (anan) -> 包包 (baobao) -> 张三 (zhangsan)
    expect(artists, ['安安', '包包', '张三']);
  });
}
