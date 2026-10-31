import 'dart:math';

const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
const idLength = 5;

final _random = Random.secure();

/// Returns a random [idLength]-character id that is not in [taken].
String newId(Set<String> taken, {Random? random}) {
  final r = random ?? _random;
  while (true) {
    final id = String.fromCharCodes(
      List.generate(
        idLength,
        (_) => _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
      ),
    );
    if (!taken.contains(id)) return id;
  }
}

/// Whether [id] is acceptable in a chapter file: non-empty, no whitespace.
bool isValidId(String id) => id.isNotEmpty && !id.contains(RegExp(r'\s'));

