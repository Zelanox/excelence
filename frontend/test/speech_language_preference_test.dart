import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'speech language defaults to Arabic regardless of interface language',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({'interface_language': 'en'});
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      const preferences = AppPreferences();

      expect(await preferences.getSpeechLanguage(), 'ar_SA');

      await preferences.setSpeechLanguage('system');
      expect(await preferences.getSpeechLanguage(), 'system');
    },
  );
}
