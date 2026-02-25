import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';

class ConfigManager {
  static const _keyAppConfig = 'app_config';
  static const _keyLabelsList = 'labels_list';
  static const _keyModelLoaded = 'model_loaded';

  static Future<AppConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAppConfig);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return AppConfig.fromJsonString(jsonStr);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppConfig, config.toJsonString());
  }

  static Future<List<String>> loadLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyLabelsList);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(jsonStr) as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLabels(List<String> labels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLabelsList, jsonEncode(labels));
  }

  static Future<bool> isModelLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyModelLoaded) ?? false;
  }

  static Future<void> setModelLoaded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyModelLoaded, value);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAppConfig);
    await prefs.remove(_keyLabelsList);
    await prefs.remove(_keyModelLoaded);
  }
}
