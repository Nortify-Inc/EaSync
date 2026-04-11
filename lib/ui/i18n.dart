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
    'To use the AI assistant, you need to download the model (~2GB). This may be heavy on some devices. Do you want to download and enable the assistant?':
        'Para usar o assistente de IA, é necessário baixar o modelo (~2GB). Isso pode ser pesado em alguns dispositivos. Deseja baixar e ativar o assistente?',
    'No, skip': 'Não, pular',
    'Yes, I want AI': 'Sim, quero IA',
    'Ask the assistant with device + room + intent for more accurate actions.':
        'Peça ao assistente com dispositivo + ambiente + intenção para ações mais precisas.',
    'If the AI response is too broad, add limits like range, time, or priority.':
        'Se a resposta da IA estiver ampla demais, adicione limites como faixa, horário ou prioridade.',
    'Short follow-up prompts usually improve continuity after the first answer.':
        'Prompts curtos de continuação geralmente melhoram a continuidade após a primeira resposta.',
    'If the assistant misunderstands, mention the exact device name as registered.':
        'Se o assistente entender errado, mencione o nome exato do dispositivo como cadastrado.',
    'Use one task per prompt when speed matters; batched requests can take longer.':
        'Use uma tarefa por prompt quando velocidade importar; pedidos em lote podem levar mais tempo.',
    'Before applying automation, ask AI for a preview of what will be changed.':
        'Antes de aplicar automações, peça para a IA uma prévia do que será alterado.',
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
    'Accept': 'Aceitar',
    'Assistant Data': 'Dados do assistente',
    'Outside temperature': 'Temperatura externa',
    'Weather': 'Clima',
    'Clear sky': 'Céu limpo',
    'Cloudy sky': 'Nublado',
    'Foggy': 'Neblina',
    'Light rain': 'Chuva leve',
    'Rainy': 'Chuva',
    'Snowy': 'Neve',
    'Stormy': 'Tempestade',
    'Sunny': 'Ensolarado',
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
    'Profile recommendation is Pro only.':
        'A recomendação de perfil está disponível apenas no Pro.',
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
    'Device limit reached for your plan.':
        'Limite de dispositivos do seu plano foi atingido.',
    'Profile limit reached for your plan.':
        'Limite de perfis do seu plano foi atingido.',
    'Temperature control is available from Plus plan.':
        'Controle de temperatura está disponível a partir do plano Plus.',
    'Assistant is available from Plus plan.':
        'O assistente está disponível a partir do plano Plus.',
    'Open plan options': 'Ver opções de plano',
    'Go to plan': 'Ir para plano',
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
    'Experience': 'Experiência',
    'Data control': 'Controle de dados',
    'Personal information': 'Informações pessoais',
    'Name and location': 'Nome e localização',
    'Language': 'Idioma',
    'Region': 'Região',
    'United States': 'Estados Unidos',
    'Brazil': 'Brasil',
    'Unknown location': 'Localização desconhecida',
    'Full name': 'Nome completo',
    'Save changes': 'Salvar alterações',
    'Language and region updated.': 'Idioma e região atualizados.',
    'Full location': 'Localização completa',
    'Update': 'Atualizar',
    'Biometrics and passkeys': 'Biometria e chaves de acesso',
    'Increase the security to access the app':
        'Aumente a segurança para acessar o app',
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
    'Could not update temperature right now.':
        'Não foi possível atualizar a temperatura agora.',
    'Firebase is not configured in this build yet.':
        'Firebase ainda não está configurado nesta build.',
    'Could not pick image: {error}':
        'Não foi possível escolher a imagem: {error}',
    'GPS unavailable on Web. Using the Location field as fallback.':
        'GPS indisponível na Web. Usando o campo Localização como fallback.',
    'GPS unavailable on this platform. Using the Location field as fallback.':
        'GPS indisponível nesta plataforma. Usando o campo Localização como fallback.',
    'Could not update location: {error}':
        'Não foi possível atualizar localização: {error}',
    'Location updated using typed field fallback.':
        'Localização atualizada com fallback do campo digitado.',
    'Could not get GPS right now. Using Location fallback when available.':
        'Não foi possível obter o GPS agora. Usando fallback de Localização quando disponível.',
    'Enable location service (GPS) to update address.':
        'Ative o serviço de localização (GPS) para atualizar o endereço.',
    'Open settings': 'Abrir ajustes',
    'Location permission denied. Allow access to update.':
        'Permissão de localização negada. Permita o acesso para atualizar.',
    'Location permission permanently denied. Allow it in app settings.':
        'Permissão de localização bloqueada permanentemente. Libere nas configurações do app.',
    'Open app': 'Abrir app',
    'Firebase is not configured for this platform yet.':
        'Firebase ainda não está configurado para esta plataforma.',
    'Sign-in failed.': 'Falha ao entrar.',
    'Sign-in failed: {error}': 'Falha ao entrar: {error}',
    'Verification code (demo): {code}': 'Código de verificação (demo): {code}',
    'Invalid verification PIN.': 'PIN de verificação inválido.',
    'Failed to create account.': 'Falha ao criar conta.',
    'Failed to create account: {error}': 'Falha ao criar conta: {error}',
    'Enter the 6-digit PIN to complete sign up':
        'Digite o PIN de 6 dígitos para concluir o cadastro',
    '2-step verification': 'Verificação em 2 etapas',
    'Additional access protection to your account':
        'Proteção adicional de acesso à sua conta',
    'Trusted devices': 'Dispositivos confiáveis',
    'Current and recent sessions': 'Sessões atuais e recentes',
    'Host': 'Host',
    'Can control devices': 'Pode controlar dispositivos',
    'Can modify configuration': 'Pode modificar configurações',
    'Host policy: control {control}, modify {modify}':
        'Política do host: controle {control}, modificação {modify}',
    'Take host role on this device': 'Assumir papel de host neste dispositivo',
    'Host applies permissions to other instances':
        'O host aplica permissões para outras instâncias',
    'Local policy active: control {control}, modify {modify}':
        'Política local ativa: controle {control}, modificação {modify}',
    'No trusted peers found on local network.':
        'Nenhum dispositivo confiável encontrado na rede local.',
    'Plan details and benefits': 'Detalhes do plano e benefícios',
    'Billing': 'Cobranças',
    'Invoices and payment methods': 'Faturas e meios de pagamento',
    'Export account data': 'Exportar dados da conta',
    'Portable backup package': 'Pacote de backup portátil',
    'Delete application data': 'Excluir dados do aplicativo',
    'Permanent local data deletion': 'Exclusão permanente de dados locais',
    'Authenticated account': 'Conta autenticada',
    'You are not authenticated yet.': 'Você ainda não está autenticado.',
    'Sign in': 'Entrar',
    'Enabled': 'Ativado',
    'Disabled': 'Desativado',
    'Authenticated via {provider}': 'Autenticado via {provider}',
    'Create your account': 'Crie sua conta',
    'Welcome back': 'Bem-vindo de volta',
    'Choose a provider to get started': 'Escolha um provedor para começar',
    'Choose a provider to continue': 'Escolha um provedor para continuar',
    'By continuing you agree to our ':
        'Ao continuar você está aceitando nossos ',
    'Terms of Use': 'Termos de Uso',
    'Privacy Policy': 'Política de Privacidade',
    ' and ': ' e ',
    'By continuing you agree to our Terms of Service.':
        'Ao continuar você concorda com nossos Termos de Serviço.',
    'Create account': 'Criar conta',
    'Authenticated': 'Autenticado',
    'Not authenticated': 'Não autenticado',
    'Guest': 'Convidado',
    'Password set': 'Senha definida',
    'No password': 'Sem senha',
    'Fingerprint enabled': 'Digital ativada',
    'Fingerprint disabled': 'Digital desativada',
    'Outside': 'Exterior',
    'Location': 'Localização',
    'Data saved locally.': 'Dados salvos localmente.',
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
    'Language and region': 'Idioma e região',
    'Portuguese': 'Português',
    'English': 'Inglês',
    'Spanish': 'Español',
    'Portugal': 'Portugal',
    '24-hour format': 'Formato 24 horas',
    'Use 24-hour time across schedules and labels':
        'Usar formato 24h em agendas e horários',
    'Save preferences': 'Salvar preferências',
    'Enable fingerprint unlock': 'Ativar desbloqueio por digital',
    'Enable device biometrics unlock':
        'Ativar desbloqueio biométrico do dispositivo',
    'Use fingerprint or face recognition to unlock the app faster.':
        'Use digital ou reconhecimento facial para desbloquear o app mais rápido.',
    'Biometric barrier on the device (without local_auth).':
        'Barreira biométrica no dispositivo (sem local_auth).',
    '24h format': 'Formato 24h',
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
    'Manual setup key': 'Chave de configuração manual',
    'Enter 6 digit': 'Digite 6 dígitos',
    'Invalid code. Try again.': 'Código inválido. Tente novamente.',
    'Invalid code.': 'Código inválido.',
    'Enter your 6-digit verification code to continue.':
        'Digite seu código de verificação de 6 dígitos para continuar.',
    'Biometrics are enabled but unavailable on this device.':
        'A biometria está ativada, mas indisponível neste dispositivo.',
    'Confirm your identity to unlock EaSync':
        'Confirme sua identidade para desbloquear o EaSync',
    'Authenticator app activated successfully.':
        'Aplicativo autenticador ativado com sucesso.',
    'Verify': 'Verificar',
    '2FA is active. Disable and enable again to generate a new setup key.':
        'O 2FA está ativo. Desative e ative novamente para gerar uma nova chave de configuração.',
    'How to configure 2FA': 'Como configurar o 2FA',
    '1. Enable Authenticator app.': '1. Ative o aplicativo autenticador.',
    '2. Choose QR-Code or Setup Key.': '2. Escolha entre QR-Code e Setup Key.',
    '2. Scan the QR code or copy the setup key in your authenticator app.':
        '2. Escaneie o QR code ou copie a chave de configuração no seu app autenticador.',
    '3. Enter the 6-digit code shown in the app to confirm activation.':
        '3. Digite o código de 6 dígitos exibido no app para confirmar a ativação.',
    '3. Setup Key mode requires the 6-digit code. QR-Code mode does not require code on this screen.':
        '3. O modo Setup Key exige o código de 6 dígitos. No modo QR-Code, não é necessário código nesta tela.',
    'Status': 'Status',
    'Inactive': 'Inativo',
    'Pending setup': 'Configuração pendente',
    'Active and protected': 'Ativo e protegido',
    'QR-Code': 'QR-Code',
    'Setup Key': 'Setup Key',
    'I scanned the QR code and want to continue':
        'Escaneei o QR code e quero continuar',
    'Could not confirm QR setup. Try Setup key mode.':
        'Não foi possível confirmar o setup via QR. Tente o modo Setup Key.',
    'QR setup confirmed. 2FA is now active.':
        'Setup via QR confirmado. O 2FA está ativo.',
    'SMS verification': 'Verificação por SMS',
    'Email verification': 'Verificação por email',
    'Save 2FA settings': 'Salvar configurações de 2FA',
    'Current session': 'Sessão atual',
    'Trusted session': 'Sessão confiável',
    'Current plan: {plan}': 'Plano atual: {plan}',
    'Advanced automations, analytics, and assistant controls.':
        'Automações, análises e controles avançados do assistente.',
    'Basic device and assistant controls':
        'Controles básicos de dispositivos e assistente',
    'Up to 3 devices and 1 profile': 'Até 3 dispositivos e 1 perfil',
    'Up to 3 profiles, temperature control, and basic assistant.':
        'Até 3 perfis, controle de temperatura e assistente básico.',
    'Advanced automations and full AI modes':
        'Automações avançadas e modos completos de IA',
    'Unlimited resources and full assistant modes':
        'Recursos ilimitados e modos completos do assistente',
    'No billing entries yet.': 'Nenhuma cobrança registrada ainda.',
    'Export copied to clipboard.':
        'Export copiado para a área de transferência.',
    'Copy setup key': 'Copiar setup key',
    'Setup key copied to clipboard.':
        'Setup key copiada para a área de transferência.',
    'This device': 'Este dispositivo',
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
