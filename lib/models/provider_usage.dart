/// 单个 provider 的累计用量统计
class ProviderUsage {
  final String providerId;
  final String providerName;
  final int totalPromptTokens;
  final int totalCompletionTokens;
  final int totalRequests;
  final int cacheHitCount;
  final int cacheMissCount;

  const ProviderUsage({
    required this.providerId,
    required this.providerName,
    this.totalPromptTokens = 0,
    this.totalCompletionTokens = 0,
    this.totalRequests = 0,
    this.cacheHitCount = 0,
    this.cacheMissCount = 0,
  });

  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  int get totalCacheOps => cacheHitCount + cacheMissCount;

  double get cacheHitRate =>
      totalCacheOps > 0 ? cacheHitCount / totalCacheOps : 0.0;

  ProviderUsage copyWith({
    String? providerId,
    String? providerName,
    int? totalPromptTokens,
    int? totalCompletionTokens,
    int? totalRequests,
    int? cacheHitCount,
    int? cacheMissCount,
  }) {
    return ProviderUsage(
      providerId: providerId ?? this.providerId,
      providerName: providerName ?? this.providerName,
      totalPromptTokens: totalPromptTokens ?? this.totalPromptTokens,
      totalCompletionTokens:
          totalCompletionTokens ?? this.totalCompletionTokens,
      totalRequests: totalRequests ?? this.totalRequests,
      cacheHitCount: cacheHitCount ?? this.cacheHitCount,
      cacheMissCount: cacheMissCount ?? this.cacheMissCount,
    );
  }

  factory ProviderUsage.fromJson(Map<String, dynamic> json) {
    return ProviderUsage(
      providerId: json['provider_id'] as String,
      providerName: json['provider_name'] as String? ?? '',
      totalPromptTokens: json['total_prompt_tokens'] as int? ?? 0,
      totalCompletionTokens: json['total_completion_tokens'] as int? ?? 0,
      totalRequests: json['total_requests'] as int? ?? 0,
      cacheHitCount: json['cache_hit_count'] as int? ?? 0,
      cacheMissCount: json['cache_miss_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_id': providerId,
      'provider_name': providerName,
      'total_prompt_tokens': totalPromptTokens,
      'total_completion_tokens': totalCompletionTokens,
      'total_requests': totalRequests,
      'cache_hit_count': cacheHitCount,
      'cache_miss_count': cacheMissCount,
    };
  }
}
