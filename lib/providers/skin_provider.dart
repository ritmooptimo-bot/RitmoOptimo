import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/skins/skin_config.dart';
import '../config/skins/dark_light_skin.dart';
import '../config/skins/f1_skin.dart';

const _kSkinKey      = 'selected_skin_id';
const _kDarkModeKey  = 'dark_mode_enabled';

// ── Mapa de skins disponibles ────────────────────────────────────
// Para añadir un nuevo skin en el futuro: solo añadir aquí.
final Map<String, SkinConfig> availableSkins = {
  'dark':  darkSkin,
  'light': lightSkin,
  'f1':    f1Skin,
};

// ── State ─────────────────────────────────────────────────────────
class SkinState {
  final SkinConfig skin;
  final bool isDark;

  const SkinState({required this.skin, required this.isDark});

  SkinState copyWith({SkinConfig? skin, bool? isDark}) => SkinState(
    skin:   skin   ?? this.skin,
    isDark: isDark ?? this.isDark,
  );
}

// ── Notifier ─────────────────────────────────────────────────────
class SkinNotifier extends StateNotifier<SkinState> {
  SkinNotifier() : super(const SkinState(skin: darkSkin, isDark: true)) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kSkinKey) ?? 'dark';
    final savedDark = prefs.getBool(_kDarkModeKey) ?? true;
    final skin = availableSkins[savedId] ?? darkSkin;
    state = SkinState(skin: skin, isDark: savedDark);
  }

  Future<void> setSkin(String skinId) async {
    final skin = availableSkins[skinId];
    if (skin == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkinKey, skinId);
    state = state.copyWith(skin: skin);
  }

  Future<void> toggleDarkLight() async {
    // Solo aplica cuando está en skin dark/light (no F1)
    if (state.skin.id != SkinId.darkLight) return;
    final nowDark = !state.isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkModeKey, nowDark);
    await prefs.setString(_kSkinKey, nowDark ? 'dark' : 'light');
    state = SkinState(
      skin:   nowDark ? darkSkin : lightSkin,
      isDark: nowDark,
    );
  }
}

// ── Providers ────────────────────────────────────────────────────
final skinProvider = StateNotifierProvider<SkinNotifier, SkinState>(
  (ref) => SkinNotifier(),
);

// Acceso directo al skin activo (el más usado)
final activeSkinProvider = Provider<SkinConfig>(
  (ref) => ref.watch(skinProvider).skin,
);
