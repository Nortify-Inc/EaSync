/*!
 * @file account.dart
 * @brief Account page with profile, security and connected app sections.
 * @param No external parameters.
 * @return Account management widgets in EaSync tile/block style.
 * @author Erick Radmann
 */

import 'handler.dart';
import 'widgets/skeleton.dart';

class Account extends StatefulWidget {
  const Account({super.key});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> {
  bool _loading = true;
  final EaAppSettings _settings = EaAppSettings.instance;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.delayed(const Duration(milliseconds: 720));
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final pad = _settings.compactMode ? 14.0 : 20.0;

    return RefreshIndicator(
      color: EaColor.fore,
      onRefresh: _bootstrap,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
        children: [
          _header(),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: EaMotion.normal,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loading ? _loadingSummary() : _accountSummary(),
          ),
          const SizedBox(height: 10),
          EaFadeSlideIn(
            child: _block(
              title: 'Profile',
              children: const [
                _AccountTile(
                  icon: Icons.badge_outlined,
                  title: 'Personal info',
                  subtitle: 'Name, email and phone',
                ),
                _AccountTile(
                  icon: Icons.apartment_outlined,
                  title: 'Address and location',
                  subtitle: 'Home and room context',
                ),
                _AccountTile(
                  icon: Icons.language_outlined,
                  title: 'Language and region',
                  subtitle: 'Locale and formatting',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          EaFadeSlideIn(
            child: _block(
              title: 'Security',
              children: const [
                _AccountTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Password & passkeys',
                  subtitle: 'Credential management',
                ),
                _AccountTile(
                  icon: Icons.shield_moon_outlined,
                  title: '2-step verification',
                  subtitle: 'Additional sign-in protection',
                ),
                _AccountTile(
                  icon: Icons.devices_other_outlined,
                  title: 'Trusted devices',
                  subtitle: 'Current and recent sessions',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          EaFadeSlideIn(
            child: _block(
              title: 'Subscription',
              children: const [
                _AccountTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'EaSync Pro',
                  subtitle: 'Plan details and benefits',
                ),
                _AccountTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Billing history',
                  subtitle: 'Invoices and payment methods',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          EaFadeSlideIn(
            child: _block(
              title: 'Data controls',
              children: const [
                _AccountTile(
                  icon: Icons.download_outlined,
                  title: 'Export account data',
                  subtitle: 'Portable backup package',
                ),
                _AccountTile(
                  icon: Icons.delete_forever_outlined,
                  title: 'Delete account',
                  subtitle: 'Permanent removal workflow',
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: EaColor.fore.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EaColor.border),
          ),
          child: const Icon(Icons.person_outline_rounded, color: EaColor.fore),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account', style: EaText.primary),
              const SizedBox(height: 2),
              Text(
                'Manage your identity and preferences.',
                style: EaText.small.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const Settings()),
            );
          },
          icon: const Icon(Icons.settings_outlined),
          color: EaColor.fore,
        ),
      ],
    );
  }

  Widget _loadingSummary() {
    final enabled = EaAppSettings.instance.skeletonEnabled;
    if (!enabled) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('loading-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EaSkeleton(width: 160, height: 16),
          SizedBox(height: 12),
          EaSkeleton(width: 220, height: 12),
          SizedBox(height: 8),
          EaSkeleton(width: 180, height: 12),
        ],
      ),
    );
  }

  Widget _accountSummary() {
    return Container(
      key: const ValueKey('account-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Erick Radmann',
            style: EaText.secondary.copyWith(
              fontSize: 16,
              color: EaAdaptiveColor.bodyText(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'radmann@easync.io',
            style: EaText.small.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.verified_user_outlined, 'Verified'),
              _chip(Icons.security_outlined, '2FA active'),
              _chip(Icons.workspace_premium_outlined, 'Pro'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EaColor.fore.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EaColor.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: EaColor.fore),
          const SizedBox(width: 6),
          Text(label, style: EaText.small),
        ],
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
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: danger ? Colors.redAccent : EaColor.fore),
      title: Text(
        title,
        style: EaText.secondary.copyWith(
          color: danger ? Colors.redAccent : EaAdaptiveColor.bodyText(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: EaText.small.copyWith(
          color: EaAdaptiveColor.secondaryText(context),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: EaColor.textSecondary,
      ),
      onTap: () {},
    );
  }
}
