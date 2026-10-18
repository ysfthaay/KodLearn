import 'package:flutter/material.dart';

const _kAccent      = Color(0xFFAF4C00);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);

/// GitHub-style activity heatmap.
///
/// Reads a `dailyActivity` map of the form `{ 'YYYY-MM-DD': count }`
/// (typically straight from the user's Firestore doc) and renders the last
/// 52 weeks as a 7×N grid. Cells are colored by intensity bucket.
///
/// Cells render as a Wrap-free Stack of `Container`s laid out column-major
/// (week-then-day) so the leftmost column is 52 weeks ago and the rightmost
/// is the current week. Each cell carries a `Tooltip` with the exact date
/// and count.
class ActivityHeatmap extends StatelessWidget {
  /// Raw daily-activity map from Firestore. Keys are 'YYYY-MM-DD'.
  final Map<String, int> activity;

  /// Number of weeks to display (default 52 = roughly one year).
  final int weeks;

  /// Edge length of each cell in logical pixels.
  final double cellSize;

  /// Gap between cells.
  final double cellGap;

  const ActivityHeatmap({
    super.key,
    required this.activity,
    this.weeks = 52,
    this.cellSize = 11,
    this.cellGap = 3,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    // Anchor the heatmap so the rightmost column ends on the current week's
    // Sunday. Then walk backwards `weeks - 1` weeks to get the start.
    // 0=Mon..6=Sun.
    final todayDow = todayMidnight.weekday - 1;
    final daysToSunday = 6 - todayDow;
    final lastSunday = todayMidnight.add(Duration(days: daysToSunday));
    final firstMonday = lastSunday.subtract(Duration(days: weeks * 7 - 1));

    int totalContrib = 0;
    int maxCount = 1;
    for (final v in activity.values) {
      totalContrib += v;
      if (v > maxCount) maxCount = v;
    }

    // Months row — show a label above each column where the month changes.
    final monthLabels = _monthLabels(firstMonday, weeks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Aktivite',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
            const Spacer(),
            Text(
              'Son 12 ay · $totalContrib aktivite',
              style: const TextStyle(
                fontSize: 11,
                color: _kSubtitle,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Scrollable horizontally on narrow screens so the grid never
        // overflows its container.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month labels strip.
              SizedBox(
                height: 14,
                child: Row(
                  children: List.generate(weeks, (i) {
                    final label = monthLabels[i];
                    return SizedBox(
                      width: cellSize + cellGap,
                      child: label == null
                          ? const SizedBox.shrink()
                          : Text(
                              label,
                              style: const TextStyle(
                                fontSize: 9,
                                color: _kSubtitle,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 4),
              // The grid itself.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(weeks, (w) {
                  return Padding(
                    padding: EdgeInsets.only(right: cellGap),
                    child: Column(
                      children: List.generate(7, (d) {
                        final cellDate = firstMonday.add(Duration(days: w * 7 + d));
                        // Days past "today" should render as inactive
                        // background, not as a coloured cell with 0 count.
                        final isFuture = cellDate.isAfter(todayMidnight);
                        final key = _dateKey(cellDate);
                        final count = isFuture ? 0 : (activity[key] ?? 0);
                        return Padding(
                          padding: EdgeInsets.only(bottom: cellGap),
                          child: _Cell(
                            size: cellSize,
                            color: isFuture
                                ? Colors.transparent
                                : _intensityColor(count, maxCount),
                            tooltip:
                                '${_friendlyDate(cellDate)} • $count aktivite',
                            outline: isFuture
                                ? null
                                : Colors.black.withOpacity(0.04),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              // Legend.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Az',
                    style: TextStyle(fontSize: 10, color: _kSubtitle),
                  ),
                  const SizedBox(width: 6),
                  for (final v in const [0, 1, 3, 6, 10])
                    Padding(
                      padding: EdgeInsets.only(right: cellGap),
                      child: _Cell(
                        size: cellSize,
                        color: _intensityColor(v, 10),
                        outline: Colors.black.withOpacity(0.06),
                      ),
                    ),
                  const SizedBox(width: 2),
                  const Text(
                    'Çok',
                    style: TextStyle(fontSize: 10, color: _kSubtitle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── helpers ──

  String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _friendlyDate(DateTime d) {
    const months = [
      'Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Returns the month abbreviation for column `i` ONLY if it's the first
  /// column of that month (so labels don't repeat).
  List<String?> _monthLabels(DateTime firstMonday, int weeks) {
    const months = [
      'Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara',
    ];
    final out = List<String?>.filled(weeks, null);
    int? lastMonth;
    for (int w = 0; w < weeks; w++) {
      final colStart = firstMonday.add(Duration(days: w * 7));
      if (lastMonth != colStart.month) {
        out[w] = months[colStart.month - 1];
        lastMonth = colStart.month;
      }
    }
    return out;
  }

  Color _intensityColor(int count, int max) {
    if (count <= 0) return const Color(0xFFEEEEEE);
    // Five-step ramp with the brand accent as the high end.
    if (count <= 1) return _kAccent.withOpacity(0.20);
    if (count <= 3) return _kAccent.withOpacity(0.40);
    if (count <= 6) return _kAccent.withOpacity(0.65);
    if (count <= 10) return _kAccent.withOpacity(0.85);
    return _kAccent;
  }
}

class _Cell extends StatelessWidget {
  final double size;
  final Color color;
  final String? tooltip;
  final Color? outline;
  const _Cell({
    required this.size,
    required this.color,
    this.tooltip,
    this.outline,
  });

  @override
  Widget build(BuildContext context) {
    final w = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: outline == null ? null : Border.all(color: outline!, width: 0.5),
      ),
    );
    if (tooltip == null) return w;
    return Tooltip(
      message: tooltip!,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 200),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      child: w,
    );
  }
}
