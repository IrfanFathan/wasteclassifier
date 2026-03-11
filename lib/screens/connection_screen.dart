import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/esp32_service.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _isChecking = false;
  String _statusMsg = '';
  bool? _isConnected;

  static const Color _accentGreen = Color(0xFF00E676);
  static const Color _accentCyan = Color(0xFF00B0FF);

  Future<void> _checkConnection() async {
    setState(() {
      _isChecking = true;
      _statusMsg = 'Pinging 192.168.1.200...';
    });
    
    final success = await Esp32Service().checkConnection();
    
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _isConnected = success;
      _statusMsg = success 
          ? 'ESP32 Connected' 
          : 'ESP32 Not Connected';
    });

    if (success) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      _proceedToApp();
    }
  }

  void _proceedToApp() {
    Navigator.of(context).pushReplacementNamed('/upload');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentCyan.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentGreen.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: const SizedBox(),
            ),
          ),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Icon(
                        _isConnected == true 
                            ? Icons.wifi_rounded 
                            : _isConnected == false 
                                ? Icons.wifi_off_rounded 
                                : Icons.sensors_rounded, 
                        color: _isConnected == true ? _accentGreen : (_isConnected == false ? const Color(0xFFFF5252) : _accentCyan),
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'ESP32 Link',
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 32,
                          letterSpacing: -1,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Connect your phone to the ESP32 Wi-Fi hotspot to transmit detection data to the dashboard.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: Colors.white54, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    
                    // Status Card
                    if (_statusMsg.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: _isConnected == true
                              ? _accentGreen.withValues(alpha: 0.1)
                              : _isConnected == false
                                  ? const Color(0xFFFF5252).withValues(alpha: 0.1)
                                  : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isConnected == true
                                ? _accentGreen.withValues(alpha: 0.3)
                                : _isConnected == false
                                    ? const Color(0xFFFF5252).withValues(alpha: 0.3)
                                    : Colors.white10,
                          ),
                        ),
                        child: Text(
                          _statusMsg,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: _isConnected == true
                                ? _accentGreen
                                : _isConnected == false
                                    ? const Color(0xFFFF5252)
                                    : Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      
                    // Actions
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E676), Color(0xFF1DE9B6)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E676).withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isChecking ? null : _checkConnection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isChecking
                          ? const SizedBox(
                              width: 24, height: 24, 
                              child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2))
                          : Text(
                              'Test Connection',
                              style: GoogleFonts.inter(
                                  color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _proceedToApp,
                      child: Text(
                        'Skip for now (No ESP32)',
                        style: GoogleFonts.inter(
                            color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
