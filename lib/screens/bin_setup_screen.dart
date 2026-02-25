import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.existingConfig != null) {
      final config = widget.existingConfig!;
      _bins = List.from(config.bins.map((b) => b.copyWith()));
      _confidenceThreshold = config.confidenceThreshold;
      // Restore label assignments
      for (final label in widget.labels) {
        if (config.nothingLabels
            .any((n) => n.toLowerCase() == label.toLowerCase())) {
          _labelAssignments[label] = _nothingOption;
        } else {
          String? foundBinId;
          for (final bin in _bins) {
            if (bin.mappedLabels
                .any((m) => m.toLowerCase() == label.toLowerCase())) {
              foundBinId = bin.id;
              break;
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

  String _generateBinId() =>
      'bin_${DateTime.now().millisecondsSinceEpoch}';


  void _showAddEditBinSheet({BinCategory? existing}) {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    final emojiController =
        TextEditingController(text: existing?.emoji ?? '♻️');
    Color pickedColor =
        existing != null ? Color(existing.colorHex) : Colors.blue;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'Add New Bin' : 'Edit Bin',
                  style: const TextStyle(
                      color: Color(0xFF08090E),
                      fontSize: 20,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                // Bin name
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Color(0xFF08090E)),
                  decoration: _inputDecoration('Bin Name (e.g. Plastic Bin)'),
                ),
                const SizedBox(height: 12),
                // Emoji
                TextField(
                  controller: emojiController,
                  style: const TextStyle(color: Color(0xFF08090E), fontSize: 24),
                  decoration: _inputDecoration('Emoji (e.g. ♻️)'),
                ),
                const SizedBox(height: 16),
                // Color picker
                const Text(
                  'Bin Color:',
                  style: TextStyle(
                      color: Color(0xFF727067), fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ColorPicker(
                    pickerColor: pickedColor,
                    onColorChanged: (c) =>
                        setSheetState(() => pickedColor = c),
                    pickerAreaHeightPercent: 0.7,
                    labelTypes: const [],
                    displayThumbColor: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF727067),
                          side: const BorderSide(color: Color(0xFFABA69E)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Bin name cannot be empty')),
                            );
                            return;
                          }
                          final emoji =
                              emojiController.text.trim().isNotEmpty
                                  ? emojiController.text.trim()
                                  : '🗑️';
                          setState(() {
                            if (existing == null) {
                              _bins.add(BinCategory(
                                id: _generateBinId(),
                                name: name,
                                emoji: emoji,
                                colorHex: pickedColor.toARGB32(),
                                mappedLabels: [],
                              ));
                            } else {
                              final idx = _bins
                                  .indexWhere((b) => b.id == existing.id);
                              if (idx != -1) {
                                _bins[idx] = existing.copyWith(
                                  name: name,
                                  emoji: emoji,
                                  colorHex: pickedColor.toARGB32(),
                                );
                              }
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Save',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _deleteBin(String binId) {
    setState(() {
      _bins.removeWhere((b) => b.id == binId);
      // Unmap labels that were assigned to this bin
      for (final key in _labelAssignments.keys.toList()) {
        if (_labelAssignments[key] == binId) {
          _labelAssignments[key] = null;
        }
      }
    });
  }

  Future<void> _saveAndNavigate() async {
    if (_bins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '⚠️ Please create at least one bin before saving.')),
      );
      return;
    }

    final mappedCount = _labelAssignments.values
        .where((v) => v != null && v != _nothingOption)
        .length;
    if (mappedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '⚠️ Map at least one label to a bin before saving.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Build final bin list with mapped labels
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFABA69E)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFABA69E), width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFABA69E), width: 0.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Bin Setup',
            style: GoogleFonts.inter(color: const Color(0xFF08090E), fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── SECTION A: Your Bins ───
          _sectionHeader('Your Bins'),
          const SizedBox(height: 8),
          // Example hint
          if (_bins.isEmpty)
            _exampleHintCard(),
          ..._bins.asMap().entries.map((entry) {
            final bin = entry.value;
            return _binTile(bin);
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showAddEditBinSheet(),
            icon: const Icon(Icons.add, color: Color(0xFF08090E)),
            label: const Text('Add New Bin',
                style: TextStyle(color: Color(0xFF08090E))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF08090E), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),

          // ─── SECTION B: Map Labels to Bins ───
          _sectionHeader('Map Labels to Bins'),
          const SizedBox(height: 4),
          const Text(
            'Assign each detected class to a bin, mark it as "Nothing / Skip" (background), or leave it Unmapped.',
            style: TextStyle(
                color: Color(0xFF727067), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (widget.labels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No labels found. Please re-upload your labels.txt file.',
                style: TextStyle(color: Color(0xFFC62828)),
              ),
            )
          else
            ...widget.labels.map((label) => _labelMappingRow(label)),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),

          // ─── SECTION C: Settings ───
          _sectionHeader('Settings'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFABA69E), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Detection Sensitivity',
                      style: TextStyle(
                          color: Color(0xFF08090E),
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Color(0xFF08090E),
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ],
                ),
                Slider(
                  value: _confidenceThreshold,
                  min: 0.50,
                  max: 0.99,
                  divisions: 49,
                  activeColor: const Color(0xFF08090E),
                  inactiveColor: const Color(0xFFABA69E).withValues(alpha: 0.3),
                  onChanged: (v) =>
                      setState(() => _confidenceThreshold = v),
                ),
                const Text(
                  'Only show a detection result when confidence exceeds this threshold.',
                  style: TextStyle(
                      color: Color(0xFF727067), fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ─── Save Button ───
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveAndNavigate,
              child: _isSaving
                  ? const CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)
                  : const Text(
                      '✅ Save & Start Detecting',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
          color: const Color(0xFF08090E),
          fontSize: 18,
          fontWeight: FontWeight.w600),
    );
  }

  Widget _exampleHintCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFABA69E), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💡 Example Configuration',
            style: TextStyle(
                color: Color(0xFF08090E),
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
          const SizedBox(height: 8),
          _hintLine('♻️ Plastic Bin (Blue)',
              'Plastic Pen, Plastic Bottle, Plastic Cover, Plastic Bag'),
          _hintLine('🪙 Metal Bin (Silver)',
              'Tin Can, Aluminium Foil, Metal Screw, Battery'),
          _hintLine(
              '📰 Paper Bin (Yellow)', 'Newspaper, Cardboard, Paper Cup'),
          _hintLine('Nothing Labels', 'Nothing, Background, Empty'),
        ],
      ),
    );
  }

  Widget _hintLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  color: Color(0xFF08090E),
                  fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Color(0xFF727067)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _binTile(BinCategory bin) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFABA69E), width: 0.5),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Text(bin.emoji, style: const TextStyle(fontSize: 26)),
        title: Text(bin.name,
            style: const TextStyle(
                color: Color(0xFF08090E), fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color dot
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Color(bin.colorHex),
                shape: BoxShape.circle,
                border:
                    Border.all(color: const Color(0xFFABA69E), width: 1),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: Color(0xFF727067), size: 20),
              onPressed: () => _showAddEditBinSheet(existing: bin),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFC62828), size: 20),
              onPressed: () => _deleteBin(bin.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelMappingRow(String label) {
    final currentAssignment = _labelAssignments[label];

    // Build dropdown items
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text(
          'Leave Unmapped',
          style: TextStyle(color: Color(0xFFABA69E)),
        ),
      ),
      DropdownMenuItem<String?>(
        value: _nothingOption,
        child: Text('Nothing / Skip',
            style: TextStyle(color: Colors.orange.shade700)),
      ),
      ..._bins.map(
        (bin) => DropdownMenuItem<String?>(
          value: bin.id,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Color(bin.colorHex),
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                '${bin.emoji} ${bin.name}',
                style: const TextStyle(color: Color(0xFF08090E)),
              ),
            ],
          ),
        ),
      ),
    ];

    // Indicator dot color
    Color dotColor;
    if (currentAssignment == null) {
      dotColor = const Color(0xFFABA69E).withValues(alpha: 0.5);
    } else if (currentAssignment == _nothingOption) {
      dotColor = Colors.orange.shade700;
    } else {
      final bin = _bins.firstWhere((b) => b.id == currentAssignment,
          orElse: () => BinCategory(
              id: '', name: '', emoji: '', colorHex: 0xFFFFFFFF, mappedLabels: []));
      dotColor = Color(bin.colorHex);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFABA69E), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF08090E), fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String?>(
              value: currentAssignment,
              items: items,
              onChanged: (val) =>
                  setState(() => _labelAssignments[label] = val),
              dropdownColor: Colors.white,
              underline: Container(height: 1, color: const Color(0xFFABA69E).withValues(alpha: 0.3)),
              isExpanded: true,
              style: const TextStyle(color: Color(0xFF08090E), fontSize: 13),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF727067)),
            ),
          ),
        ],
      ),
    );
  }
}
