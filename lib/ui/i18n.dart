/*!
 * @file i18n.dart
 * @brief Lightweight bidirectional localization helper for EaSync UI.
 * @param context BuildContext used to resolve active locale.
 * @return Localized string for EN/PT-BR.
 * @author Erick Radmann
 */

import 'package:flutter/material.dart';

class EaI18n {
  static const supportedLocales = [Locale('en'), Locale('pt', 'BR')];

  static bool _isPt(Locale locale) => locale.languageCode.toLowerCase() == 'pt';

  static Locale _safeLocale(BuildContext context) {
    final maybe = Localizations.maybeLocaleOf(context);
    return maybe ?? WidgetsBinding.instance.platformDispatcher.locale;
  }

  static String t(
    BuildContext context,
    String text, [
    Map<String, String>? params,
  ]) {
    return tForLocale(_safeLocale(context), text, params);
  }

  static String tSystem(String text, [Map<String, String>? params]) {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return tForLocale(locale, text, params);
  }

  static String tForLocale(
    Locale locale,
    String text, [
    Map<String, String>? params,
  ]) {
    final translated = _isPt(locale)
        ? (_enToPt[text] ?? text)
        : (_ptToEn[text] ?? text);

    if (params == null || params.isEmpty) return translated;

    var out = translated;
    params.forEach((k, v) {
      out = out.replaceAll('{$k}', v);
    });
    return out;
  }

  static final Map<String, String> _ptToEn = {
    for (final e in _enToPt.entries) e.value: e.key,
  };

  static const Map<String, String> _enToPt = {
        // 'Data saved locally.' already present below, removed duplicate.
        // Pop-up IA splash
        'Complete experience?': 'Experiência completa?',
        'To use the AI assistant, you need to download the model (~2GB). This may be heavy on some devices. Do you want to download and enable the assistant?': 'Para usar o assistente de IA, é necessário baixar o modelo (~2GB). Isso pode ser pesado em alguns dispositivos. Deseja baixar e ativar o assistente?',
        'No, skip': 'Não, pular',
        'Yes, I want AI': 'Sim, quero IA',
    'Dashboard': 'Painel',
    'Profiles': 'Perfis',
    'Assistant': 'Assistente',
    'Manage': 'Gerenciar',
    'Account': 'Conta',
    'Settings': 'Configurações',
    'Powered by': 'Desenvolvido por',
    'Everything connected.\nOne interface.': 'Tudo conectado.\nUma interface.',
    'General App': 'Aplicativo geral',
    'Dark mode': 'Modo escuro',
    'Default visual mode for EaSync': 'Modo visual padrão do EaSync',
    'Animations': 'Animações',
    'Subtle transitions across pages and tiles':
        'Transições suaves entre páginas e blocos',
    'Compact mode': 'Modo compacto',
    'Reduced paddings and denser tiles':
        'Espaçamentos reduzidos e blocos mais densos',
    'Haptic feedback': 'Feedback tátil',
    'Micro feedback on primary interactions':
        'Microfeedback nas interações principais',
    'Use location data': 'Usar dados de localização',
    'Improve context and suggestions': 'Melhorar contexto e sugestões',
    'Use weather data': 'Usar dados do clima',
    'Account for outdoor conditions': 'Considerar condições externas',
    'Use usage history': 'Usar histórico de uso',
    'Adapt to user patterns': 'Adaptar aos padrões do usuário',
    'Allow device control': 'Permitir controle de dispositivos',
    'AI can execute commands on devices':
        'A IA pode executar comandos em dispositivos',
    'Allow auto routines': 'Permitir rotinas automáticas',
    'Enable autonomous routine execution':
        'Ativar execução autônoma de rotinas',
    'AI temperament': 'Temperamento da IA',
    'Balanced': 'Equilibrado',
    'Fast': 'Rápido',
    'Conservative': 'Conservador',
    'Usage patterns': 'Padrões de uso',
    'Telemetry': 'Telemetria',
    'Collect anonymous usage metrics': 'Coletar métricas anônimas de uso',
    'Offline cache': 'Cache offline',
    'Keep recent state and responses locally':
        'Manter estado recente e respostas localmente',
    'Low data mode': 'Modo de baixo consumo',
    'Reduce background refresh and sync frequency':
        'Reduzir atualização em segundo plano e frequência de sincronização',
    'Usage profile': 'Perfil de uso',
    'Automation': 'Automação',
    'Economy': 'Economia',
    'New chat': 'Novo chat',
    'Hide chats': 'Ocultar chats',
    'Show chats': 'Mostrar chats',
    'Close chats': 'Fechar chats',
    'Thinking...': 'Pensando...',
    'No response generated. Try rephrasing your request.':
        'Nenhuma resposta gerada. Tente reformular seu pedido.',
    'Could not process this command right now. Please try again.':
        'Não foi possível processar este comando agora. Tente novamente.',
    'Type a command or ask a question...':
        'Digite um comando ou faça uma pergunta...',
    'How can I help you {_profileName}?':
        'No que posso ajudar você {_profileName}?',
    'Chat': 'Chat',
    'Send': 'Enviar',
    'Listening...': 'Ouvindo...',
    'Online': 'Online',
    'Listening... speak now': 'Ouvindo... fale agora',
    'Ask anything about your home…': 'Pergunte qualquer coisa sobre sua casa…',
    'Stop': 'Parar',
    'Rec': 'Gravar',
    'Retry': 'Tentar novamente',
    'Assistant Data': 'Dados do assistente',
    'Outside temperature': 'Temperatura externa',
    'Set location': 'Definir localização',
    'Annotations': 'Anotações',
    'View details': 'Ver detalhes',
    'All annotations': 'Todas as anotações',
    'Apply': 'Aplicar',
    'Run now': 'Executar agora',
    'Behavior insight': 'Insight de comportamento',
    'Learning in progress': 'Aprendizado em andamento',
    'Assistant backend is still collecting behavior signals from app usage, commands and profiles.':
        'O backend do assistente ainda está coletando sinais de comportamento de uso do app, comandos e perfis.',
    'No devices yet': 'Nenhum dispositivo ainda',
    'No devices discovered on network.':
        'Nenhum dispositivo descoberto na rede.',
    'Discovering...': 'Descobrindo...',
    'Discover': 'Descobrir',
    'Add device': 'Dispositivo',
    'Add your first device': 'Adicione seu primeiro dispositivo',
    'Let EaSync to discover him or add manually.':
        'Deixe o EaSync descobri-lo ou adicione manualmente.',
    'Search devices...': 'Buscar dispositivos...',
    'No matching devices': 'Nenhum dispositivo encontrado',
    'Power': 'Energia',
    'Brightness': 'Brilho',
    'Color': 'Cor',
    'Temperature': 'Temperatura',
    'Fridge': 'Geladeira',
    'Freezer': 'Freezer',
    'Schedule': 'Agendamento',
    'White Temp': 'Temp. de branco',
    'Color Temp': 'Temp. de cor',
    'Lock': 'Trava',
    'Mode': 'Modo',
    'Position': 'Posição',
    'Other': 'Outro',
    'All': 'Todos',
    'On': 'Ligado',
    'Off': 'Desligado',
    'Locked': 'Trancado',
    'Unlocked': 'Destrancado',
    'Core error': 'Erro do núcleo',
    'Your devices will appear here.': 'Seus dispositivos aparecerão aqui.',
    'No devices match this capability filter.':
        'Nenhum dispositivo corresponde a este filtro de capacidade.',
    'Showing all devices ({count})':
        'Mostrando todos os dispositivos ({count})',
    'Filtered: {selected} of {total}': 'Filtrado: {selected} de {total}',
    'No profiles yet': 'Nenhum perfil ainda',
    'Create profiles aligned with your mood.':
        'Crie perfis alinhados com seu humor.',
    'New profile': 'Novo perfil',
    'Assistant recommendation': 'Recomendação do assistente',
    'Add': 'Adicionar',
    'New Profile': 'Novo perfil',
    'Edit Profile': 'Editar perfil',
    'e.g Focus Mode, Movie Time, Relax Moment':
        'ex.: Modo foco, Hora do filme, Momento relax',
    'Profile name': 'Nome do perfil',
    'Not set': 'Não definido',
    'Select time': 'Selecionar horário',
    'Save Profile': 'Salvar perfil',
    'Delete': 'Excluir',
    'Delete profile?': 'Excluir perfil?',
    'This will permanently remove "{name}".':
        'Isso removerá permanentemente "{name}".',
    'Cancel': 'Cancelar',
    'Remove': 'Remover',
    'Remove device': 'Remover dispositivo',
    'Do you want to remove "{name}"?': 'Você quer remover "{name}"?',
    'Retry connection': 'Tentar conexão novamente',
    'Diagnostics': 'Diagnóstico',
    'Retry provisioning': 'Tentar provisionamento novamente',
    'Provisioning': 'Provisionamento',
    'Capabilities': 'Capacidades',
    'Rename nickname': 'Renomear apelido',
    'Enter new nickname': 'Digite um novo apelido',
    'Save': 'Salvar',
    'Profile and environment': 'Perfil e ambiente',
    'Security': 'Segurança',
    'Subscription': 'Assinatura',
    'Data control': 'Controle de dados',
    'Personal information': 'Informações pessoais',
    'Nme and location': 'Nome e localização',
    'Language': 'Idioma',
    'Full location': 'Localização completa',
    'Update': 'Atualizar',
    'Password and passkeys': 'Senha e passkeys',
    'Credential management': 'Gerenciamento de credenciais',
    'Sign out': 'Sair',
    'Continue': 'Continuar',
    'Display name': 'Nome de exibição',
    'Send verification PIN': 'Enviar PIN de verificação',
    'Password': 'Senha',
    'Protocol': 'Protocolo',
    'Connection': 'Conexão',
    'UUID': 'UUID',
    'Verify now': 'Verificar agora',
    'SSID': 'SSID',
    'Provision': 'Provisionar',
    'Clear': 'Limpar',
    'Device was removed.': 'Dispositivo removido.',
    'No diagnostics yet.': 'Ainda sem diagnóstico.',
    'Retry Wi-Fi provisioning': 'Tentar provisionamento Wi-Fi novamente',
    'Invalid SSID/password.': 'SSID/senha inválidos.',
    'Wi-Fi was provisioned successfully.': 'Wi-Fi provisionado com sucesso.',
    'Select a model': 'Selecione um modelo',
    'Please confirm you\'re connected to the device Access Point.':
        'Confirme que você está conectado ao Ponto de Acesso do dispositivo.',
    'Please enter your home Wi-Fi SSID.':
        'Informe o SSID do Wi-Fi da sua casa.',
    'Please enter a Wi-Fi password with at least 8 characters.':
        'Informe uma senha de Wi-Fi com pelo menos 8 caracteres.',
    'Automatic network settings opening is not supported on this system.':
        'A abertura automática das configurações de rede não é suportada neste sistema.',
    'Could not open network settings.':
        'Não foi possível abrir as configurações de rede.',
    'New Device': 'Novo dispositivo',
    'Search brand, model or capability': 'Buscar marca, modelo ou capacidade',
    'No templates found': 'Nenhum modelo encontrado',
    'Wi-Fi Provisioning': 'Provisionamento Wi-Fi',
    'Remember Wi-Fi credentials': 'Lembrar credenciais de Wi-Fi',
    'Before saving, open network settings, connect to the device Access Point, return to the app and then submit your Wi-Fi credentials.':
        'Antes de salvar, abra as configurações de rede, conecte ao Ponto de Acesso do dispositivo, volte ao app e então informe suas credenciais de Wi-Fi.',
    'Open Network Settings': 'Abrir configurações de rede',
    'I\'ve already connected to the device\'s Access Point':
        'Eu já me conectei ao Ponto de Acesso do dispositivo',
    'Network Name/SSID': 'Nome da rede/SSID',
    'Network Password': 'Senha da rede',
    'Device Custom Name': 'Nome personalizado do dispositivo',
    'Backend AI execution error.': 'Erro na execução da IA de backend.',
    'Voice recognition is only available on Android for now.':
        'O reconhecimento de voz está disponível apenas no Android por enquanto.',
    'Voice recognition is not available right now.':
        'Reconhecimento de voz indisponível no momento.',
    'Your location': 'Sua localização',
    'City or city,country (e.g. London,UK)':
        'Cidade ou cidade,país (ex.: Londres,UK)',
    'Device control is disabled in Assistant Data.':
        'O controle de dispositivos está desativado em Dados do assistente.',
    'No temperature-capable device found.':
        'Nenhum dispositivo com suporte a temperatura encontrado.',
    'Suggestion applied to {name} ({temp}°C).':
        'Sugestão aplicada em {name} ({temp}°C).',
    'Assistant auto-routine applied on {name}.':
        'Rotina automática do assistente aplicada em {name}.',
    'Arrival routine applied on {name} ({temp}°C).':
        'Rotina de chegada aplicada em {name} ({temp}°C).',
    'Color temperature': 'Temperatura de cor',
    'Minimalist': 'Minimalista',
    'Cheerful': 'Alegre',
    'Direct': 'Direto',
    'Professional': 'Profissional',
    'Assistant temperament': 'Temperamento do assistente',
    'Controls tone of generated answers.':
        'Controla o tom das respostas geradas.',
    'Allow AI to consume location': 'Permitir que a IA use localização',
    'Use device GPS when available, otherwise network-based location.':
        'Usa GPS do dispositivo quando disponível, caso contrário localização por rede.',
    'Allow AI to consume weather data': 'Permitir que a IA use dados do clima',
    'Weather informs climate and arrival suggestions.':
        'O clima orienta sugestões de climatização e chegada.',
    'Allow AI to consume usage history':
        'Permitir que a IA use histórico de uso',
    'Lets Assistant learn open/arrival patterns over time.':
        'Permite ao assistente aprender padrões de abertura/chegada ao longo do tempo.',
    'Allow AI to control devices': 'Permitir que a IA controle dispositivos',
    'Enables command execution and suggestion apply buttons.':
        'Habilita execução de comandos e botões para aplicar sugestões.',
    'Allow AI to run automatic routines':
        'Permitir que a IA execute rotinas automáticas',
    'Allows periodic auto-arrival automation near learned time.':
        'Permite automação periódica de chegada próxima ao horário aprendido.',
    'Enable auto-arrival routine': 'Ativar rotina de chegada automática',
    'Auto run near {hour} when weather is warm.':
        'Executa automaticamente perto de {hour} quando o clima está quente.',
    'Não foi possível atualizar a temperatura agora.':
        'Could not update temperature right now.',
    'Firebase ainda não está configurado nesta build.':
        'Firebase is not configured in this build yet.',
    'Não foi possível escolher a imagem: {error}':
        'Could not pick image: {error}',
    'GPS indisponível na Web. Usando o campo Localização como fallback.':
        'GPS unavailable on Web. Using the Location field as fallback.',
    'GPS indisponível nesta plataforma. Usando o campo Localização como fallback.':
        'GPS unavailable on this platform. Using the Location field as fallback.',
    'Não foi possível atualizar localização: {error}':
        'Could not update location: {error}',
    'Localização atualizada com fallback do campo digitado.':
        'Location updated using typed field fallback.',
    'Detalhes do plano e benefícios': 'Plan details and benefits',
    'Firebase ainda não está configurado para esta plataforma.':
        'Firebase is not configured for this platform yet.',
    'Falha ao entrar.': 'Sign-in failed.',
    'Falha ao entrar: {error}': 'Sign-in failed: {error}',
    'Código de verificação (demo): {code}': 'Verification code (demo): {code}',
    'PIN de verificação inválido.': 'Invalid verification PIN.',
    'Falha ao criar conta.': 'Failed to create account.',
    'Falha ao criar conta: {error}': 'Failed to create account: {error}',
    'Digite o PIN de 6 dígitos para concluir o cadastro':
        'Enter the 6-digit PIN to complete sign up',
    '2-step verification': 'Verificação em 2 etapas',
    'Additional access protection': 'Proteção adicional de acesso',
    'Trusted devices': 'Dispositivos confiáveis',
    'Current and recent sessions': 'Sessões atuais e recentes',
    'Plan details and benefits': 'Detalhes do plano e benefícios',
    'Billing history': 'Histórico de cobranças',
    'Invoices and payment methods': 'Faturas e meios de pagamento',
    'Export account data': 'Exportar dados da conta',
    'Portable backup package': 'Pacote de backup portátil',
    'Delete account': 'Excluir conta',
    'Permanent removal flow': 'Fluxo de remoção permanente',
    'Authenticated account': 'Conta autenticada',
    'You are not authenticated yet.': 'Você ainda não está autenticado.',
    'Sign in': 'Entrar',
    'Create account': 'Criar conta',
    'Authenticated': 'Autenticado',
    'Guest': 'Convidado',
    'Password set': 'Senha definida',
    'No password': 'Sem senha',
    'Fingerprint enabled': 'Digital ativada',
    'Fingerprint disabled': 'Digital desativada',
    'Outside': 'Exterior',
    'Location': 'Localização',
    'Data saved locally.': 'Dados salvos localmente.',
    'Save changes': 'Salvar alterações',
    'Type city, state or country': 'Digite cidade, estado ou país',
    'No update recorded.': 'Sem atualização registrada.',
    'Updated at {time}': 'Atualizado às {time}',
    'Refresh from devices': 'Atualizar pelos dispositivos',
    'Address saved locally.': 'Endereço salvo localmente.',
    'Address and location': 'Endereço e localização',
    'Street': 'Rua',
    'City': 'Cidade',
    'CEP': 'CEP',
    'Country': 'País',
    'Save address': 'Salvar endereço',
    'Language and region updated.': 'Idioma e região atualizados.',
    'Language and region': 'Idioma e região',
    'Region': 'Região',
    'Portuguese': 'Português',
    'English': 'Inglês',
    'Spanish': 'Español',
    'Brazil': 'Brasil',
    'Portugal': 'Portugal',
    'United States': 'Estados Unidos',
    '24-hour format': 'Formato 24 horas',
    'Save preferences': 'Salvar preferências',
    'Enable fingerprint unlock': 'Ativar desbloqueio por digital',
    'Biometric barrier on the device (without local_auth).':
        'Barreira biométrica no dispositivo (sem local_auth).',
    'Change login password': 'Alterar senha de login',
    'Create login password': 'Criar senha de login',
    'Configure your local login password':
        'Configurar sua senha local de login',
    'Password must have at least 4 characters.':
        'A senha precisa ter ao menos 4 caracteres.',
    'Passwords do not match.': 'As senhas não coincidem.',
    'Password saved successfully.': 'Senha salva com sucesso.',
    'Login password': 'Senha de login',
    'New password': 'Nova senha',
    'Confirm password': 'Confirmar senha',
    'Save password': 'Salvar senha',
    '2FA updated successfully.': '2FA atualizada com sucesso.',
    'Authenticator app': 'Aplicativo autenticador',
    'SMS verification': 'Verificação por SMS',
    'Email verification': 'Verificação por email',
    'Save 2FA settings': 'Salvar configurações de 2FA',
    'Current session': 'Sessão atual',
    'Trusted session': 'Sessão confiável',
    'Current plan: {plan}': 'Plano atual: {plan}',
    'Automation, analytics and advanced assistant controls.':
        'Automações, análises e controles avançados do assistente.',
    'Basic device and assistant controls':
        'Controles básicos de dispositivos e assistente',
    'Advanced automations and full AI modes':
        'Automações avançadas e modos completos de IA',
    'No billing records yet.': 'Nenhuma cobrança registrada ainda.',
    'Profile data': 'Dados de perfil',
    'Usage data': 'Dados de uso',
    'Security settings': 'Configurações de segurança',
    'Generate export': 'Gerar exportação',
    'Confirm by typing DELETE and checking the option.':
        'Confirme digitando DELETE e marque a opção.',
    'Local account data removed.': 'Dados locais da conta removidos.',
    'This action removes your local data and cannot be undone.':
        'Esta ação remove seus dados locais e não pode ser desfeita.',
    'Type DELETE to confirm': 'Digite DELETE para confirmar',
    'I understand this operation is irreversible':
        'Entendo que esta operação é irreversível',
    'Delete local account data': 'Excluir dados locais da conta',
  };
}
