import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/device/device_settings_notifier.dart';

class DeviceSettingsScreen extends ConsumerStatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  ConsumerState<DeviceSettingsScreen> createState() =>
      _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends ConsumerState<DeviceSettingsScreen> {
  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _surface = Color(0xFF141414);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _accent = Color(0xFF00E676);
  static const Color _accentRed = Color(0xFFFF5252);
  static const Color _border = Color(0xFF2A2A2A);

  bool _isSyncing = false;

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _shortId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onSyncNow() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await ref.read(deviceSettingsProvider.notifier).syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Synced — location ping sent', icon: Icons.check_circle_outline),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Sync failed: $e', isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _onEditName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Device Name',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter device name',
            hintStyle: GoogleFonts.inter(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _accent.withValues(alpha: 0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _accent),
            ),
          ),
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Save',
              style: GoogleFonts.inter(color: _accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      try {
        await ref
            .read(deviceSettingsProvider.notifier)
            .updateDeviceName(controller.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            _snackBar('Device name updated', icon: Icons.check_circle_outline),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            _snackBar('Failed to update name', isError: true),
          );
        }
      }
    }
  }

  SnackBar _snackBar(String msg, {IconData? icon, bool isError = false}) {
    return SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: isError ? _accentRed : _accent, size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(deviceSettingsProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18,
              color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Device Settings',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          settingsAsync.whenOrNull(
            data: (s) => TextButton.icon(
              onPressed: _isSyncing ? null : _onSyncNow,
              icon: _isSyncing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _accent,
                      ),
                    )
                  : Icon(Icons.sync_rounded, size: 18, color: _accent),
              label: Text(
                'Sync Now',
                style: GoogleFonts.inter(
                  color: _isSyncing ? Colors.white24 : _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ) ?? const SizedBox(),
          const SizedBox(width: 8),
        ],
      ),
      body: settingsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, color: Colors.white24, size: 48),
              const SizedBox(height: 16),
              Text(
                'Could not load settings',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(deviceSettingsProvider),
                child: Text('Retry', style: GoogleFonts.inter(color: _accent)),
              ),
            ],
          ),
        ),
        data: (settings) => _buildContent(settings),
      ),
    );
  }

  Widget _buildContent(DeviceSettings s) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        _buildDeviceInfoCard(s),
        const SizedBox(height: 20),
        _buildSectionHeader('SUPABASE SYNC'),
        const SizedBox(height: 10),
        _buildToggleCard(
          icon: Icons.power_settings_new_rounded,
          iconColor: s.isActive ? _accent : Colors.white38,
          title: 'Device Active',
          subtitle: s.isActive
              ? 'Visible to operators — data is being collected'
              : 'Marked inactive — data collection paused',
          value: s.isActive,
          onChanged: (v) async {
            try {
              await ref.read(deviceSettingsProvider.notifier).setActive(v);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  _snackBar(
                    v ? 'Device marked active in Supabase' : 'Device marked inactive in Supabase',
                    icon: Icons.check_circle_outline,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  _snackBar('Failed to update — check connection', isError: true),
                );
              }
            }
          },
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('LOCAL TRACKING'),
        const SizedBox(height: 10),
        _buildToggleCard(
          icon: Icons.location_on_rounded,
          iconColor: s.locationTrackingEnabled ? _accent : Colors.white38,
          title: 'Location Tracking',
          subtitle: s.locationTrackingEnabled
              ? 'GPS ping sent to Supabase every 2 minutes'
              : 'Location pings paused',
          value: s.locationTrackingEnabled,
          onChanged: (v) => ref
              .read(deviceSettingsProvider.notifier)
              .setLocationTracking(v),
        ),
        const SizedBox(height: 12),
        _buildToggleCard(
          icon: Icons.camera_alt_rounded,
          iconColor: s.detectionLoggingEnabled ? _accent : Colors.white38,
          title: 'Detection Logging',
          subtitle: s.detectionLoggingEnabled
              ? 'Waste detections are saved to Supabase'
              : 'Detection events are not being saved',
          value: s.detectionLoggingEnabled,
          onChanged: (v) => ref
              .read(deviceSettingsProvider.notifier)
              .setDetectionLogging(v),
        ),
        const SizedBox(height: 28),
        _buildSyncNowButton(s),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Device Info Card ──────────────────────────────────────────────────────

  Widget _buildDeviceInfoCard(DeviceSettings s) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.smartphone_rounded, color: _accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.deviceName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _onEditName(s.deviceName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_rounded,
                                    color: _accent, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'Edit',
                                  style: GoogleFonts.inter(
                                    color: _accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: s.deviceId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          _snackBar('Device ID copied to clipboard',
                              icon: Icons.copy_rounded),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            _shortId(s.deviceId),
                            style: GoogleFonts.robotoMono(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.copy_rounded,
                              color: Colors.white24, size: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: _border, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoRow(
                  Icons.calendar_today_rounded,
                  'Registered',
                  _formatDate(s.registeredAt),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoRow(
                  Icons.access_time_rounded,
                  'Last Seen',
                  _formatDate(s.lastSeenAt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white24, size: 12),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.white24,
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.robotoMono(
            color: Colors.white60,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ── Section Header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white24,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── Toggle Card ───────────────────────────────────────────────────────────

  Widget _buildToggleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? _accent.withValues(alpha: 0.25) : _border,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Switch
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: _accent,
              activeTrackColor: _accent.withValues(alpha: 0.4),
              inactiveTrackColor: Colors.white12,
              inactiveThumbColor: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sync Now button ───────────────────────────────────────────────────────

  Widget _buildSyncNowButton(DeviceSettings s) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isSyncing ? null : _onSyncNow,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent.withValues(alpha: 0.12),
          foregroundColor: _accent,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
          side: BorderSide(
            color: _isSyncing
                ? Colors.white12
                : _accent.withValues(alpha: 0.4),
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: _isSyncing
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              )
            : const Icon(Icons.sync_rounded, size: 20),
        label: Text(
          _isSyncing ? 'Syncing…' : 'Sync Now',
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
