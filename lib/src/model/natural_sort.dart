/// Compares strings so that embedded numbers sort numerically:
/// `2.txt` < `10.txt`.
///
/// Only equal strings compare as 0, so a sorted list of names has one possible
/// order (`02.txt` comes before `2.txt`).
int naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(a).map((m) => m[0]!).toList();
  final pb = re.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null)
        ? nx.compareTo(ny)
        : x.toLowerCase().compareTo(y.toLowerCase());
    if (c != 0) return c;
  }
  final c = pa.length.compareTo(pb.length);
  return c != 0 ? c : a.compareTo(b);
}
