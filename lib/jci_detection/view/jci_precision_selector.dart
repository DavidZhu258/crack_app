import 'package:flutter/material.dart';

@immutable
class JciPrecisionOption {
  const JciPrecisionOption({
    required this.maxWindows,
    required this.name,
    required this.description,
    required this.icon,
  });

  final int maxWindows;
  final String name;
  final String description;
  final IconData icon;

  String get label => '$name $maxWindows 窗口';
}

const jciPrecisionOptions = <JciPrecisionOption>[
  JciPrecisionOption(
    maxWindows: 4,
    name: '快速',
    description: '低内存优先，适合快速测试和普通手机。',
    icon: Icons.speed,
  ),
  JciPrecisionOption(
    maxWindows: 8,
    name: '标准',
    description: '兼顾速度和覆盖度，适合一般现场复核。',
    icon: Icons.tune,
  ),
  JciPrecisionOption(
    maxWindows: 12,
    name: '精细',
    description: '提升分窗覆盖度，识别更慢、更占内存。',
    icon: Icons.grid_view,
  ),
  JciPrecisionOption(
    maxWindows: 20,
    name: '最高',
    description: '使用最高窗口数量，耗时最长且更占内存。',
    icon: Icons.memory,
  ),
];

JciPrecisionOption jciPrecisionOptionForWindows(int maxWindows) {
  for (final option in jciPrecisionOptions) {
    if (option.maxWindows == maxWindows) {
      return option;
    }
  }
  return jciPrecisionOptions.first;
}

class JciPrecisionSelector extends StatelessWidget {
  const JciPrecisionSelector({
    required this.selectedMaxWindows,
    required this.onChanged,
    super.key,
  });

  final int selectedMaxWindows;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedOption = jciPrecisionOptionForWindows(selectedMaxWindows);

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.center_focus_strong,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '识别精度',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                selected: {selectedOption.maxWindows},
                onSelectionChanged: onChanged == null
                    ? null
                    : (values) {
                        if (values.isNotEmpty) {
                          onChanged!(values.first);
                        }
                      },
                segments: [
                  for (final option in jciPrecisionOptions)
                    ButtonSegment<int>(
                      value: option.maxWindows,
                      icon: Icon(option.icon, size: 16),
                      label: Text(option.label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              selectedOption.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
