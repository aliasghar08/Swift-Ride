import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Production-grade Legal Disclaimers, Terms of Service & Privacy Policy Modal.
///
/// Designed to shield the platform against regulatory challenges, trademark disputes,
/// vicarious accident liability, and common-carrier lawsuits by establishing:
/// 1. Strict Technology Facilitator / Non-Carrier status (NOT a taxi company or common carrier).
/// 2. Independent Contractor relationship with drivers (no employer-employee relationship).
/// 3. Permanent, transparent 2% platform fee policy with 98% driver retention.
/// 4. Comprehensive limitation of liability and statutory insurance compliance.
/// 5. Full data privacy rights under PECA 2016 and App Store data deletion standards.
class LegalTermsModal extends StatelessWidget {
  final int initialTabIndex;

  const LegalTermsModal({super.key, this.initialTabIndex = 0});

  static Future<void> show(BuildContext context, {int initialTabIndex = 0}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LegalTermsModal(initialTabIndex: initialTabIndex),
    );
  }

  static Future<void> showTerms(BuildContext context) => show(context, initialTabIndex: 0);
  static Future<void> showFeePolicy(BuildContext context) => show(context, initialTabIndex: 1);
  static Future<void> showPrivacy(BuildContext context) => show(context, initialTabIndex: 2);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08);

    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // 1. Drag handle & Modal Header
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: AppTheme.primaryBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Legal & Regulatory Center',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppTheme.darkNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SwiftRide Platform Terms & Compliance',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: isDark ? Colors.white70 : AppTheme.darkNavy,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // 2. Tab Bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: isDark ? Colors.white60 : AppTheme.slateMuted,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Terms & Status'),
                    Tab(text: '2% Fee Policy'),
                    Tab(text: 'Privacy & PECA'),
                  ],
                ),
              ),

              // 3. Tab Contents
              Expanded(
                child: TabBarView(
                  children: [
                    _buildTermsTab(context, isDark, cardColor, borderColor),
                    _buildFeePolicyTab(context, isDark, cardColor, borderColor),
                    _buildPrivacyTab(context, isDark, cardColor, borderColor),
                  ],
                ),
              ),

              // 4. Acceptance Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 16, color: AppTheme.emeraldGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Governed by the laws of Pakistan & Arbitration Act 1940.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : AppTheme.slateMuted,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Understood', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermsTab(BuildContext context, bool isDark, Color cardColor, Color borderColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildNoticeBanner(
          icon: Icons.info_outline_rounded,
          color: AppTheme.primaryBlue,
          isDark: isDark,
          title: 'Non-Carrier & Technology Intermediary Status',
          description:
              '${AppConstants.appName} is exclusively an electronic software application and digital marketplace that connects passengers with independent third-party driver partners. ${AppConstants.appName} is NOT a common carrier, transportation service provider, taxi company, or employer, and does not own or operate transportation vehicles.',
        ),
        const SizedBox(height: 12),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '1. Independent Contractor Relationship',
          body:
              'Driver partners using ${AppConstants.appName} are independent third-party contractors and NOT employees, agents, or joint venturers of ${AppConstants.appName} or DartNexusLab. Drivers decide entirely when, where, and how long to provide ride services, and retain sole discretion to accept, negotiate, or reject ride requests. No employment contract, minimum hours, or exclusivity exists.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '2. Assumption of Risk & Limitation of Liability',
          body:
              'Transportation involves inherent road travel risks. To the maximum extent permitted by applicable law, ${AppConstants.appName} shall not be held liable for personal injury, property damage, traffic infractions, driver delays, or third-party acts. Drivers are strictly required under the Motor Vehicles Act to maintain valid driver licenses, vehicle fitness, and mandatory statutory third-party vehicle insurance.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '3. Fare Bargaining & Direct Agreement',
          body:
              'All ride fares on ${AppConstants.appName} are mutually negotiated and agreed between riders and drivers via open-market counter-offers. The suggested price generated by on-device algorithms is an advisory estimate only. Once a fare is mutually accepted and confirmed, it constitutes a direct agreement between the passenger and driver.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '4. Dispute Resolution & Arbitration',
          body:
              'Any dispute or legal claim arising from the use of ${AppConstants.appName} shall first be submitted to informal dispute resolution. If unresolved, all claims shall be settled via individual binding arbitration under the Arbitration Act, 1940 (Pakistan). Users and drivers waive any right to initiate or join class-action litigation against the platform.',
        ),
      ],
    );
  }

  Widget _buildFeePolicyTab(BuildContext context, bool isDark, Color cardColor, Color borderColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildNoticeBanner(
          icon: Icons.percent_rounded,
          color: AppTheme.emeraldGreen,
          isDark: isDark,
          title: 'Permanent 2% Platform Commission Guarantee',
          description:
              '${AppConstants.appName} guarantees an ultra-low, permanent 2.0% platform facilitation fee on completed rides. Drivers keep 98% of their agreed fares at all times. This rate is permanent and non-predatory.',
        ),
        const SizedBox(height: 12),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '1. Transparent 2% Facilitation Fee',
          body:
              'For every completed trip, ${AppConstants.appName} charges a 2.0% software facilitation fee to cover digital infrastructure, map routing services, and security. The remaining 98.0% of the fare belongs entirely to the driver partner.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '2. No Hidden Surcharges or Algorithmic Skimming',
          body:
              'Unlike traditional ride-hailing networks that deduct 15% to 30% or pocket opaque surge margins, ${AppConstants.appName} does not take hidden commissions. The fare displayed on the receipt is the exact amount negotiated, with the 2% fee clearly itemized.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '3. Real-Time Khata Ledger & Zero Subscriptions',
          body:
              'Drivers receive immediate access to their daily earnings Khata ledger. No compulsory monthly subscription fees, equipment rentals, or hidden penalties are levied to access ride offers.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '4. Cancellation & Toll Transparency',
          body:
              'If a rider cancels after driver arrival, a nominal cancellation fee compensates the driver. All highway tolls and bridge fees incurred during a trip are passed through transparently without platform markups.',
        ),
      ],
    );
  }

  Widget _buildPrivacyTab(BuildContext context, bool isDark, Color cardColor, Color borderColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildNoticeBanner(
          icon: Icons.security_rounded,
          color: AppTheme.accentTeal,
          isDark: isDark,
          title: 'Data Protection & PECA 2016 Compliance',
          description:
              'Your privacy is rigorously safeguarded under the Prevention of Electronic Crimes Act (PECA) 2016 and international data protection standards. We never sell your personal information.',
        ),
        const SizedBox(height: 12),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '1. Geolocation Tracking Scope',
          body:
              'GPS location data is accessed strictly while the app is actively in use for ride matching, turn-by-turn navigation, route previewing, and emergency SOS dispatch. Continuous background tracking ceases when offline.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '2. Telemetry & Ride Safety Sharing',
          body:
              'Trip sharing links generate time-limited, encrypted read-only tokens allowing designated emergency contacts or family members to view live progress. Once a ride completes, live tracking access terminates immediately.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '3. Data Retention & One-Tap Account Deletion',
          body:
              'Users hold the unrestricted right to permanently delete their account and associated profile records at any time directly through the in-app Account menu. In accordance with Apple and Google Play Privacy Guidelines, all personal identifiers and cloud data are permanently purged upon deletion.',
        ),
        _buildClauseCard(
          isDark: isDark,
          cardColor: cardColor,
          borderColor: borderColor,
          title: '4. Security Operations & Contact',
          body:
              'All telemetry is transmitted over TLS 1.3 encryption. For privacy inquiries, compliance verification, or statutory disclosures, contact DartNexusLab Security & Compliance at legal@dartnexuslab.com.',
        ),
      ],
    );
  }

  Widget _buildNoticeBanner({
    required IconData icon,
    required Color color,
    required bool isDark,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.darkNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: isDark ? Colors.white70 : AppTheme.slateMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClauseCard({
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.darkNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: isDark ? Colors.white60 : AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }
}
