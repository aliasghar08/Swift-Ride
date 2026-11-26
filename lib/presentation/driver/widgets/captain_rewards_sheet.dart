import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/native/native_launcher_service.dart';
import '../../view_models/responsive_layout_helper.dart';

/// Modal sheet showcasing the Captain-Only Growth, 0% Fee Waiver & 5-Driver Badge Engine.
class CaptainRewardsSheet extends StatefulWidget {
  final DriverProvider driverProv;

  const CaptainRewardsSheet({
    super.key,
    required this.driverProv,
  });

  static Future<void> show(BuildContext context, DriverProvider driverProv) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CaptainRewardsSheet(driverProv: driverProv),
    );
  }

  @override
  State<CaptainRewardsSheet> createState() => _CaptainRewardsSheetState();
}

class _CaptainRewardsSheetState extends State<CaptainRewardsSheet> {
  final TextEditingController _promoController = TextEditingController();
  bool _isApplying = false;
  String? _promoMessage;
  bool _isPromoSuccess = false;

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isApplying = true;
      _promoMessage = null;
    });

    final res = await widget.driverProv.applyPromoCode(code);
    if (!mounted) return;

    setState(() {
      _isApplying = false;
      _isPromoSuccess = res['success'] == true;
      _promoMessage = res['message']?.toString() ??
          (_isPromoSuccess ? '0% Platform Fee Unlocked for 30 Days!' : 'Failed to apply code.');
    });

    if (_isPromoSuccess) {
      _promoController.clear();
    }
  }

  Future<void> _shareOnWhatsApp(String code, String link) async {
    final text =
        "Assalam-o-Alaikum Captain! Swift Ride join karein mere link se aur paayein 30 din ke liye 0% platform fee (100% kamai aapki)!\n\n"
        "👉 Join Link: $link\n"
        "Ya invite code: *$code*\n"
        "Download on Google Play: https://play.google.com/store/apps/details?id=com.dartnexuslab.swiftride&referrer=captain_code%3D$code";
    final url = "https://wa.me/?text=${Uri.encodeComponent(text)}";
    await NativeLauncherService().launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);
    final profile = widget.driverProv.driverProfile;

    final inviteCode = profile.captainInviteCode ??
        'CAPT${profile.userId.length >= 3 ? profile.userId.substring(profile.userId.length - 3).toUpperCase() : "786"}';
    final referralLink = profile.captainReferralLink;
    final isWaiver = profile.isFeeWaiverActive;
    final waiverDays = profile.waiverDaysRemaining;
    final weeklyRides = profile.weeklyCompletedRides;
    final weeklyProgress = (weeklyRides / 15.0).clamp(0.0, 1.0);
    final referralsCount = profile.verifiedReferralsCount;
    final isFounding = profile.isFoundingCaptain;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        layout.scale(20),
        layout.scale(12),
        layout.scale(20),
        layout.scale(28) + MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.border.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.military_tech_rounded,
                        color: AppTheme.emeraldGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Captain Rewards & Badges",
                          style: TextStyle(
                            fontSize: layout.fontSize(16),
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          "0% Platform Fee Waivers & Stand Badges",
                          style: TextStyle(
                            fontSize: layout.fontSize(11.5),
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.textSecondary, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Hero Fee Tier Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isWaiver
                      ? const [Color(0xFF00796B), Color(0xFF004D40)]
                      : [AppTheme.primaryBlue, const Color(0xFF1E3A8A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: (isWaiver ? AppTheme.emeraldGreen : AppTheme.primaryBlue)
                        .withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isWaiver ? Icons.verified_rounded : Icons.info_outline_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isWaiver
                                  ? "0% Platform Fee Active"
                                  : "2% Standard Fee (Year 1)",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isFounding)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFD700), width: 1),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                "🎖️ Founding Captain",
                                style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isWaiver
                        ? "You keep 100% of all ride fares!"
                        : "Keep 98% of your fares • Earn 0% fee waivers below",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isWaiver
                        ? "Waiver expires in $waiverDays days (${profile.feeWaiverUntil != null ? '${profile.feeWaiverUntil!.day}/${profile.feeWaiverUntil!.month}/${profile.feeWaiverUntil!.year}' : ''})"
                        : "Standard 2% commission applies. Complete weekly rides or invite captains to unlock 0% fee.",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Card 1: Weekly 0% Fee Target
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.speed_rounded, color: AppTheme.accentCyan, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "Weekly 0% Fee Target",
                            style: TextStyle(
                              fontSize: layout.fontSize(13.5),
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "$weeklyRides / 15 Rides",
                        style: TextStyle(
                          fontSize: layout.fontSize(12.5),
                          fontWeight: FontWeight.w800,
                          color: weeklyRides >= 15 ? AppTheme.emeraldGreen : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: weeklyProgress,
                      backgroundColor: c.border.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        weeklyRides >= 15 ? AppTheme.emeraldGreen : AppTheme.accentCyan,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    weeklyRides >= 15
                        ? "Target reached! +7 days of 0% fee has been applied to your account."
                        : "Complete ${15 - weeklyRides} more rides this week to unlock +7 days of 0% fee.",
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Card 2: 5-Driver Referral Milestone & Stand Badge
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFounding
                      ? const Color(0xFFFFD700).withValues(alpha: 0.7)
                      : c.border.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.group_add_rounded, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "5-Driver Stand Leader Badge",
                            style: TextStyle(
                              fontSize: layout.fontSize(13.5),
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "$referralsCount / 5 Captains",
                        style: TextStyle(
                          fontSize: layout.fontSize(12.5),
                          fontWeight: FontWeight.w800,
                          color: isFounding ? const Color(0xFFFFD700) : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Progress indicator with 5 visual slots
                  Row(
                    children: List.generate(5, (index) {
                      final isUnlocked = index < referralsCount;
                      return Expanded(
                        child: Container(
                          height: 8,
                          margin: EdgeInsets.only(right: index < 4 ? 4 : 0),
                          decoration: BoxDecoration(
                            color: isUnlocked ? Colors.orange : c.border.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isFounding
                        ? "You unlocked the Founding Captain badge! It appears on your profile and on passenger offer cards."
                        : "Invite 5 captains who verify CNIC/License and complete 3 rides. Unlocks permanent 'Founding Captain' badge + 30 days of 0% fee!",
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Captain Invite Code & WhatsApp Share
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Your Captain Code",
                                  style: TextStyle(
                                    fontSize: layout.fontSize(10.5),
                                    color: c.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  inviteCode,
                                  style: TextStyle(
                                    fontSize: layout.fontSize(16),
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.emeraldGreen,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: inviteCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Captain Code $inviteCode copied to clipboard!"),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: const Text("Copy Code"),
                              style: TextButton.styleFrom(
                                foregroundColor: c.textSecondary,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: referralLink));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Referral Link copied!\n$referralLink"),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.link_rounded, size: 16),
                                label: const Text("Copy Link"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accentTeal,
                                  side: BorderSide(color: AppTheme.accentTeal.withValues(alpha: 0.5)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _shareOnWhatsApp(inviteCode, referralLink),
                                icon: const Icon(Icons.share_rounded, size: 16),
                                label: const Text("WhatsApp"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Card 3: Redeem Promo or Invite Code
            if (profile.referredByCode == null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Have a Launch Code or Captain Invite?",
                      style: TextStyle(
                        fontSize: layout.fontSize(13),
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Enter JHANG0 or a fellow captain's code to unlock 0% fee for 30 days.",
                      style: TextStyle(
                        fontSize: layout.fontSize(11),
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promoController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: "e.g. JHANG0 or CAPT-482",
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isApplying ? null : _applyPromo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.emeraldGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isApplying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    if (_promoMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _promoMessage!,
                        style: TextStyle(
                          fontSize: layout.fontSize(11.5),
                          fontWeight: FontWeight.w600,
                          color: _isPromoSuccess ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Close Button
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.surfaceRaised,
                foregroundColor: c.textPrimary,
                elevation: 0,
                side: BorderSide(color: c.border.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Close", style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
