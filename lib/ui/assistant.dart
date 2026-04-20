import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handler.dart';
import 'utils/bridge.dart';
import 'utils/skeleton.dart';
import 'i18n.dart';

class Agent extends StatefulWidget {
  const Agent({super.key});

  @override
  State<Agent> createState() => AgentState();
}

class AgentState extends State<Agent> {
  UsageStats? _stats;
  UsageRecommendation? _recommendation;
  bool _isLoading = true;
  String _profileName = "You";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final fullName = (prefs.getString('account.auth.name') ??
            prefs.getString('account.profile.name') ??
            '')
        .trim();
    if (fullName.isNotEmpty) {
      _profileName = fullName.split(' ').first;
    } else {
      _profileName = "";
    }

    _stats = Bridge.usageStats();
    _recommendation = Bridge.usageRecommendation();

    // Removed Recent Activity reading per user request

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      HapticFeedback.mediumImpact();
    }
  }

  Widget _buildCompactTile({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String text,
    int index = 0,
  }) {
    return EaFadeSlideIn(
      begin: const Offset(0, 0.05),
      duration: Duration(milliseconds: 400 + (index * 100)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: EaColor.back.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: () => HapticFeedback.lightImpact(),
            splashColor: accentColor.withValues(alpha: 0.1),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withValues(alpha: 0.25),
                          accentColor.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: accentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          text,
                          style: TextStyle(
                            color: EaColor.textSecondary.withValues(alpha: 0.8),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInsights() {
    List<Widget> cards = [];
    int index = 1;

    if (_recommendation != null && _recommendation!.title.isNotEmpty) {
      cards.add(
        _buildCompactTile(
          icon: Icons.insights_rounded,
          accentColor: const Color(0xFFB155FF),
          title: _recommendation!.title,
          text: _recommendation!.message,
          index: index++,
        ),
      );
    }

    if (_stats != null &&
        _stats!.sampleCount >= 5 &&
        _stats!.predictedArrivalHour > 0) {
      int hour = _stats!.predictedArrivalHour;
      String ampm = hour >= 12 ? "PM" : "AM";
      int displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

      int sleepHour = (hour + 4) % 24;
      String sleepAmpm = sleepHour >= 12 ? "PM" : "AM";
      int sleepDisplay = sleepHour > 12
          ? sleepHour - 12
          : (sleepHour == 0 ? 12 : sleepHour);

      cards.add(
        _buildCompactTile(
          icon: Icons.home_rounded,
          accentColor: const Color(0xFF4A90E2),
          title: EaI18n.t(context, "Arrival Pattern"),
          text: EaI18n.t(
            context,
            "{profileName} often arrives home around {hour} and sets lights brightness to {bright}%.",
            {
              'profileName': _profileName,
              'hour': '$displayHour$ampm',
              'bright': '${_stats!.preferredBrightness}',
            },
          ),
          index: index++,
        ),
      );

      cards.add(
        _buildCompactTile(
          icon: Icons.nightlight_round,
          accentColor: const Color(0xFF9AAEFF),
          title: EaI18n.t(context, "Evening Routine"),
          text: EaI18n.t(
            context,
            "{profileName} usually goes to sleep at {hour} and turns off all the lights.",
            {'profileName': _profileName, 'hour': '$sleepDisplay$sleepAmpm'},
          ),
          index: index++,
        ),
      );
    }

    if (_stats != null &&
        _stats!.sampleCount >= 5 &&
        _stats!.preferredTemperature > 10) {
      cards.add(
        _buildCompactTile(
          icon: Icons.thermostat_rounded,
          accentColor: const Color(0xFFFF7A00),
          title: EaI18n.t(context, "Climate Preference"),
          text: EaI18n.t(
            context,
            "When outside it's up to 27°C, {profileName} sets up the air conditioner around {temp}°C.",
            {
              'profileName': _profileName,
              'temp': _stats!.preferredTemperature.toStringAsFixed(1),
            },
          ),
          index: index++,
        ),
      );
    }

    if (cards.isEmpty) {
      cards.add(
        _buildCompactTile(
          icon: Icons.auto_fix_high,
          accentColor: EaColor.fore,
          title: EaI18n.t(context, "AI Analysis"),
          text: EaI18n.t(
            context,
            "Learning in progress. Assistant is still collecting behavior signals from app usage, commands and profiles.",
          ),
          index: index++,
        ),
      );
    }

    return cards;
  }

  Widget _buildSkeletonLoading() {
    return Column(
      children: List.generate(
        3,
        (index) => const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: EaSkeleton(
            width: double.infinity,
            height: 120,
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          physics: const BouncingScrollPhysics(),
          children: [
            EaFadeSlideIn(
              duration: const Duration(milliseconds: 400),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [EaColor.fore, Color(0xFFB155FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFB155FF).withValues(alpha: 0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _profileName.isEmpty
                        ? EaI18n.t(context, "Hello")
                        : EaI18n.t(context, "Hello, {profileName}", {
                            'profileName': _profileName,
                          }),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    EaI18n.t(context, "Here are your smart home insights"),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: EaColor.secondaryFore,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
            if (_isLoading) _buildSkeletonLoading() else ..._buildInsights(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
