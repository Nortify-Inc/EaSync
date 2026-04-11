/*!
 * @file settings.dart
 * @brief General settings page for app, AI and usage patterns.
 * @param No external parameters.
 * @return Stateful settings screen with persisted toggles.
 * @author Erick Radmann
 */

import 'handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final EaAppSettings _settings = EaAppSettings.instance;
  static const _kProfileLanguage = 'profile.language';
  static const _kTimeFormat24h = 'profile.time_24h';

  String _language = 'English';
  bool _time24h = true;

  static String _normalizeLanguageValue(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'portuguese' ||
        v == 'portugues' ||
        v == 'português' ||
        v == 'pt' ||
        v == 'pt-br') {
      return 'Portuguese';
    }
    return 'English';
  }

  @override
  void initState() {
    super.initState();
    _loadLocalizationSettings();
  }

  Future<void> _loadLocalizationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _language = _normalizeLanguageValue(
      prefs.getString(_kProfileLanguage) ?? '',
    );
    _time24h = prefs.getBool(_kTimeFormat24h) ?? true;
    if (mounted) setState(() {});
  }

  Future<void> _saveLocalizationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfileLanguage, _language);
    await prefs.setBool(_kTimeFormat24h, _time24h);
    EaAppSettings.instance.setLocaleFromProfileLanguage(_language);
  }

  Future<void> _persistAll() async {
    try {} catch (_) {}

    await _settings.persist();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _settings.themeMode != ThemeMode.light;

    return Scaffold(
      backgroundColor: EaAdaptiveColor.pageBackground(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
                const SizedBox(width: 4),
                Text(
                  EaI18n.t(context, 'Settings'),
                  style: EaText.primary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _block(
              title: EaI18n.t(context, 'General App'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: EaAdaptiveColor.field(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: EaAdaptiveColor.border(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.language_outlined,
                              color: EaColor.fore,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              EaI18n.t(context, 'Language'),
                              style: EaText.secondary.copyWith(
                                color: EaAdaptiveColor.bodyText(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          EaI18n.t(
                            context,
                            _language == 'Portuguese'
                                ? 'Portuguese'
                                : 'English',
                          ),
                          style: EaText.small.copyWith(
                            color: EaAdaptiveColor.secondaryText(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: EaAdaptiveColor.surface(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: EaAdaptiveColor.border(context),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _language,
                              isExpanded: true,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: EaAdaptiveColor.secondaryText(context),
                              ),
                              dropdownColor: EaAdaptiveColor.surface(context),
                              borderRadius: BorderRadius.circular(12),
                              style: EaText.secondary.copyWith(
                                color: EaAdaptiveColor.bodyText(context),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'English',
                                  child: Text(EaI18n.t(context, 'English')),
                                ),
                                DropdownMenuItem(
                                  value: 'Portuguese',
                                  child: Text(EaI18n.t(context, 'Portuguese')),
                                ),
                              ],
                              onChanged: (v) async {
                                if (v == null || v == _language) return;
                                setState(() => _language = v);
                                await _saveLocalizationSettings();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _switchTile(
                  icon: Icons.schedule_rounded,
                  title: EaI18n.t(context, '24h format'),
                  subtitle: EaI18n.t(
                    context,
                    'Use 24-hour time across schedules and labels',
                  ),
                  value: _time24h,
                  onChanged: (v) async {
                    setState(() => _time24h = v);
                    await _saveLocalizationSettings();
                  },
                ),
                _switchTile(
                  icon: Icons.dark_mode_outlined,
                  title: EaI18n.t(context, 'Dark mode'),
                  subtitle: EaI18n.t(context, 'Default visual mode for EaSync'),
                  value: isDark,
                  onChanged: (v) async {
                    await _settings.setThemeMode(
                      v ? ThemeMode.dark : ThemeMode.light,
                    );
                    if (mounted) setState(() {});
                  },
                ),
                _switchTile(
                  icon: Icons.animation_outlined,
                  title: EaI18n.t(context, 'Animations'),
                  subtitle: EaI18n.t(
                    context,
                    'Subtle transitions across pages and tiles',
                  ),
                  value: _settings.animationsEnabled,
                  onChanged: (v) async {
                    setState(() => _settings.animationsEnabled = v);
                    await _persistAll();
                  },
                ),

                _switchTile(
                  icon: Icons.vibration_outlined,
                  title: EaI18n.t(context, 'Haptic feedback'),
                  subtitle: EaI18n.t(
                    context,
                    'Micro feedback on primary interactions',
                  ),
                  value: _settings.hapticsEnabled,
                  onChanged: (v) async {
                    setState(() => _settings.hapticsEnabled = v);
                    await _persistAll();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _block(
              title: EaI18n.t(context, 'AI'),
              children: [
                _switchTile(
                  icon: Icons.location_on_outlined,
                  title: EaI18n.t(context, 'Use location data'),
                  subtitle: EaI18n.t(
                    context,
                    'Improve context and suggestions',
                  ),
                  value: _settings.aiUseLocationData,
                  onChanged: (v) async {
                    setState(() => _settings.aiUseLocationData = v);
                    await _persistAll();
                  },
                ),
                _switchTile(
                  icon: Icons.wb_sunny_outlined,
                  title: EaI18n.t(context, 'Use weather data'),
                  subtitle: EaI18n.t(context, 'Account for outdoor conditions'),
                  value: _settings.aiUseWeatherData,
                  onChanged: (v) async {
                    setState(() => _settings.aiUseWeatherData = v);
                    await _persistAll();
                  },
                ),
                _switchTile(
                  icon: Icons.history_toggle_off,
                  title: EaI18n.t(context, 'Use usage history'),
                  subtitle: EaI18n.t(context, 'Adapt to user patterns'),
                  value: _settings.aiUseUsageHistory,
                  onChanged: (v) async {
                    setState(() => _settings.aiUseUsageHistory = v);
                    await _persistAll();
                  },
                ),
                _switchTile(
                  icon: Icons.developer_board_outlined,
                  title: EaI18n.t(context, 'Allow device control'),
                  subtitle: EaI18n.t(
                    context,
                    'AI can execute commands on devices',
                  ),
                  value: _settings.aiAllowDeviceControl,
                  onChanged: (v) async {
                    setState(() => _settings.aiAllowDeviceControl = v);
                    await _persistAll();
                  },
                ),
                _switchTile(
                  icon: Icons.auto_awesome_outlined,
                  title: EaI18n.t(context, 'Allow auto routines'),
                  subtitle: EaI18n.t(
                    context,
                    'Enable autonomous routine execution',
                  ),
                  value: _settings.aiAllowAutoRoutines,
                  onChanged: (v) async {
                    setState(() => _settings.aiAllowAutoRoutines = v);
                    await _persistAll();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _block(
              title: EaI18n.t(context, 'Usage patterns'),
              children: [
                _switchTile(
                  icon: Icons.analytics_outlined,
                  title: EaI18n.t(context, 'Telemetry'),
                  subtitle: EaI18n.t(
                    context,
                    'Collect anonymous usage metrics',
                  ),
                  value: _settings.telemetryEnabled,
                  onChanged: (v) async {
                    setState(() => _settings.telemetryEnabled = v);
                    await _persistAll();
                  },
                ),
                _switchTile(
                  icon: Icons.cloud_off_outlined,
                  title: EaI18n.t(context, 'Offline cache'),
                  subtitle: EaI18n.t(
                    context,
                    'Keep recent state and responses locally',
                  ),
                  value: _settings.offlineCache,
                  onChanged: (v) async {
                    setState(() => _settings.offlineCache = v);
                    await _persistAll();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _block({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              title,
              style: EaText.secondary.copyWith(
                fontWeight: FontWeight.w700,
                color: EaAdaptiveColor.bodyText(context),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: EaColor.fore),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: EaText.small.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            activeThumbColor: EaColor.fore,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
