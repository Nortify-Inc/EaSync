/*!
 * @file settings.dart
 * @brief General settings page for app, AI and usage patterns.
 * @param No external parameters.
 * @return Stateful settings screen with persisted toggles.
 * @author Erick Radmann
 */

import 'handler.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final EaAppSettings _settings = EaAppSettings.instance;

  @override
  void initState() {
    super.initState();
    _syncAiPermissionsFromCore();
  }

  void _syncAiPermissionsFromCore() {
    try {
      final p = Bridge.getAiPermissions();
      _settings.aiUseLocationData = p.useLocationData;
      _settings.aiUseWeatherData = p.useWeatherData;
      _settings.aiUseUsageHistory = p.useUsageHistory;
      _settings.aiAllowDeviceControl = p.allowDeviceControl;
      _settings.aiAllowAutoRoutines = p.allowAutoRoutines;
      _settings.aiTemperament = p.temperament.clamp(0, 2);
    } catch (_) {}
  }

  Future<void> _persistAll() async {
    try {
      Bridge.setAiPermissions(
        AiPermissions(
          useLocationData: _settings.aiUseLocationData,
          useWeatherData: _settings.aiUseWeatherData,
          useUsageHistory: _settings.aiUseUsageHistory,
          allowDeviceControl: _settings.aiAllowDeviceControl,
          allowAutoRoutines: _settings.aiAllowAutoRoutines,
          temperament: _settings.aiTemperament,
        ),
      );
    } catch (_) {}

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
                  icon: Icons.compress_outlined,
                  title: EaI18n.t(context, 'Compact mode'),
                  subtitle: EaI18n.t(
                    context,
                    'Reduced paddings and denser tiles',
                  ),
                  value: _settings.compactMode,
                  onChanged: (v) async {
                    setState(() => _settings.compactMode = v);
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
                ListTile(
                  leading: const Icon(Icons.tune_rounded, color: EaColor.fore),
                  title: Text(
                    EaI18n.t(context, 'AI temperament'),
                    style: EaText.secondary,
                  ),
                  subtitle: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 220,
                      child: Slider(
                        value: _settings.aiTemperament.toDouble(),
                        min: 0,
                        max: 2,
                        divisions: 2,
                        label: switch (_settings.aiTemperament) {
                          0 => EaI18n.t(context, 'Balanced'),
                          1 => EaI18n.t(context, 'Fast'),
                          _ => EaI18n.t(context, 'Conservative'),
                        },
                        onChanged: (v) async {
                          setState(() => _settings.aiTemperament = v.round());
                          await _persistAll();
                        },
                      ),
                    ),
                  ),
                  trailing: Text(
                    switch (_settings.aiTemperament) {
                      0 => EaI18n.t(context, 'Balanced'),
                      1 => EaI18n.t(context, 'Fast'),
                      _ => EaI18n.t(context, 'Conservative'),
                    },
                    style: EaText.small.copyWith(color: EaColor.textSecondary),
                  ),
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
                _switchTile(
                  icon: Icons.data_saver_off_outlined,
                  title: EaI18n.t(context, 'Low data mode'),
                  subtitle: EaI18n.t(
                    context,
                    'Reduce background refresh and sync frequency',
                  ),
                  value: _settings.lowDataMode,
                  onChanged: (v) async {
                    setState(() => _settings.lowDataMode = v);
                    await _persistAll();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.route_outlined,
                    color: EaColor.fore,
                  ),
                  title: Text(
                    EaI18n.t(context, 'Usage profile'),
                    style: EaText.secondary,
                  ),
                  trailing: DropdownButton<String>(
                    value: _settings.usagePattern,
                    dropdownColor: EaAdaptiveColor.surface(context),
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: 'balanced',
                        child: Text(EaI18n.t(context, 'Balanced')),
                      ),
                      DropdownMenuItem(
                        value: 'automation',
                        child: Text(EaI18n.t(context, 'Automation')),
                      ),
                      DropdownMenuItem(
                        value: 'economy',
                        child: Text(EaI18n.t(context, 'Economy')),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _settings.usagePattern = v);
                      await _persistAll();
                    },
                  ),
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
    return SwitchListTile.adaptive(
      secondary: Icon(icon, color: EaColor.fore),
      title: Text(
        title,
        style: EaText.secondary.copyWith(
          color: EaAdaptiveColor.bodyText(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: EaText.small.copyWith(
          color: EaAdaptiveColor.secondaryText(context),
        ),
      ),
      activeColor: EaColor.fore,
      value: value,
      onChanged: onChanged,
    );
  }
}
