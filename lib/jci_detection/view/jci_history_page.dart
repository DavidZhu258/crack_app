/// JCI 历史记录页面
///
/// 实现历史记录列表 UI 和记录详情查看功能。
///
/// 需求:
/// - 8.4: 按时间倒序显示已保存的检测记录
/// - 8.5: 点击历史记录项显示完整的检测详情
library;

import 'package:crack_app/jci_detection/cubit/jci_history_cubit.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/view/jci_result_images_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

/// JCI 历史记录页面
///
/// 提供 BlocProvider 包装的历史记录视图。
class JciHistoryPage extends StatelessWidget {
  /// 创建 JCI 历史记录页面
  const JciHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = JciHistoryCubit();
        // 使用 Future.microtask 避免在 build 中直接调用异步方法
        // ignore: discarded_futures
        Future.microtask(cubit.loadHistory);
        return cubit;
      },
      child: const JciHistoryView(),
    );
  }
}

/// JCI 历史记录视图
///
/// 显示历史记录列表或选中记录的详情。
///
/// 需求:
/// - 8.4: 按时间倒序显示已保存的检测记录
/// - 8.5: 点击历史记录项显示完整的检测详情
class JciHistoryView extends StatelessWidget {
  /// 创建 JCI 历史记录视图
  const JciHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JciHistoryCubit, JciHistoryState>(
      builder: (context, state) {
        return Scaffold(
          appBar: _buildAppBar(context, state),
          body: _buildBody(context, state),
        );
      },
    );
  }

  /// 构建应用栏
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    JciHistoryState state,
  ) {
    // 如果有选中的记录，显示返回按钮
    if (state is JciHistoryLoaded && state.hasSelectedResult) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.read<JciHistoryCubit>().clearSelection(),
          tooltip: '返回列表',
        ),
        title: const Text('检测详情'),
      );
    }

    return AppBar(
      title: const Text('历史记录'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<JciHistoryCubit>().loadHistory(),
          tooltip: '刷新',
        ),
      ],
    );
  }

  /// 构建页面主体
  Widget _buildBody(BuildContext context, JciHistoryState state) {
    return switch (state) {
      JciHistoryInitial() => const Center(
        child: Text('正在初始化...'),
      ),
      JciHistoryLoading() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载历史记录中...'),
          ],
        ),
      ),
      JciHistoryError(:final message) => _buildErrorView(context, message),
      JciHistoryLoaded(:final results, :final selectedResult) =>
        selectedResult != null
            ? _JciHistoryDetailView(result: selectedResult)
            : _JciHistoryListView(results: results),
    };
  }

  /// 构建错误视图
  Widget _buildErrorView(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.read<JciHistoryCubit>().loadHistory(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 历史记录列表视图
///
/// 显示所有历史记录，支持滑动删除。
///
/// 需求: 8.4 - 按时间倒序显示已保存的检测记录
class _JciHistoryListView extends StatelessWidget {
  const _JciHistoryListView({required this.results});

  final List<JciDetectionResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _buildEmptyView();
    }

    return RefreshIndicator(
      onRefresh: () => context.read<JciHistoryCubit>().refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          return _JciHistoryListItem(
            result: result,
            onTap: () => context.read<JciHistoryCubit>().selectRecord(result),
            onDelete: () => _confirmDelete(context, result),
          );
        },
      ),
    );
  }

  /// 构建空列表视图
  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            '暂无历史记录',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '完成 JCI 检测后，结果将保存在这里',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// 确认删除对话框
  Future<void> _confirmDelete(
    BuildContext context,
    JciDetectionResult result,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条检测记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      await context.read<JciHistoryCubit>().deleteRecord(result.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('记录已删除'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
}

/// 历史记录列表项
///
/// 显示单条记录的摘要信息，支持滑动删除。
class _JciHistoryListItem extends StatelessWidget {
  const _JciHistoryListItem({
    required this.result,
    required this.onTap,
    required this.onDelete,
  });

  final JciDetectionResult result;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final gradeColor = _getGradeColor(result.classification.finalGrade);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Dismissible(
      key: Key(result.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // 由 onDelete 处理实际删除
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 28,
        ),
      ),
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 时间和位置
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateFormat.format(result.timestamp),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 20,
                      color: Colors.grey,
                      onPressed: onDelete,
                      tooltip: '删除',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                if (result.engineeringInfo.location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          result.engineeringInfo.location,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      icon: Icons.sync,
                      label: result.syncStatus.displayName,
                      color: _syncStatusColor(result.syncStatus),
                    ),
                    _StatusChip(
                      icon: Icons.memory,
                      label: _inferenceModeLabel(result.inferenceMode),
                      color: Colors.blueGrey,
                    ),
                    if (result.syncError != null &&
                        result.syncError!.isNotEmpty)
                      const _StatusChip(
                        icon: Icons.error_outline,
                        label: '可重试',
                        color: Colors.red,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // JCI 值和围岩等级
                Row(
                  children: [
                    // JCI 值
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'JCI 值',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result.jciResult.jciValue.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 围岩等级
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: gradeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: gradeColor),
                      ),
                      child: Column(
                        children: [
                          Text(
                            result.classification.finalGrade.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: gradeColor,
                            ),
                          ),
                          Text(
                            result.classification.finalGrade.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: gradeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 渗水降级标记
                if (result.classification.wasDowngraded) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_drop,
                          size: 14,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '因渗水降级',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // 岩石类型
                Row(
                  children: [
                    const Icon(
                      Icons.terrain,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      result.engineeringInfo.rockType.displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.height,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '埋深 ${result.engineeringInfo.depth.toStringAsFixed(1)}m',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 根据围岩等级获取颜色
  Color _getGradeColor(RockGrade grade) {
    switch (grade) {
      case RockGrade.i1:
      case RockGrade.i2:
        return Colors.green;
      case RockGrade.ii1:
      case RockGrade.ii2:
        return Colors.orange;
      case RockGrade.iii:
        return Colors.deepOrange;
      case RockGrade.iv:
      case RockGrade.v:
        return Colors.red;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

String _inferenceModeLabel(String mode) {
  switch (mode) {
    case 'online':
      return '服务器推理';
    case 'autoFallbackOffline':
    case 'onlineFailedOfflineFallback':
      return '转离线';
    case 'auto':
      return '自动模式';
    default:
      return '手机端推理';
  }
}

Color _syncStatusColor(SyncStatus status) {
  switch (status) {
    case SyncStatus.localOnly:
      return Colors.blueGrey;
    case SyncStatus.pendingUpload:
    case SyncStatus.uploading:
      return Colors.orange;
    case SyncStatus.uploaded:
      return Colors.green;
    case SyncStatus.uploadFailed:
      return Colors.red;
  }
}

/// 历史记录详情视图
///
/// 显示选中记录的完整检测详情。
///
/// 需求: 8.5 - 点击历史记录项显示完整的检测详情
class _JciHistoryDetailView extends StatelessWidget {
  const _JciHistoryDetailView({required this.result});

  final JciDetectionResult result;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 检测时间和地点
          _buildHeaderSection(),
          const SizedBox(height: 24),

          // 检测结果图像
          JciResultImagesSection(result: result),
          const SizedBox(height: 24),

          // JCI 值和计算明细
          _buildJciSection(),
          const SizedBox(height: 24),

          // 围岩等级
          _buildRockGradeSection(),
          const SizedBox(height: 24),

          // 支护方案建议
          _buildSupportPlanSection(),
          const SizedBox(height: 24),

          // 人工复核
          _buildManualReviewSection(),
          const SizedBox(height: 24),

          // 提取的参数
          _buildExtractedParamsSection(),
          const SizedBox(height: 24),

          // 工程信息
          _buildEngineeringInfoSection(),
        ],
      ),
    );
  }

  /// 构建头部信息区域
  Widget _buildHeaderSection() {
    final dateFormat = DateFormat('yyyy年MM月dd日 HH:mm:ss');

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  dateFormat.format(result.timestamp),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (result.engineeringInfo.location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.engineeringInfo.location,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
            if (result.engineeringInfo.inspector.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '检测人员: ${result.engineeringInfo.inspector}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  icon: Icons.sync,
                  label: result.syncStatus.displayName,
                  color: _syncStatusColor(result.syncStatus),
                ),
                _StatusChip(
                  icon: Icons.memory,
                  label: _inferenceModeLabel(result.inferenceMode),
                  color: Colors.blueGrey,
                ),
                if (result.remoteRecordId != null &&
                    result.remoteRecordId!.isNotEmpty)
                  _StatusChip(
                    icon: Icons.cloud_done,
                    label: result.remoteRecordId!,
                    color: Colors.green,
                  ),
              ],
            ),
            if (result.syncError != null && result.syncError!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '同步错误: ${result.syncError}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建 JCI 值和计算明细区域
  Widget _buildJciSection() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calculate, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'JCI 计算结果',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // JCI 值显示
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  children: [
                    const Text(
                      'JCI 值',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.jciResult.jciValue.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // 计算明细
            const Text(
              '计算明细',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            ...result.jciResult.componentScores.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      entry.value.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建围岩等级区域
  Widget _buildRockGradeSection() {
    final classification = result.classification;
    final effectiveGrade = result.effectiveGrade;
    final gradeColor = _getGradeColor(effectiveGrade);
    final gradeIcon = _getGradeIcon(effectiveGrade);
    final manualOverride = result.manualReview?.hasOverride ?? false;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.terrain, color: Colors.brown),
                SizedBox(width: 8),
                Text(
                  '围岩等级',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 最终等级显示
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: gradeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: gradeColor, width: 2),
                ),
                child: Column(
                  children: [
                    Icon(
                      gradeIcon,
                      size: 48,
                      color: gradeColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      effectiveGrade.name,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: gradeColor,
                      ),
                    ),
                    Text(
                      effectiveGrade.description,
                      style: TextStyle(
                        fontSize: 16,
                        color: gradeColor,
                      ),
                    ),
                    if (manualOverride) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '人工复核采用等级',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 渗水降级说明
            if (classification.wasDowngraded) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.water_drop, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '因渗水降级',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildGradeBadge(
                          classification.originalGrade,
                          label: '原等级',
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(
                            Icons.arrow_forward,
                            color: Colors.orange,
                          ),
                        ),
                        _buildGradeBadge(
                          classification.finalGrade,
                          label: '调整后',
                        ),
                      ],
                    ),
                    if (classification.downgradeReason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        classification.downgradeReason!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建等级徽章
  Widget _buildGradeBadge(RockGrade grade, {required String label}) {
    final color = _getGradeColor(grade);
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(
            grade.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建支护方案区域
  Widget _buildSupportPlanSection() {
    final supportPlan = result.effectiveSupportPlan;
    final manualOverride = result.manualReview?.hasOverride ?? false;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.construction, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '支护方案建议',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (manualOverride) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.rate_review, color: Colors.indigo, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前显示人工复核选择的支护方案',
                        style: TextStyle(color: Colors.indigo, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 方案摘要
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      supportPlan.summary,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 预留方案提示
            if (supportPlan.isPlaceholder) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '暂无具体方案，请咨询专业人员',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 支护方法列表
            if (supportPlan.methods.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '支护工艺',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              ...supportPlan.methods.map(_buildSupportMethodCard),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建人工复核区域
  Widget _buildManualReviewSection() {
    final review = result.manualReview;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.rate_review, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  '人工复核',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (review == null)
              const Text('未复核')
            else ...[
              _buildParamRow(
                '复核结论',
                review.acceptedRecognitionResult ? '接受识别结果' : '人工调整',
              ),
              if (review.hasOverride) ...[
                _buildParamRow('人工判断级别', review.manualGrade?.name ?? ''),
                _buildParamRow(
                  '人工支护方案',
                  review.selectedSupportPlan?.grade.fullName ?? '',
                ),
              ],
              if (review.reviewerName.isNotEmpty)
                _buildParamRow('复核人员', review.reviewerName),
              if (review.note.isNotEmpty) _buildParamRow('复核说明', review.note),
              _buildParamRow(
                '复核时间',
                review.reviewedAt.toLocal().toString().split('.').first,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建支护方法卡片
  Widget _buildSupportMethodCard(SupportMethod method) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                method.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (method.parameters.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: method.parameters.entries.map((param) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${param.key}: ${param.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建提取参数区域
  Widget _buildExtractedParamsSection() {
    final params = result.extractedParams;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  '提取参数',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildParamRow('RQD 值', '${params.rqd.toStringAsFixed(1)}%'),
            _buildParamRow(
              '节理间距',
              '${params.jointSpacing.toStringAsFixed(2)} 米',
            ),
            _buildParamRow(
              '节理面密度',
              '${params.jointDensity.toStringAsFixed(2)} 条/m²',
            ),
          ],
        ),
      ),
    );
  }

  /// 构建工程信息区域
  Widget _buildEngineeringInfoSection() {
    final info = result.engineeringInfo;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.engineering, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  '工程信息',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildParamRow('岩性', info.rockType.displayName),
            _buildParamRow('工程地点', info.projectLocation),
            _buildParamRow('工程名称', info.projectName),
            _buildParamRow('施工人员', info.workerName),
            _buildParamRow(
              '工程所在中段标高',
              '${info.elevation.toStringAsFixed(1)} m',
            ),
            _buildParamRow('掌子面渗水', info.hasSeepage ? '是' : '否'),
          ],
        ),
      ),
    );
  }

  /// 构建参数行
  Widget _buildParamRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 根据围岩等级获取颜色
  Color _getGradeColor(RockGrade grade) {
    switch (grade) {
      case RockGrade.i1:
      case RockGrade.i2:
        return Colors.green;
      case RockGrade.ii1:
      case RockGrade.ii2:
        return Colors.orange;
      case RockGrade.iii:
        return Colors.deepOrange;
      case RockGrade.iv:
      case RockGrade.v:
        return Colors.red;
    }
  }

  /// 根据围岩等级获取图标
  IconData _getGradeIcon(RockGrade grade) {
    switch (grade) {
      case RockGrade.i1:
      case RockGrade.i2:
        return Icons.check_circle;
      case RockGrade.ii1:
      case RockGrade.ii2:
        return Icons.info;
      case RockGrade.iii:
        return Icons.warning;
      case RockGrade.iv:
      case RockGrade.v:
        return Icons.dangerous;
    }
  }
}
