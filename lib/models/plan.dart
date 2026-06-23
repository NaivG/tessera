/// 计划步骤状态
enum PlanStepStatus {
  pending,
  inProgress,
  completed,
  failed;

  static PlanStepStatus fromName(String name) {
    return PlanStepStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => PlanStepStatus.pending,
    );
  }
}

/// 单个计划步骤
class PlanStep {
  final String title;
  final String description;
  PlanStepStatus status;

  PlanStep({
    required this.title,
    this.description = '',
    this.status = PlanStepStatus.pending,
  });

  PlanStep copyWith({
    String? title,
    String? description,
    PlanStepStatus? status,
  }) {
    return PlanStep(
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
    );
  }

  factory PlanStep.fromJson(Map<String, dynamic> json) {
    return PlanStep(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] != null
          ? PlanStepStatus.fromName(json['status'] as String)
          : PlanStepStatus.pending,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'status': status.name,
    };
  }
}

/// 执行计划
class Plan {
  final List<PlanStep> steps;

  Plan({required this.steps});

  factory Plan.fromJson(Map<String, dynamic> json) {
    final stepsList = json['steps'] as List<dynamic>? ?? [];
    return Plan(
      steps: stepsList
          .map((e) => PlanStep.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'steps': steps.map((s) => s.toJson()).toList(),
    };
  }
}
