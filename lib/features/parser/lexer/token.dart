/// Typy tokenów rozpoznawanych przez lexer
enum TokenType {
  multiplier,     // np. "12x", "2x"
  distance,       // np. "300", "50m"
  mmolValue,      // np. "3.5 mmol", "2,0 mmol"
  percentage,     // np. "95%"
  zoneKeyword,    // rozpoznane słowo kluczowe strefy
  athleteName,    // nazwa zawodnika (z listy)
  personalMod,    // modyfikator personalny z mnożnikiem, np. "Wika 1x"
  parenOpen,      // "("
  parenClose,     // ")"
  plus,           // "+"
  slash,          // "/"
  separator,      // ","
  noise,          // ignorowany szum
}

/// Token – jednostka leksykalna
class Token {
  final TokenType type;
  final String raw;       // oryginalna wartość tekstowa
  final dynamic value;    // sparsowana wartość (int, double, String...)

  const Token({
    required this.type,
    required this.raw,
    this.value,
  });

  @override
  String toString() => 'Token(${type.name}, "$raw", $value)';
}
