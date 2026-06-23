import '../models/message.dart';
import '../models/tool.dart';

/// spawn_sub_agent 工具定义
const spawnSubAgentTool = ToolDefinition(
  name: 'spawn_sub_agent',
  description:
      'Spawn a sub-agent to handle a specific subtask independently. '
      'The sub-agent will execute with its own context and return the result to you. '
      'Use this when a task can be broken down into independent subtasks.',
  parameters: {
    'task': {
      'type': 'string',
      'description': 'Clear description of the task for the sub-agent',
      'required': true,
    },
    'context': {
      'type': 'string',
      'description':
          'Additional context or data the sub-agent needs to complete the task',
    },
  },
);

/// 从 ToolCall 中提取 SubAgentTask 参数
SubAgentTaskArgs parseSubAgentArgs(ToolCall call) {
  final task = call.arguments['task'] as String? ?? '';
  final context = call.arguments['context'] as String?;
  return SubAgentTaskArgs(task: task, context: context);
}

class SubAgentTaskArgs {
  final String task;
  final String? context;
  const SubAgentTaskArgs({required this.task, this.context});
}
