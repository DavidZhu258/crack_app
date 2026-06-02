/// JCI 历史记录 Cubit
///
/// 管理 JCI 检测历史记录的状态，包括加载、删除和选择记录功能。
///
/// 需求:
/// - 8.4: 按时间倒序显示已保存的检测记录
/// - 8.5: 点击历史记录项显示完整的检测详情
library;

import 'package:bloc/bloc.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';
import 'package:equatable/equatable.dart';

// ============ 状态定义 ============

/// JCI 历史记录状态基类
///
/// 使用 sealed class 确保所有状态类型在编译时已知，
/// 支持穷尽式模式匹配。
sealed class JciHistoryState extends Equatable {
  const JciHistoryState();
}

/// 初始状态
///
/// 历史记录页面刚加载时的状态。
/// 此时尚未加载任何数据。
class JciHistoryInitial extends JciHistoryState {
  const JciHistoryInitial();

  @override
  List<Object?> get props => [];
}

/// 加载中状态
///
/// 正在从本地存储加载历史记录时的状态。
class JciHistoryLoading extends JciHistoryState {
  const JciHistoryLoading();

  @override
  List<Object?> get props => [];
}

/// 加载成功状态
///
/// 历史记录加载成功时的状态。
/// 包含按时间倒序排列的检测记录列表。
///
/// 需求:
/// - 8.4: 按时间倒序显示已保存的检测记录
/// - 8.5: 点击历史记录项显示完整的检测详情
class JciHistoryLoaded extends JciHistoryState {
  const JciHistoryLoaded({
    required this.results,
    this.selectedResult,
  });

  /// 历史记录列表（按时间倒序排列）
  final List<JciDetectionResult> results;

  /// 当前选中的记录（用于显示详情）
  final JciDetectionResult? selectedResult;

  /// 检查是否有历史记录
  bool get hasResults => results.isNotEmpty;

  /// 历史记录数量
  int get resultCount => results.length;

  /// 检查是否有选中的记录
  bool get hasSelectedResult => selectedResult != null;

  @override
  List<Object?> get props => [results, selectedResult];

  /// 创建副本并更新指定字段
  JciHistoryLoaded copyWith({
    List<JciDetectionResult>? results,
    JciDetectionResult? selectedResult,
    bool clearSelectedResult = false,
  }) {
    return JciHistoryLoaded(
      results: results ?? this.results,
      selectedResult: clearSelectedResult
          ? null
          : (selectedResult ?? this.selectedResult),
    );
  }
}

/// 加载错误状态
///
/// 加载历史记录失败时的状态。
/// 包含错误信息用于显示给用户。
class JciHistoryError extends JciHistoryState {
  const JciHistoryError({
    required this.message,
  });

  /// 错误信息
  final String message;

  @override
  List<Object?> get props => [message];
}

// ============ Cubit 定义 ============

/// JCI 历史记录 Cubit
///
/// 管理历史记录的加载、删除和选择操作。
/// 使用 JciStorageService 进行数据持久化操作。
///
/// 状态流转:
/// Initial -> Loading -> Loaded/Error
///
/// 需求:
/// - 8.4: 按时间倒序显示已保存的检测记录
/// - 8.5: 点击历史记录项显示完整的检测详情
class JciHistoryCubit extends Cubit<JciHistoryState> {
  /// 创建 JCI 历史记录 Cubit 实例
  ///
  /// [jciStorageService] 本地存储服务（可选，用于测试注入）
  JciHistoryCubit({
    JciStorageService? jciStorageService,
  }) : _jciStorageService = jciStorageService ?? JciStorageService(),
       super(const JciHistoryInitial());

  final JciStorageService _jciStorageService;

  /// 加载历史记录
  ///
  /// 从本地存储加载所有检测记录，按时间倒序排列。
  ///
  /// 需求: 8.4 - 按时间倒序显示已保存的检测记录
  Future<void> loadHistory() async {
    emit(const JciHistoryLoading());

    try {
      final results = await _jciStorageService.getAllResults();
      emit(JciHistoryLoaded(results: results));
    } on Exception catch (e) {
      emit(JciHistoryError(message: '加载历史记录失败: $e'));
    }
  }

  /// 删除记录
  ///
  /// 从本地存储删除指定的检测记录，并更新状态。
  ///
  /// [id] 要删除的记录的唯一标识符
  Future<void> deleteRecord(String id) async {
    final currentState = state;

    if (currentState is! JciHistoryLoaded) {
      return;
    }

    try {
      await _jciStorageService.deleteResult(id);

      // 从列表中移除已删除的记录
      final updatedResults = currentState.results
          .where((result) => result.id != id)
          .toList();

      // 如果删除的是当前选中的记录，清除选中状态
      final selectedResult = currentState.selectedResult;
      final shouldClearSelection =
          selectedResult != null && selectedResult.id == id;

      emit(
        JciHistoryLoaded(
          results: updatedResults,
          selectedResult: shouldClearSelection ? null : selectedResult,
        ),
      );
    } on Exception catch (e) {
      emit(JciHistoryError(message: '删除记录失败: $e'));
    }
  }

  /// 选择记录
  ///
  /// 选择指定的检测记录以显示详情。
  ///
  /// [result] 要选择的检测记录
  ///
  /// 需求: 8.5 - 点击历史记录项显示完整的检测详情
  void selectRecord(JciDetectionResult result) {
    final currentState = state;

    if (currentState is! JciHistoryLoaded) {
      return;
    }

    emit(currentState.copyWith(selectedResult: result));
  }

  /// 通过 ID 选择记录
  ///
  /// 根据 ID 从已加载的列表中查找并选择记录。
  ///
  /// [id] 要选择的记录的唯一标识符
  ///
  /// 需求: 8.5 - 点击历史记录项显示完整的检测详情
  void selectRecordById(String id) {
    final currentState = state;

    if (currentState is! JciHistoryLoaded) {
      return;
    }

    final result = currentState.results.where((r) => r.id == id).firstOrNull;

    if (result != null) {
      emit(currentState.copyWith(selectedResult: result));
    }
  }

  /// 清除选中状态
  ///
  /// 取消当前选中的记录，返回列表视图。
  void clearSelection() {
    final currentState = state;

    if (currentState is! JciHistoryLoaded) {
      return;
    }

    emit(currentState.copyWith(clearSelectedResult: true));
  }

  /// 刷新历史记录
  ///
  /// 重新加载历史记录，保持当前选中状态（如果记录仍存在）。
  Future<void> refresh() async {
    final currentState = state;
    String? selectedId;

    if (currentState is JciHistoryLoaded) {
      selectedId = currentState.selectedResult?.id;
    }

    emit(const JciHistoryLoading());

    try {
      final results = await _jciStorageService.getAllResults();

      // 尝试恢复之前选中的记录
      JciDetectionResult? selectedResult;
      if (selectedId != null) {
        selectedResult = results.where((r) => r.id == selectedId).firstOrNull;
      }

      emit(JciHistoryLoaded(results: results, selectedResult: selectedResult));
    } on Exception catch (e) {
      emit(JciHistoryError(message: '刷新历史记录失败: $e'));
    }
  }
}
