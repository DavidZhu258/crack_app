import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/models.dart';
import 'package:flutter/material.dart';

/// Displays JCI recognition result images with single-image semantics.
///
/// New records reuse `image1Path/resultImage1` for legacy compatibility, so the
/// second image is only shown when an older record has a genuinely different
/// `image2Path`.
class JciResultImagesSection extends StatelessWidget {
  /// Creates a result image section for a JCI detection record.
  const JciResultImagesSection({
    required this.result,
    super.key,
  });

  /// Detection result whose annotated images should be displayed.
  final JciDetectionResult result;

  bool get _hasLegacySecondImage => result.image2Path != result.image1Path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '检测结果图像',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (!_hasLegacySecondImage) {
              return _ResultImageCard(
                label: '掌子面识别结果图',
                imageData: result.resultImage1,
              );
            }

            final first = _ResultImageCard(
              label: '掌子面识别结果图',
              imageData: result.resultImage1,
            );
            final second = _ResultImageCard(
              label: '历史兼容图像2',
              imageData: result.resultImage2,
            );
            if (constraints.maxWidth < 520) {
              return Column(
                children: [
                  first,
                  const SizedBox(height: 12),
                  second,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: second),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ResultImageCard extends StatelessWidget {
  const _ResultImageCard({
    required this.label,
    required this.imageData,
  });

  final String label;
  final Uint8List imageData;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: Image.memory(
              imageData,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}
