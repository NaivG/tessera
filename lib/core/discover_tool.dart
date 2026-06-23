import '../models/tool.dart';

/// `discover` meta-tool — LLM 用来发现可用 skills 和 tools 的统一入口。
///
/// 返回轻量摘要：name + description + tags + capabilities，
/// **故意不含 parameter schema**——避免 context 污染。
///
/// LLM 通过 `discover` 了解工具后直接发起调用；Runtime 在 `ToolCallValidator`
/// 中校验参数，失败时将完整 schema 通过错误响应返回给 LLM。
const discoverTool = ToolDefinition(
  name: 'discover',
  description: 'Discover available skills and tools by keyword, capability, or tag. '
      'Returns lightweight summaries only — parameter schemas are NOT included '
      'to avoid polluting the context. When you decide to call a tool, the runtime '
      'will validate your arguments against the tool\'s full schema; if validation '
      'fails, the schema will be returned to you for correction.',
  tags: {'meta', 'discovery'},
  capabilities: {'meta.discover'},
  parameters: {
    'query': {
      'type': 'string',
      'description': 'Free-text keyword matched against name/description/capability/tag.',
    },
    'capability': {
      'type': 'string',
      'description': 'Exact capability to match (e.g. "web.search", "audio.tts").',
    },
    'tag': {
      'type': 'string',
      'description': 'Tag to filter by (free-form label).',
    },
    'kind': {
      'type': 'string',
      'description': 'One of "skill", "tool", "all". Defaults to "all".',
    },
  },
);
