/// 网络可达性服务
///
/// `connectivity_plus` 只能说明网络类型，不能证明服务器可达，因此默认实现
/// 会继续调用健康检查接口。
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// 网络健康检查抽象，便于测试推理路由。
// ignore: one_member_abstracts
abstract interface class NetworkStatusService {
  /// 当前是否可以访问服务器。
  Future<bool> canReachServer();
}

/// 基于 connectivity_plus + /health 的网络可达性实现。
class ConnectivityNetworkStatusService implements NetworkStatusService {
  /// 创建网络服务
  ConnectivityNetworkStatusService({
    required this.healthUrl,
    Connectivity? connectivity,
    Dio? dio,
  }) : _connectivity = connectivity ?? Connectivity(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 3),
               receiveTimeout: const Duration(seconds: 3),
             ),
           );

  /// 健康检查地址
  final String healthUrl;

  final Connectivity _connectivity;
  final Dio _dio;

  @override
  Future<bool> canReachServer() async {
    final connectivityResults = await _connectivity.checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      return false;
    }

    try {
      final response = await _dio.get<Object?>(healthUrl);
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } on DioException {
      return false;
    } on Exception {
      return false;
    }
  }
}
