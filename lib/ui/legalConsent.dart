/*!
 * @file legal_consent.dart
 * @brief One-time legal consent screen with localized legal articles.
 * @param None.
 * @return Consent payload for startup gating.
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'handler.dart';
import 'auth/provider.dart';
import 'auth/security.dart';
import 'auth/service.dart';

class LegalConsentPayload {
  final bool contractsAccepted;
  final bool privacyTermsAccepted;

  const LegalConsentPayload({
    required this.contractsAccepted,
    required this.privacyTermsAccepted,
  });
}

class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({super.key});

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  bool _contractsAccepted = false;
  bool _privacyTermsAccepted = false;
  bool _authBusy = false;
  bool _authenticated = false;
  String _authLabel = '';

  bool get _isPtBr => Localizations.localeOf(context).languageCode == 'pt';
  bool get _isIosOrMac => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    final saved = await OAuthService.instance.getSavedProfile();
    if (!mounted) return;
    setState(() {
      _authenticated = saved != null;
      _authLabel = saved?.provider ?? '';
    });
  }

  Future<void> _loginWith(OAuthProvider provider) async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      final profile = await OAuthService.instance.login(provider);

      final security = await AppSecurityService.instance
          .readStartupSecurityState();
      if (security.requiresAuthenticatorCode) {
        var unlocked = false;
        var attempts = 0;
        while (mounted && attempts < 5) {
          attempts++;
          final normalized = await _askAuthenticatorCodeForLogin();
          if (!mounted || normalized == null) break;

          final ok = await AppSecurityService.instance.verifyAuthenticatorCode(
            normalized,
          );
          if (ok) {
            unlocked = true;
            break;
          }

          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(EaI18n.t(context, 'Invalid code. Try again.')),
              ),
            );
        }

        if (!unlocked) {
          await OAuthService.instance.logout();
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(EaI18n.t(context, 'Sign-in failed.')),
              ),
            );
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _authenticated = true;
        _authLabel = profile.provider;
      });
    } on OAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(e.message),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _isPtBr
                  ? 'Erro inesperado durante o login: $e'
                  : 'Unexpected login error: $e',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<String?> _askAuthenticatorCodeForLogin() async {
    final controller = TextEditingController();
    var invalid = false;

    try {
      return await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocalState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: EaAdaptiveColor.surface(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: EaAdaptiveColor.border(context),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EaI18n.t(
                              context,
                              'Enter your 6-digit verification code to continue.',
                            ),
                            style: EaText.small.copyWith(
                              color: EaAdaptiveColor.secondaryText(context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: InputDecoration(
                              hintText: '123456',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          if (invalid) ...[
                            const SizedBox(height: 8),
                            Text(
                              EaI18n.t(context, 'Invalid code.'),
                              style: EaText.small.copyWith(
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: EaColor.fore,
                                foregroundColor: EaColor.back,
                              ),
                              onPressed: () {
                                final normalized = controller.text.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
                                if (normalized.length != 6) {
                                  setLocalState(() => invalid = true);
                                  return;
                                }
                                Navigator.of(ctx).pop(normalized);
                              },
                              child: Text(EaI18n.t(context, 'Verify')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openArticle(_LegalArticleType type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalArticlePage(
          articleType: type == _LegalArticleType.contracts
              ? LegalArticleType.contracts
              : LegalArticleType.privacyTerms,
          isPtBr: _isPtBr,
        ),
      ),
    );
  }

  void _continue() {
    if (!_authenticated) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _isPtBr
                  ? 'Faça login com um provedor para continuar.'
                  : 'Sign in with a provider to continue.',
            ),
          ),
        );
      return;
    }

    if (!_contractsAccepted || !_privacyTermsAccepted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _isPtBr
                  ? 'Você precisa aceitar os dois itens para continuar.'
                  : 'You must accept both items to continue.',
            ),
          ),
        );
      return;
    }

    Navigator.pop(
      context,
      LegalConsentPayload(
        contractsAccepted: _contractsAccepted,
        privacyTermsAccepted: _privacyTermsAccepted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isPtBr ? 'Antes de entrar' : 'Before you continue';
    final subtitle = _isPtBr
        ? 'Para continuar o login, leia e aceite os documentos legais.'
        : 'To continue to login, read and accept the legal documents.';

    return Scaffold(
      backgroundColor: EaAdaptiveColor.pageBackground(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heroHeader(title: title, subtitle: subtitle),
              const SizedBox(height: 16),
              _authCard(),
              const SizedBox(height: 14),
              Text(
                _isPtBr ? 'Consentimento legal' : 'Legal consent',
                style: EaText.secondary.copyWith(
                  color: EaAdaptiveColor.bodyText(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              _consentTile(
                value: _contractsAccepted,
                onChanged: (v) => setState(() => _contractsAccepted = v),
                spans: _contractsSpans(),
              ),
              const SizedBox(height: 10),
              _consentTile(
                value: _privacyTermsAccepted,
                onChanged: (v) => setState(() => _privacyTermsAccepted = v),
                spans: _privacyTermsSpans(),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: EaColor.fore,
                    foregroundColor: EaColor.back,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _authBusy ? null : _continue,
                  child: Text(_isPtBr ? 'Continuar' : 'Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _consentTile({
    required bool value,
    required ValueChanged<bool> onChanged,
    required List<InlineSpan> spans,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: RichText(
                text: TextSpan(
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                    height: 1.35,
                  ),
                  children: spans,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _linkSpan(String text, VoidCallback onTap) {
    return TextSpan(
      text: text,
      style: EaText.secondary.copyWith(
        color: EaColor.fore,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = onTap,
    );
  }

  Widget _heroHeader({required String title, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            EaColor.fore.withValues(alpha: 0.22),
            EaAdaptiveColor.field(context).withValues(alpha: 0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: EaColor.fore.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_rounded, color: EaColor.fore),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: EaText.primary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _authCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isPtBr ? 'Entrar com provedor' : 'Sign in with provider',
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          if (_authenticated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: EaColor.fore.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EaColor.fore.withValues(alpha: 0.28)),
              ),
              child: Text(
                _isPtBr
                    ? 'Autenticado via ${_authLabel.isEmpty ? 'provedor' : _authLabel}'
                    : 'Signed in with ${_authLabel.isEmpty ? 'provider' : _authLabel}',
                style: EaText.small.copyWith(
                  color: EaAdaptiveColor.bodyText(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_authenticated) const SizedBox(height: 8),
          _providerButton(
            label: 'Google',
            icon: const _GoogleIcon(),
            onTap: () => _loginWith(OAuthProvider.google),
          ),
          const SizedBox(height: 8),
          _providerButton(
            label: 'Microsoft',
            icon: const _MicrosoftIcon(),
            onTap: () => _loginWith(OAuthProvider.microsoft),
          ),
          if (_isIosOrMac) ...[
            const SizedBox(height: 8),
            _providerButton(
              label: 'Apple',
              icon: Icon(
                Icons.apple_rounded,
                color: EaAdaptiveColor.bodyText(context),
              ),
              onTap: () => _loginWith(OAuthProvider.apple),
            ),
          ],
        ],
      ),
    );
  }

  Widget _providerButton({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _authBusy ? null : onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: EaAdaptiveColor.border(context)),
          backgroundColor: EaAdaptiveColor.field(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: icon)),
            const SizedBox(width: 10),
            Text(
              label,
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.bodyText(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_authBusy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _contractsSpans() {
    if (_isPtBr) {
      return [
        const TextSpan(text: 'Li e aceito os '),
        _linkSpan('Contratos', () => _openArticle(_LegalArticleType.contracts)),
        const TextSpan(text: '.'),
      ];
    }

    return [
      const TextSpan(text: 'I have read and accept the '),
      _linkSpan('Contracts', () => _openArticle(_LegalArticleType.contracts)),
      const TextSpan(text: '.'),
    ];
  }

  List<InlineSpan> _privacyTermsSpans() {
    if (_isPtBr) {
      return [
        const TextSpan(text: 'Li e aceito a '),
        _linkSpan(
          'Política de Privacidade',
          () => _openArticle(_LegalArticleType.privacyTerms),
        ),
        const TextSpan(text: ' e os '),
        _linkSpan(
          'Termos de Uso',
          () => _openArticle(_LegalArticleType.contracts),
        ),
        const TextSpan(text: '.'),
      ];
    }

    return [
      const TextSpan(text: 'I have read and accept the '),
      _linkSpan(
        'Privacy Policy',
        () => _openArticle(_LegalArticleType.privacyTerms),
      ),
      const TextSpan(text: ' and the '),
      _linkSpan(
        'Terms of Use',
        () => _openArticle(_LegalArticleType.contracts),
      ),
      const TextSpan(text: '.'),
    ];
  }
}

enum _LegalArticleType { contracts, privacyTerms }

enum LegalArticleType { contracts, privacyTerms }

class LegalArticlePage extends StatelessWidget {
  final LegalArticleType articleType;
  final bool isPtBr;

  const LegalArticlePage({
    super.key,
    required this.articleType,
    required this.isPtBr,
  });

  @override
  Widget build(BuildContext context) {
    final doc = _buildDoc();

    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [...doc.sections.map((s) => _section(context, s))],
      ),
    );
  }

  Widget _section(BuildContext context, _DocSection section) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: EaText.small.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  _DocContent _buildDoc() {
    if (isPtBr) {
      return articleType == LegalArticleType.contracts
          ? _contractsPt()
          : _privacyTermsPt();
    }
    return articleType == LegalArticleType.contracts
        ? _contractsEn()
        : _privacyTermsEn();
  }

  _DocContent _contractsPt() {
    return const _DocContent(
      title: 'Contratos',
      sections: [
        _DocSection(
          title: '1. Objeto',
          body:
              'Este contrato regula o acesso e uso do aplicativo EaSync e seus módulos associados.',
        ),
        _DocSection(
          title: '2. Elegibilidade e Conta',
          body:
              'Você declara possuir capacidade legal para contratar e manter dados de conta verdadeiros e atualizados.',
        ),
        _DocSection(
          title: '3. Uso Permitido',
          body:
              'É proibido utilizar o app para atividades ilícitas, abusivas, fraudulentas, discriminatórias, violentas ou ofensivas.',
        ),
        _DocSection(
          title: '4. IA e Conduta',
          body:
              'Você deve usar os recursos de IA de forma ética e legal. Conteúdos inapropriados, desrespeitosos, ofensivos, assediadores ou ilegais são estritamente proibidos.',
        ),
        _DocSection(
          title: '5. Responsabilização do Usuário',
          body:
              'Você assume responsabilidade integral e exclusiva por comandos, prompts, respostas geradas, publicações, compartilhamentos e qualquer dano decorrente de uso indevido da IA, incluindo geração de conteúdo inapropriado ou desrespeitoso.',
        ),
        _DocSection(
          title: '6. Limitação e Suspensão',
          body:
              'A plataforma pode limitar ou suspender acesso em caso de violação contratual, risco técnico, segurança ou exigência legal.',
        ),
      ],
    );
  }

  _DocContent _privacyTermsPt() {
    return const _DocContent(
      title: 'Política de Privacidade e Termos de Uso',
      sections: [
        _DocSection(
          title: '1. Dados Coletados',
          body:
              'Podem ser processados dados de conta, telemetria de uso, informações técnicas do dispositivo e preferências do aplicativo.',
        ),
        _DocSection(
          title: '2. Finalidades',
          body:
              'Os dados são usados para autenticação, segurança, estabilidade, melhoria de experiência e funcionamento dos serviços.',
        ),
        _DocSection(
          title: '3. Base Legal e Retenção',
          body:
              'O tratamento ocorre conforme bases legais aplicáveis e retenção mínima necessária para operação, conformidade e segurança.',
        ),
        _DocSection(
          title: '4. Direitos do Usuário',
          body:
              'Você pode solicitar acesso, correção, atualização e remoção de dados, quando aplicável por lei.',
        ),
        _DocSection(
          title: '5. Termos de Uso da IA',
          body:
              'O usuário é responsável por revisar as respostas antes de aplicá-las. A IA pode produzir conteúdo incorreto, incompleto ou inadequado. Não utilize IA para violar leis, direitos de terceiros ou políticas da plataforma.',
        ),
        _DocSection(
          title: '6. Responsabilidade por Conteúdo',
          body:
              'Você assume total responsabilidade por qualquer conteúdo gerado, solicitado, armazenado ou compartilhado a partir do app, incluindo conteúdo inapropriado, desrespeitoso ou ilícito.',
        ),
      ],
    );
  }

  _DocContent _contractsEn() {
    return const _DocContent(
      title: 'Contracts',
      sections: [
        _DocSection(
          title: '1. Scope',
          body:
              'This agreement governs access to and use of the EaSync application and related modules.',
        ),
        _DocSection(
          title: '2. Eligibility and Account',
          body:
              'You represent that you are legally capable of entering into this agreement and keeping account data accurate.',
        ),
        _DocSection(
          title: '3. Acceptable Use',
          body:
              'Using the app for unlawful, abusive, fraudulent, discriminatory, violent, or offensive activities is prohibited.',
        ),
        _DocSection(
          title: '4. AI Usage and Conduct',
          body:
              'AI features must be used ethically and lawfully. Inappropriate, disrespectful, offensive, harassing, or illegal content is strictly prohibited.',
        ),
        _DocSection(
          title: '5. User Liability',
          body:
              'You assume full and exclusive responsibility for prompts, generated responses, publications, sharing, and any harm resulting from misuse of AI, including generation of inappropriate or disrespectful content.',
        ),
        _DocSection(
          title: '6. Restrictions and Suspension',
          body:
              'The platform may limit or suspend access in case of policy breach, technical risk, security concerns, or legal requirements.',
        ),
      ],
    );
  }

  _DocContent _privacyTermsEn() {
    return const _DocContent(
      title: 'Privacy Policy',
      sections: [
        _DocSection(
          title: '1. Data Collected',
          body:
              'Account data, usage telemetry, device technical information, and app preferences may be processed.',
        ),
        _DocSection(
          title: '2. Purposes',
          body:
              'Data is used for authentication, security, reliability, product improvement, and service operation.',
        ),
        _DocSection(
          title: '3. Legal Basis and Retention',
          body:
              'Processing follows applicable legal bases and data is retained only as needed for operations, compliance, and security.',
        ),
        _DocSection(
          title: '4. User Rights',
          body:
              'Where applicable, you may request access, correction, update, and deletion of personal data.',
        ),
        _DocSection(
          title: '5. AI Terms of Use',
          body:
              'You are responsible for reviewing AI outputs before using them. AI may produce incorrect, incomplete, or inappropriate content. Do not use AI to violate laws, third-party rights, or platform policies.',
        ),
        _DocSection(
          title: '6. Content Responsibility',
          body:
              'You accept full responsibility for any content generated, requested, stored, or shared through the app, including inappropriate, disrespectful, or unlawful content.',
        ),
      ],
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: Image.asset(
      'assets/images/google.png',
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => CustomPaint(painter: _GooglePainter()),
    ),
  );
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);

    final stroke = size.width * 0.18;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    double deg(double v) => v * pi / 180.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    paint.color = red;
    canvas.drawArc(rect, deg(-40), deg(85), false, paint);

    paint.color = yellow;
    canvas.drawArc(rect, deg(45), deg(90), false, paint);

    paint.color = green;
    canvas.drawArc(rect, deg(135), deg(90), false, paint);

    paint.color = blue;
    canvas.drawArc(rect, deg(225), deg(95), false, paint);

    final barHeight = stroke * 0.7;
    final barTop = center.dy - barHeight / 2;
    final barLeft = center.dx + radius * 0.05;
    final barRight = center.dx + radius * 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(barLeft, barTop, barRight, barTop + barHeight),
        Radius.circular(barHeight / 2),
      ),
      Paint()..color = blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MicrosoftIcon extends StatelessWidget {
  const _MicrosoftIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: CustomPaint(painter: _MicrosoftPainter()),
  );
}

class _MicrosoftPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2 - 1.0;
    const gap = 2.0;

    final rects = [
      Rect.fromLTWH(0, 0, half, half),
      Rect.fromLTWH(half + gap, 0, half, half),
      Rect.fromLTWH(0, half + gap, half, half),
      Rect.fromLTWH(half + gap, half + gap, half, half),
    ];

    const colors = [
      Color(0xFFF25022),
      Color(0xFF7FBA00),
      Color(0xFFFFB900),
      Color(0xFF00A4EF),
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rects[i], const Radius.circular(1.5)),
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DocContent {
  final String title;
  final List<_DocSection> sections;

  const _DocContent({required this.title, required this.sections});
}

class _DocSection {
  final String title;
  final String body;

  const _DocSection({required this.title, required this.body});
}
