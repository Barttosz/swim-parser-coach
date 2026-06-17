import 'token.dart';
import '../models/intensity_zone.dart';

/// Lexer – tokenizuje tekst notatki trenerskiej
class SwimLexer {
  final List<String> knownAthletes;

  SwimLexer({required this.knownAthletes});

  // --- Słownik stref intensywności ---
  static const Map<String, IntensityZone> _zoneKeywords = {
    // Rec
    'rozpł': IntensityZone.rec,
    'rozp': IntensityZone.rec,
    'luz': IntensityZone.rec,
    'ćw.t': IntensityZone.rec,
    // EN1
    'tlenowo': IntensityZone.en1,
    'aktywny wypoczynek': IntensityZone.en1,
    'mocno': IntensityZone.en1,
    'progres': IntensityZone.en1,
    'progresja': IntensityZone.en1,
    'regres': IntensityZone.en1,
    'regresja': IntensityZone.en1,
    'r': IntensityZone.en1, // rozpędzanie – ostrożnie, krótkie
    'p': IntensityZone.en1, // P = 100% EN1 – obsługiwane w evaluatorze
    // EN2
    'progowo': IntensityZone.en2,
    // EN3
    'vo2 max': IntensityZone.en3,
    'vo2max': IntensityZone.en3,
    // SP2
    '95%': IntensityZone.sp2,
    // SP3
    'spr': IntensityZone.sp3,
    '(o-a)': IntensityZone.sp3,
  };

  // --- Złożone modyfikatory (P-L, ćw.t-R) ---
  static const Set<String> _splitModifiers = {
    'p-l',
    'ćw.t-r',
    'progowo-tlenowo',
  };

  /// Tokenizuje jedną linię tekstu
  List<Token> tokenizeLine(String line) {
    final tokens = <Token>[];
    final lowerLine = line.toLowerCase().trim();

    // Pomiń puste linie i komentarze (#)
    if (lowerLine.isEmpty || lowerLine.startsWith('#')) return tokens;

    // Sprawdź modyfikatory złożone (muszą być przed innymi)
    String remaining = line.trim();
    remaining = _extractTokens(remaining, tokens);

    return tokens;
  }

  String _extractTokens(String text, List<Token> tokens) {
    var pos = 0;
    final chars = text;
    final len = chars.length;

    while (pos < len) {
      // Pomiń białe znaki
      if (chars[pos] == ' ' || chars[pos] == '\t') {
        pos++;
        continue;
      }

      // --- Próbuj dopasować w kolejności priorytetów ---

      // 1. Wartość mmol: "3.5 mmol" lub "2,0mmol"
      final mmolMatch = RegExp(
        r'(\d+[.,]\d+)\s*mmol',
        caseSensitive: false,
      ).matchAtPosition(chars, pos);
      if (mmolMatch != null && mmolMatch.start == pos) {
        final raw = mmolMatch.group(0)!;
        final numStr = mmolMatch.group(1)!.replaceAll(',', '.');
        tokens.add(Token(
          type: TokenType.mmolValue,
          raw: raw,
          value: double.tryParse(numStr),
        ));
        pos += raw.length;
        continue;
      }

      // 2. Zakres mmol: "3-4 mmol" lub "2-3 mmol"
      final mmolRangeMatch = RegExp(
        r'(\d+[.,]?\d*)-(\d+[.,]?\d*)\s*mmol',
        caseSensitive: false,
      ).matchAtPosition(chars, pos);
      if (mmolRangeMatch != null && mmolRangeMatch.start == pos) {
        final raw = mmolRangeMatch.group(0)!;
        final low = double.tryParse(
              mmolRangeMatch.group(1)!.replaceAll(',', '.'),
            ) ??
            0;
        final high = double.tryParse(
              mmolRangeMatch.group(2)!.replaceAll(',', '.'),
            ) ??
            0;
        tokens.add(Token(
          type: TokenType.mmolValue,
          raw: raw,
          value: [low, high], // lista oznacza zakres
        ));
        pos += raw.length;
        continue;
      }

      // 3. Procenty: "95%"
      final pctMatch = RegExp(r'(\d+)%').matchAtPosition(chars, pos);
      if (pctMatch != null && pctMatch.start == pos) {
        final raw = pctMatch.group(0)!;
        final pct = int.tryParse(pctMatch.group(1)!) ?? 0;
        final zone = pct >= 95 ? IntensityZone.sp2 : null;
        tokens.add(Token(
          type: TokenType.percentage,
          raw: raw,
          value: {'percent': pct, 'zone': zone},
        ));
        pos += raw.length;
        continue;
      }

      // 4. Mnożnik: "12x" lub "12X"
      final multMatch = RegExp(r'(\d+)[xX]').matchAtPosition(chars, pos);
      if (multMatch != null && multMatch.start == pos) {
        final raw = multMatch.group(0)!;
        final n = int.tryParse(multMatch.group(1)!) ?? 1;
        tokens.add(Token(type: TokenType.multiplier, raw: raw, value: n));
        pos += raw.length;
        continue;
      }

      // 5. Dystans metryczny: "300m" lub "300" (cyfry standalone)
      final distMatch = RegExp(r'(\d+)\s*m\b').matchAtPosition(chars, pos);
      if (distMatch != null && distMatch.start == pos) {
        final raw = distMatch.group(0)!;
        final meters = int.tryParse(distMatch.group(1)!) ?? 0;
        tokens.add(Token(type: TokenType.distance, raw: raw, value: meters));
        pos += raw.length;
        continue;
      }

      // 6. Liczba bez jednostki (dystans lub mnożnik) – tylko jeśli jest sensowna
      final numMatch = RegExp(r'(\d+)').matchAtPosition(chars, pos);
      if (numMatch != null && numMatch.start == pos) {
        // Sprawdź, czy nie jest częścią słowa kluczowego
        final after = pos + numMatch.group(0)!.length;
        final isFollowedByLetter =
            after < len && RegExp(r'[a-zA-ZąćęłńóśźżĄĆĘŁŃÓŚŹŻ]').hasMatch(chars[after]);
        if (!isFollowedByLetter) {
          final raw = numMatch.group(0)!;
          final n = int.tryParse(raw) ?? 0;
          tokens.add(Token(type: TokenType.distance, raw: raw, value: n));
          pos += raw.length;
          continue;
        }
      }

      // 7. Operatory
      if (chars[pos] == '(') {
        tokens.add(Token(type: TokenType.parenOpen, raw: '('));
        pos++;
        continue;
      }
      if (chars[pos] == ')') {
        tokens.add(Token(type: TokenType.parenClose, raw: ')'));
        pos++;
        continue;
      }
      if (chars[pos] == '+') {
        tokens.add(Token(type: TokenType.plus, raw: '+'));
        pos++;
        continue;
      }
      if (chars[pos] == '/') {
        tokens.add(Token(type: TokenType.slash, raw: '/'));
        pos++;
        continue;
      }
      if (chars[pos] == ',') {
        tokens.add(Token(type: TokenType.separator, raw: ','));
        pos++;
        continue;
      }

      // 8. Słowa kluczowe – próbuj od najdłuższych
      bool foundKeyword = false;
      final remainingText = chars.substring(pos).toLowerCase();

      // Modyfikatory złożone (P-L, ćw.t-R)
      for (final mod in _splitModifiers) {
        if (remainingText.startsWith(mod)) {
          tokens.add(Token(
            type: TokenType.zoneKeyword,
            raw: chars.substring(pos, pos + mod.length),
            value: mod,
          ));
          pos += mod.length;
          foundKeyword = true;
          break;
        }
      }
      if (foundKeyword) continue;

      // Strefy (sortuj malejąco po długości)
      final sortedKeywords = _zoneKeywords.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final kw in sortedKeywords) {
        if (remainingText.startsWith(kw)) {
          // Upewnij się, że to nie jest środek słowa
          final afterKw = pos + kw.length;
          final isWordBound = afterKw >= len ||
              RegExp(r'[\s,.()/+]').hasMatch(chars[afterKw]);
          if (isWordBound) {
            tokens.add(Token(
              type: TokenType.zoneKeyword,
              raw: chars.substring(pos, afterKw),
              value: _zoneKeywords[kw],
            ));
            pos = afterKw;
            foundKeyword = true;
            break;
          }
        }
      }
      if (foundKeyword) continue;

      // 9. Nazwy zawodników (z dostarczonej listy)
      bool foundAthlete = false;
      final sortedAthletes = knownAthletes.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final name in sortedAthletes) {
        if (remainingText.startsWith(name.toLowerCase())) {
          final afterName = pos + name.length;
          // Sprawdź, czy po nazwie jest mnożnik personalny (np. "Wika 1x")
          final afterSpaces = _skipSpaces(chars, afterName);
          final multAfterMatch = RegExp(r'(\d+)[xX]').matchAtPosition(chars, afterSpaces);
          if (multAfterMatch != null && multAfterMatch.start == afterSpaces) {
            final mult = int.tryParse(multAfterMatch.group(1)!) ?? 1;
            tokens.add(Token(
              type: TokenType.personalMod,
              raw: '${chars.substring(pos, afterName)} ${multAfterMatch.group(0)!}',
              value: {'name': name, 'multiplier': mult},
            ));
            pos = afterSpaces + multAfterMatch.group(0)!.length;
          } else {
            tokens.add(Token(
              type: TokenType.athleteName,
              raw: chars.substring(pos, afterName),
              value: name,
            ));
            pos = afterName;
          }
          foundAthlete = true;
          break;
        }
      }
      if (foundAthlete) continue;

      // 10. Szum – skocz do następnego separatora lub konca słowa
      final noiseEnd = _findNoiseEnd(chars, pos);
      tokens.add(Token(
        type: TokenType.noise,
        raw: chars.substring(pos, noiseEnd),
      ));
      pos = noiseEnd;
    }

    return '';
  }

  int _skipSpaces(String s, int pos) {
    while (pos < s.length && (s[pos] == ' ' || s[pos] == '\t')) {
      pos++;
    }
    return pos;
  }

  int _findNoiseEnd(String s, int start) {
    var i = start + 1;
    while (i < s.length && !RegExp(r'[\s,.()/+\d]').hasMatch(s[i])) {
      i++;
    }
    return i;
  }

  /// Tokenizuje cały tekst sesji, zwracając linie z tokenami
  List<List<Token>> tokenizeSession(String text) {
    return text
        .split('\n')
        .map((line) => tokenizeLine(line))
        .where((tokens) => tokens.isNotEmpty)
        .toList();
  }
}

/// Prosta klasa opakowująca dopasowanie regex z przesunięciem pozycji
class _OffsetMatch {
  final RegExpMatch _inner;
  final int _offset;
  _OffsetMatch(this._inner, this._offset);

  int get start => _inner.start + _offset;
  int get end => _inner.end + _offset;
  String? group(int g) => _inner.group(g);
}

extension _RegExpMatchAt on RegExp {
  _OffsetMatch? matchAtPosition(String text, int pos) {
    final match = firstMatch(text.substring(pos));
    if (match == null || match.start != 0) return null;
    return _OffsetMatch(match, pos);
  }
}
