import '../models/tool.dart';
import '../plugin/lua_plugin_host.dart' show PluginSkill;
import 'tool_registry.dart';

// =============================================================================
// DiscoverManager — 统一发现管理器
//
// 合并原本分离的 Skill 与 Tool 搜索，统一返回「轻量摘要」——
// **不包含 parameter schema**。
//
// 设计原则：
// - LLM 负责选工具，Runtime 负责参数验证
// - Schema 仅在真正需要构造/校验参数时才暴露
// =============================================================================

/// 统一发现管理器
class DiscoverManager {
  /// 构造 system prompt 中的紧凑 skill 目录
  ///
  /// 仅展示 skills 的概要（name + tags + capabilities），不包含 tool schema。
  String buildCompactCatalog(List<PluginSkill> skills) {
    if (skills.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('## Available Skills');
    buf.writeln('Use the `discover` tool to get details and find tools.');
    buf.writeln();
    for (final s in skills) {
      final tags = s.tags.isNotEmpty ? '[${s.tags.join(", ")}] ' : '';
      final caps = s.capabilities.isNotEmpty
          ? ' (${s.capabilities.join(", ")})'
          : '';
      buf.writeln('- $tags**${s.name}**$caps: $s.description');
    }
    return buf.toString();
  }

  /// 构造 discover 工具使用说明
  String buildDiscoverGuidance() {
    return '''
## Discovery
Use the `discover` tool to find skills and tools by keyword, capability, or tag.
- It returns lightweight summaries (name, description, capabilities) — NOT full schemas.
- Once you decide to call a tool, the runtime validates your arguments against the full schema.
  If validation fails, the schema is returned to you in the error so you can correct the call.
- Prefer `discover({capability: "web.search"})` for precise lookup; use `query` for fuzzy search.''';
  }

  /// 统一发现：返回 skills + tools 的轻量摘要
  DiscoverResult discover({
    required List<PluginSkill> skills,
    required ToolRegistry toolRegistry,
    String? query,
    String? capability,
    String? tag,
    /// "skill" / "tool" / "all"
    String kind = 'all',
  }) {
    final skillResults = <SkillSummary>[];
    final toolResults = <ToolSummary>[];

    if (kind == 'skill' || kind == 'all') {
      skillResults.addAll(_matchSkills(
        skills: skills,
        query: query,
        capability: capability,
        tag: tag,
      ));
    }

    if (kind == 'tool' || kind == 'all') {
      toolResults.addAll(_matchTools(
        registry: toolRegistry,
        query: query,
        capability: capability,
        tag: tag,
      ));
    }

    return DiscoverResult(skills: skillResults, tools: toolResults);
  }

  List<SkillSummary> _matchSkills({
    required List<PluginSkill> skills,
    String? query,
    String? capability,
    String? tag,
  }) {
    final q = query?.toLowerCase();
    return skills.where((s) {
      if (capability != null && !s.capabilities.contains(capability)) {
        return false;
      }
      if (tag != null && !s.tags.contains(tag)) return false;
      if (q != null && q.isNotEmpty) {
        final hitName = s.name.toLowerCase().contains(q);
        final hitDesc = s.description.toLowerCase().contains(q);
        final hitCap = s.capabilities.any((c) => c.toLowerCase().contains(q));
        final hitTag = s.tags.any((t) => t.toLowerCase().contains(q));
        if (!(hitName || hitDesc || hitCap || hitTag)) return false;
      }
      return true;
    }).map((s) => SkillSummary(
      name: s.name,
      description: s.description,
      tags: s.tags,
      capabilities: s.capabilities,
    )).toList();
  }

  List<ToolSummary> _matchTools({
    required ToolRegistry registry,
    String? query,
    String? capability,
    String? tag,
  }) {
    Iterable<ToolDefinition> pool;
    if (capability != null) {
      pool = registry.findByCapability(capability);
    } else if (tag != null) {
      pool = registry.findByTag(tag);
    } else if (query != null && query.isNotEmpty) {
      pool = registry.search(query);
    } else {
      pool = registry.definitions;
    }

    final q = query?.toLowerCase();
    return pool.where((t) {
      if (q == null || q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q) ||
          t.capabilities.any((c) => c.toLowerCase().contains(q)) ||
          t.tags.any((tg) => tg.toLowerCase().contains(q));
    }).map((t) => ToolSummary(
      name: t.name,
      description: t.description,
      tags: t.tags,
      capabilities: t.capabilities,
      // 注意：故意不暴露 t.parameters
    )).toList();
  }
}

// =============================================================================
// 结果模型
// =============================================================================

class DiscoverResult {
  final List<SkillSummary> skills;
  final List<ToolSummary> tools;

  const DiscoverResult({
    this.skills = const [],
    this.tools = const [],
  });

  String toDisplayString() {
    final buf = StringBuffer();
    if (skills.isNotEmpty) {
      buf.writeln('## Matching Skills');
      for (final s in skills) {
        buf.writeln(s.toDisplayString());
        buf.writeln();
      }
    }
    if (tools.isNotEmpty) {
      buf.writeln('## Matching Tools');
      for (final t in tools) {
        buf.writeln(t.toDisplayString());
        buf.writeln();
      }
    }
    if (skills.isEmpty && tools.isEmpty) {
      buf.writeln('No matching skills or tools.');
    }
    return buf.toString();
  }

  /// 返回所有匹配到的工具名集合（用于 _discoveredInSession 追踪）
  Set<String> get discoveredToolNames =>
      tools.map((t) => t.name).toSet();
}

class SkillSummary {
  final String name;
  final String description;
  final Set<String> tags;
  final Set<String> capabilities;

  const SkillSummary({
    required this.name,
    required this.description,
    this.tags = const {},
    this.capabilities = const {},
  });

  String toDisplayString() {
    final buf = StringBuffer()..writeln('- Skill: $name');
    buf.writeln('  Description: $description');
    if (capabilities.isNotEmpty) {
      buf.writeln('  Capabilities: ${capabilities.join(", ")}');
    }
    if (tags.isNotEmpty) buf.writeln('  Tags: ${tags.join(", ")}');
    return buf.toString();
  }
}

class ToolSummary {
  final String name;
  final String description;
  final Set<String> tags;
  final Set<String> capabilities;
  // 不包含 parameters

  const ToolSummary({
    required this.name,
    required this.description,
    this.tags = const {},
    this.capabilities = const {},
  });

  String toDisplayString() {
    final buf = StringBuffer()..writeln('- Tool: $name');
    buf.writeln('  Description: $description');
    if (capabilities.isNotEmpty) {
      buf.writeln('  Capabilities: ${capabilities.join(", ")}');
    }
    if (tags.isNotEmpty) buf.writeln('  Tags: ${tags.join(", ")}');
    buf.writeln('  Schema: not shown — call this tool to receive its parameter schema on validation.');
    return buf.toString();
  }
}
