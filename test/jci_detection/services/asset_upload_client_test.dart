import 'package:crack_app/jci_detection/services/asset_upload_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requestUploadTargets calls v1 presign endpoint', () async {
    final captured = <String, Object?>{};
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured['path'] = options.path;
          captured['data'] = options.data;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'success': true,
                'data': {
                  'uploads': [
                    {
                      'kind': 'originalImage',
                      'bucket': 'crack-record-assets',
                      'objectKey': 'records/r1/originalImage/face.jpg',
                      'uploadUrl': 'http://minio/upload',
                      'downloadUrl': 'http://minio/download',
                      'headers': {'Content-Type': 'image/jpeg'},
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final client = DioAssetUploadClient(dio: dio);

    final uploads = await client.requestUploadTargets(
      recordId: 'r1',
      assets: const [
        AssetUploadIntent(
          kind: 'originalImage',
          fileName: 'face.jpg',
          contentType: 'image/jpeg',
          sha256: 'abc123',
          sizeBytes: 4,
        ),
      ],
    );

    expect(captured['path'], '/api/v1/uploads/presign');
    expect(uploads.single.objectKey, 'records/r1/originalImage/face.jpg');
    expect(uploads.single.headers['Content-Type'], 'image/jpeg');
  });
}
