import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_config.dart';
import '../models/bin_category.dart';
import '../utils/config_manager.dart';
import 'detection_screen.dart';

class BinSetupScreen extends StatefulWidget {
  final List<String> labels;
  final AppConfig? existingConfig;

  const BinSetupScreen({
    super.key,
    required this.labels,
    this.existingConfig,
  });

  @override
  State<BinSetupScreen> createState() => _BinSetupScreenState();
}

class _BinSetupScreenState extends State<BinSetupScreen> {
  List<BinCategory> _bins = [];
  /// label → assigned bin ID, or '__nothing__', or null (unmapped)
  final Map<String, String?> _labelAssignments = {};
  double _confidenceThreshold = 0.85;
  bool _isSaving = false;

  static const String _nothingOption = '__nothing__';

  // Theme Constants
  static const Color _accentGreen = Color(0xFF00E676);
  static const Color _accentCyan = Color(0xFF00B0FF);
  static const Color _bgSurface = Color(0x0CFFFFFF); // ~5% white
  static const Color _borderSubtle = Color(0x1AFFFFFF); // ~10% white

  static const String _paperBinId = 'bin_paper';
  static const String _plasticBinId = 'bin_plastic';

  static final List<BinCategory> _defaultBins = [
    BinCategory(
      id: _paperBinId,
      name: 'Paper',
      emoji: '📰',
      colorHex: const Color(0xFFFFA726).toARGB32(),
      mappedLabels: [],
    ),
    BinCategory(
      id: _plasticBinId,
      name: 'Plastic',
      emoji: '♻️',
      colorHex: const Color(0xFF42A5F5).toARGB32(),
      mappedLabels: [],
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Enforce portrait mode for the Waste Creation screen
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _bins = _defaultBins.map((b) => b.copyWith()).toList();

    if (widget.existingConfig != null) {
      final config = widget.existingConfig!;
      _confidenceThreshold = config.confidenceThreshold;
      // Restore label assignments from existing config
      for (final label in widget.labels) {
        if (config.nothingLabels
            .any((n) => n.toLowerCase() == label.toLowerCase())) {
          _labelAssignments[label] = _nothingOption;
        } else {
          String? foundBinId;
          for (final bin in config.bins) {
            if (bin.mappedLabels
                .any((m) => m.toLowerCase() == label.toLowerCase())) {
              // Map old bin assignments to fixed bin IDs
              final nameLower = bin.name.toLowerCase();
              if (nameLower == 'paper') {
                foundBinId = _paperBinId;
              } else if (nameLower == 'plastic') {
                foundBinId = _plasticBinId;
              } else if (bin.id == _paperBinId || bin.id == _plasticBinId) {
                foundBinId = bin.id;
              }
              if (foundBinId != null) break;
            }
          }
          _labelAssignments[label] = foundBinId;
        }
      }
    } else {
      for (final label in widget.labels) {
        _labelAssignments[label] = null;
      }
    }
  }

  Future<void> _saveAndNavigate() async {
    final mappedCount = _labelAssignments.values
        .where((v) => v != null && v != _nothingOption)
        .length;
    if (mappedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text('⚠️ Map at least one label to a bin.', style: GoogleFonts.inter()),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final List<BinCategory> finalBins = _bins.map((bin) {
      final mapped = _labelAssignments.entries
          .where((e) => e.value == bin.id)
          .map((e) => e.key)
          .toList();
      return bin.copyWith(mappedLabels: mapped);
    }).toList();

    final nothingLabels = _labelAssignments.entries
        .where((e) => e.value == _nothingOption)
        .map((e) => e.key)
        .toList();

    final config = AppConfig(
      bins: finalBins,
      confidenceThreshold: _confidenceThreshold,
      nothingLabels: nothingLabels,
    );

    await ConfigManager.saveConfig(config);
    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DetectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentCyan.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentGreen.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: const SizedBox(),
            ),
          ),

          // Main View
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                centerTitle: true,
                title: Text('Configuration',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5)),
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    
                    // ── Your Bins ──
                    _buildSectionHeader('Your Bins', Icons.delete_outline),
                    const SizedBox(height: 16),
                    ..._bins.map((bin) => _buildBinTile(bin)),

                    const SizedBox(height: 40),
                    
                    // ── Map Labels ──
                    _buildSectionHeader('Map Labels', Icons.schema_rounded),
                    const SizedBox(height: 8),
                    Text(
                      'Assign models to bins. Unmapped items are ignored.',
                      style: GoogleFonts.inter(color: Colors.white54, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    
                    if (widget.labels.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFFF5252)),
                            const SizedBox(width: 12),
                            Expanded(child: Text('No labels found. Check models.', style: GoogleFonts.inter(color: Colors.white70))),
                          ],
                        ),
                      )
                    else
                      ...widget.labels.map((label) => _buildLabelMappingCard(label)),

                    const SizedBox(height: 40),

                    // ── Settings ──
                    _buildSectionHeader('Confidence', Icons.tune_rounded),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _bgSurface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Threshold', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                                    style: GoogleFonts.robotoMono(color: _accentCyan, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _accentCyan,
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.white,
                              overlayColor: _accentCyan.withValues(alpha: 0.2),
                              trackHeight: 6,
                            ),
                            child: Slider(
                              value: _confidenceThreshold,
                              min: 0.50,
                              max: 0.99,
                              divisions: 49,
                              onChanged: (v) => setState(() => _confidenceThreshold = v),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Low values trigger falsely. High values require good angles.',
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),

                    // Bottom padding matching FAB height
                    const SizedBox(height: 120),
                  ]),
                ),
              ),
            ],
          ),

          // ── Sticky Save Button ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black, Colors.black.withValues(alpha: 0.0)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF1DE9B6)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveAndNavigate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2))
                      : Text(
                          'Save & Start Detecting',
                          style: GoogleFonts.inter(
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildBinTile(BinCategory bin) {
    final mappedCount = _labelAssignments.values.where((v) => v == bin.id).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Color(bin.colorHex).withValues(alpha: 0.5), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(bin.emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(bin.name, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Text('$mappedCount labels assigned', style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
      ),
    );
  }

  Widget _buildLabelMappingCard(String label) {
    final currentAssignment = _labelAssignments[label];

    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text('Ignore', style: GoogleFonts.inter(color: Colors.white54)),
      ),
      DropdownMenuItem<String?>(
        value: _nothingOption,
        child: Text('Skip (Background)', style: GoogleFonts.inter(color: Colors.orange.shade400)),
      ),
      ..._bins.map((bin) => DropdownMenuItem<String?>(
            value: bin.id,
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Color(bin.colorHex)),
                ),
                const SizedBox(width: 8),
                Text('${bin.emoji} ${bin.name}', style: GoogleFonts.inter(color: Colors.white)),
              ],
            ),
          )),
    ];

    Color stripColor = Colors.white10;
    if (currentAssignment == _nothingOption) {
      stripColor = Colors.orange.shade600;
    } else if (currentAssignment != null) {
      final b = _bins.firstWhere((b) => b.id == currentAssignment,
          orElse: () => BinCategory(id: '', name: '', emoji: '', colorHex: 0, mappedLabels: []));
      if (b.colorHex != 0) stripColor = Color(b.colorHex);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderSubtle),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 6, color: stripColor),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(right: 16),
              width: 160,
              child: Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: const Color(0xFF1E1E1E), // Dropdown menu bg
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: currentAssignment,
                    items: items,
                    onChanged: (val) => setState(() => _labelAssignments[label] = val),
                    isExpanded: true,
                    icon: const Icon(Icons.expand_more_rounded, color: Colors.white38),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
