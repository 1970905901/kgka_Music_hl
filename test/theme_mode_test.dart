import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/controllers/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController 外观模式测试', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认主题模式为跟随系统', () {
      final controller = ThemeController();
      expect(controller.themeMode, ThemeMode.system);
      expect(controller.themeModeLabel, '跟随系统');
    });

    test('切换主题模式并持久化生效', () async {
      final controller = ThemeController();
      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.themeModeLabel, '深色模式');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme.mode'), 'dark');

      // 重新加载后应保持深色模式
      final reloadedController = ThemeController();
      await reloadedController.load();
      expect(reloadedController.themeMode, ThemeMode.dark);

      // 切换浅色模式
      await reloadedController.setThemeMode(ThemeMode.light);
      expect(reloadedController.themeMode, ThemeMode.light);
      expect(reloadedController.themeModeLabel, '浅色模式');
      expect(prefs.getString('theme.mode'), 'light');
    });
  });
}
