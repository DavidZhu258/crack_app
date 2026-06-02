/// App HTTP 客户端
library;

import 'package:dio/dio.dart';

/// 企业服务端默认地址。
class EnterpriseApiDefaults {
  /// 默认本地开发 API 地址。
  ///
  /// 生产包通过 `CRACK_API_BASE_URL` 指定真实服务端，避免开源代码绑定私有地址。
  static const baseUrl = String.fromEnvironment(
    'CRACK_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}

/// 创建带基础地址、超时和 token 注入能力的 Dio 客户端。
class ApiClient {
  /// 创建 API 客户端
  ApiClient({
    required String baseUrl,
    Future<String?> Function()? tokenProvider,
    Dio? dio,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 60),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ) {
    final provider = tokenProvider;
    if (provider != null) {
      this.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final token = await provider();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  /// Dio 实例
  final Dio dio;
}
