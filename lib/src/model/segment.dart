/// Which side of a segment a piece of text belongs to.
enum Side { source, target }

/// An editable part of a segment.
enum Field {
  source,
  target,
  remark;

  /// The side this field splits on; a remark has none.
  Side? get side => switch (this) {
    Field.source => Side.source,
    Field.target => Side.target,
    Field.remark => null,
  };
}

/// One row of the parallel text: a source paragraph, its translation and an
/// optional remark.
///
/// Source and target never contain line breaks. The remark may span several
/// lines (joined with `\n`).
class Segment {
  Segment({
    required this.id,
    this.source = '',
    this.target = '',
    this.remark = '',
  });

  /// Short, chapter-unique identifier that stays with the row across edits.
  final String id;
  final String source;
  final String target;
  final String remark;

  bool get hasRemark => remark.isNotEmpty;

  String text(Side side) => side == Side.source ? source : target;

  String field(Field field) => switch (field) {
    Field.source => source,
    Field.target => target,
    Field.remark => remark,
  };

  Segment copyWith({String? source, String? target, String? remark}) => Segment(
    id: id,
    source: source ?? this.source,
    target: target ?? this.target,
    remark: remark ?? this.remark,
  );

  Segment withText(Side side, String value) =>
      side == Side.source ? copyWith(source: value) : copyWith(target: value);

  Segment withField(Field field, String value) => switch (field) {
    Field.source => copyWith(source: value),
    Field.target => copyWith(target: value),
    Field.remark => copyWith(remark: value),
  };

  @override
  bool operator ==(Object other) =>
      other is Segment &&
      other.id == id &&
      other.source == source &&
      other.target == target &&
      other.remark == remark;

  @override
  int get hashCode => Object.hash(id, source, target, remark);

  @override
  String toString() =>
      'Segment($id, src: "$source", tgt: "$target", remark: "$remark")';
}
