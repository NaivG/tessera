/// 记忆关联 — 记录两条 MemoryEntry 之间的关系
///
/// 关系类型：
/// - `derived_from`：一条记忆从另一条衍生而来
/// - `contradicts`：两条记忆相互矛盾
/// - `supports`：一条记忆印证另一条
/// - `merged_into`：一条记忆已被合并到另一条（source 已被标记为删除）
class MemoryRelation {
  /// UUID 主键
  final String id;

  /// 源 MemoryEntry.id
  final String sourceId;

  /// 目标 MemoryEntry.id
  final String targetId;

  /// 关系类型
  final String relationType;

  /// 关联强度 0.0 ~ 1.0
  final double weight;

  const MemoryRelation({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationType,
    this.weight = 1.0,
  });

  /// 预定义关系类型常量
  static const derivedFrom = 'derived_from';
  static const contradicts = 'contradicts';
  static const supports = 'supports';
  static const mergedInto = 'merged_into';

  /// 创建
  factory MemoryRelation.create({
    required String id,
    required String sourceId,
    required String targetId,
    required String relationType,
    double weight = 1.0,
  }) {
    return MemoryRelation(
      id: id,
      sourceId: sourceId,
      targetId: targetId,
      relationType: relationType,
      weight: weight,
    );
  }

  /// 从数据库行创建
  factory MemoryRelation.fromDb(Map<String, dynamic> row) {
    return MemoryRelation(
      id: row['id'] as String,
      sourceId: row['source_id'] as String,
      targetId: row['target_id'] as String,
      relationType: row['relation_type'] as String,
      weight: (row['weight'] as num).toDouble(),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'source_id': sourceId,
      'target_id': targetId,
      'relation_type': relationType,
      'weight': weight,
    };
  }

  @override
  String toString() =>
      'MemoryRelation($sourceId -> $targetId, $relationType, w=$weight)';
}
