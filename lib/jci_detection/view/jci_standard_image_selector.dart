import 'dart:async';

import 'package:crack_app/jci_detection/models/standard_image_option.dart';
import 'package:flutter/material.dart';

/// JCI 标准样图选择器。
class JciStandardImageSelector extends StatelessWidget {
  /// 创建标准样图选择器。
  const JciStandardImageSelector({
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  /// 选择样图时回调。
  final ValueChanged<JciStandardImageOption> onSelected;

  /// 是否可操作。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? () => _showOptions(context) : null,
        icon: const Icon(Icons.image_search, size: 18),
        label: const Text('选择标准样图'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.teal,
          side: const BorderSide(color: Colors.teal),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '选择标准掌子面图像',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final option in jciStandardImageOptions)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.image_outlined),
                          title: Text(option.label),
                          subtitle: Text(option.description),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onSelected(option);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
