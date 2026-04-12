import 'package:shared_preferences/shared_preferences.dart';

enum EaPlanTier { free, plus, pro }

class EaPlanService {
  const EaPlanService._();
  static const EaPlanService instance = EaPlanService._();

  static const String kPlanPrefKey = 'account.subscription.plan';
  static const int _kUnlimited = 1 << 30;

  Future<EaPlanTier> readTier() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(kPlanPrefKey) ?? 'Free').trim().toLowerCase();
    return switch (raw) {
      'free' => EaPlanTier.free,
      'plus' => EaPlanTier.plus,
      'experience' => EaPlanTier.pro,
      'experiencia' => EaPlanTier.pro,
      'experiência' => EaPlanTier.pro,
      'pro' => EaPlanTier.pro,
      _ => EaPlanTier.free,
    };
  }

  String tierName(EaPlanTier tier) {
    return switch (tier) {
      EaPlanTier.free => 'Free',
      EaPlanTier.plus => 'Plus',
      EaPlanTier.pro => 'Experience',
    };
  }

  int maxDevices(EaPlanTier tier) {
    return switch (tier) {
      EaPlanTier.free => 3,
      EaPlanTier.plus => _kUnlimited,
      EaPlanTier.pro => _kUnlimited,
    };
  }

  int maxProfiles(EaPlanTier tier) {
    return switch (tier) {
      EaPlanTier.free => 1,
      EaPlanTier.plus => 3,
      EaPlanTier.pro => _kUnlimited,
    };
  }

  bool allowsAssistant(EaPlanTier tier) =>
      tier == EaPlanTier.plus || tier == EaPlanTier.pro;

  bool allowsAssistantFull(EaPlanTier tier) => tier == EaPlanTier.pro;

  bool allowsTemperature(EaPlanTier tier) => true;

  bool allowsRareAssistantRecommendations(EaPlanTier tier) =>
      tier == EaPlanTier.plus;

  bool canAddDevice(EaPlanTier tier, int currentDeviceCount) =>
      currentDeviceCount < maxDevices(tier);

  bool canCreateProfile(EaPlanTier tier, int currentProfileCount) =>
      currentProfileCount < maxProfiles(tier);
}
