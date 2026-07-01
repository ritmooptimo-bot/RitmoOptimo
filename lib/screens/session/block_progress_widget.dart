import 'package:flutter/material.dart';
import '../../config/skins/skin_config.dart';
import '../../core/audio/session_audio_controller.dart';

class BlockProgressWidget extends StatelessWidget {
  final SessionBlockUIState uiState;
  final SkinConfig skin;
  final VoidCallback onSkip;

  const BlockProgressWidget({
    super.key,
    required this.uiState,
    required this.skin,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(color: skin.accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BlockHeader(uiState: uiState, skin: skin),
          if (uiState.isInterval)
            _IntervalProgress(uiState: uiState, skin: skin)
          else
            _LinearProgress(uiState: uiState, skin: skin),
          _SkipButton(skin: skin, onSkip: onSkip),
        ],
      ),
    );
  }
}

// ── Cabecera: número de bloque + nombre ─────────────────────────────────

class _BlockHeader extends StatelessWidget {
  final SessionBlockUIState uiState;
  final SkinConfig skin;
  const _BlockHeader({required this.uiState, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: skin.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${uiState.blockNumber}/${uiState.totalBlocks}',
              style: TextStyle(
                color: skin.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: skin.fontFamilyMono,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              uiState.blockLabel,
              style: TextStyle(
                color: skin.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (uiState.blockRemainingSeconds != null) ...[
            const SizedBox(width: 8),
            _CountdownPill(seconds: uiState.blockRemainingSeconds!, skin: skin),
          ],
        ],
      ),
    );
  }
}

class _CountdownPill extends StatelessWidget {
  final int seconds;
  final SkinConfig skin;
  const _CountdownPill({required this.seconds, required this.skin});

  @override
  Widget build(BuildContext context) {
    final isWarning = seconds <= 30;
    final color = isWarning ? skin.warning : skin.textMuted;
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return Text(
      '$m:$s',
      style: TextStyle(
        fontFamily: skin.fontFamilyMono,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

// ── Progreso lineal (bloques normales) ─────────────────────────────────

class _LinearProgress extends StatelessWidget {
  final SessionBlockUIState uiState;
  final SkinConfig skin;
  const _LinearProgress({required this.uiState, required this.skin});

  @override
  Widget build(BuildContext context) {
    final total     = uiState.blockDurationSeconds;
    final remaining = uiState.blockRemainingSeconds;
    if (total == null || remaining == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          'Bloque de duración libre — toca "Saltar" para continuar.',
          style: TextStyle(color: skin.textMuted, fontSize: 11),
        ),
      );
    }
    final progress = ((total - remaining) / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: skin.border,
          valueColor: AlwaysStoppedAnimation<Color>(skin.accent),
        ),
      ),
    );
  }
}

// ── Progreso intervalos (rep + descanso) ──────────────────────────────

class _IntervalProgress extends StatelessWidget {
  final SessionBlockUIState uiState;
  final SkinConfig skin;
  const _IntervalProgress({required this.uiState, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: uiState.isResting
          ? _RestRow(uiState: uiState, skin: skin)
          : _RepRow(uiState: uiState, skin: skin),
    );
  }
}

class _RestRow extends StatelessWidget {
  final SessionBlockUIState uiState;
  final SkinConfig skin;
  const _RestRow({required this.uiState, required this.skin});

  @override
  Widget build(BuildContext context) {
    final restSec = uiState.restRemainingSeconds ?? 0;
    final m = restSec ~/ 60;
    final s = (restSec % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        Icon(Icons.hourglass_bottom, size: 16, color: skin.accentSecondary),
        const SizedBox(width: 8),
        Text(
          'Descanso',
          style: TextStyle(color: skin.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(
          '$m:$s',
          style: TextStyle(
            fontFamily: skin.fontFamilyMono,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: skin.accentSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Serie ${uiState.currentRep + 1}/${uiState.totalReps}',
          style: TextStyle(color: skin.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _RepRow extends StatelessWidget {
  final SessionBlockUIState uiState;
  final SkinConfig skin;
  const _RepRow({required this.uiState, required this.skin});

  @override
  Widget build(BuildContext context) {
    final repEl  = uiState.repElapsedSeconds ?? 0;
    final repDur = uiState.repDurationSeconds;
    final m = repEl ~/ 60;
    final s = (repEl % 60).toString().padLeft(2, '0');
    double progress = 0;
    if (repDur != null && repDur > 0) {
      progress = (repEl / repDur).clamp(0.0, 1.0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: skin.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: skin.error.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${uiState.currentRep}/${uiState.totalReps}',
                style: TextStyle(
                  color: skin.error,
                  fontFamily: skin.fontFamilyMono,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'EN CURSO',
              style: TextStyle(
                color: skin.error,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            Text(
              '$m:$s',
              style: TextStyle(
                fontFamily: skin.fontFamilyMono,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: skin.error,
              ),
            ),
          ],
        ),
        if (repDur != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: skin.border,
              valueColor: AlwaysStoppedAnimation<Color>(skin.error),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Botón saltar bloque ────────────────────────────────────────────────

class _SkipButton extends StatelessWidget {
  final SkinConfig skin;
  final VoidCallback onSkip;
  const _SkipButton({required this.skin, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onSkip,
          icon: Icon(Icons.skip_next, size: 16, color: skin.textMuted),
          label: Text(
            'Saltar bloque',
            style: TextStyle(
              color: skin.textMuted,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
