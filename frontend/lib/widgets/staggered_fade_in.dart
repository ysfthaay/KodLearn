import 'dart:async';

import 'package:flutter/material.dart';

/// Apple-style staggered entrance.
///
/// The widget's frame is laid out immediately (no layout shift), but each
/// child fades from `opacity 0 → 1` and slides up by `slideOffset` pixels in
/// sequence. The first child starts after [startDelay]; each subsequent
/// child waits an additional [interval]; every child takes [itemDuration]
/// to finish animating.
///
/// Children appear in a [Column] by default. Use [direction] to switch to a
/// [Row] if needed.
///
/// Typical use:
///
/// ```dart
/// StaggeredFadeIn(
///   interval: const Duration(milliseconds: 70),
///   itemDuration: const Duration(milliseconds: 480),
///   slideOffset: 14,
///   children: [
///     Text('Title'),
///     Text('Subtitle'),
///     SubmitButton(),
///   ],
/// )
/// ```
class StaggeredFadeIn extends StatefulWidget {
  final List<Widget> children;

  /// Delay before the first child starts animating.
  final Duration startDelay;

  /// Delay added between each subsequent child's start.
  final Duration interval;

  /// How long each individual child's fade + slide takes.
  final Duration itemDuration;

  /// Pixels the child slides upward from. 12-16 looks "Apple-ish".
  final double slideOffset;

  /// Curve applied to the per-item animation.
  final Curve curve;

  /// Lay children out as a Column or Row.
  final Axis direction;

  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;

  /// If the widget rebuilds with a new [animationKey], the animation
  /// restarts. Pass something like `ValueKey(isRegister)` if you want a
  /// re-stagger when the page contents swap meaningfully.
  final Key? animationKey;

  const StaggeredFadeIn({
    super.key,
    required this.children,
    this.startDelay = const Duration(milliseconds: 80),
    this.interval = const Duration(milliseconds: 70),
    this.itemDuration = const Duration(milliseconds: 480),
    this.slideOffset = 14,
    this.curve = Curves.easeOutCubic,
    this.direction = Axis.vertical,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.min,
    this.animationKey,
  });

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  Duration _totalDuration() {
    final n = widget.children.length;
    if (n == 0) return widget.itemDuration;
    final lastStart = widget.startDelay + widget.interval * (n - 1);
    return lastStart + widget.itemDuration;
  }

  void _buildAnimations() {
    final total = _totalDuration().inMilliseconds.toDouble();
    _animations = List.generate(widget.children.length, (i) {
      final startMs =
          (widget.startDelay.inMilliseconds + widget.interval.inMilliseconds * i)
              .toDouble();
      final endMs = startMs + widget.itemDuration.inMilliseconds;
      final start = (startMs / total).clamp(0.0, 1.0);
      final end = (endMs / total).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: widget.curve),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration());
    _buildAnimations();
    // Schedule the forward on the next frame so the parent's layout has
    // already happened — guarantees no layout shift.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.forward();
    });
  }

  @override
  void didUpdateWidget(covariant StaggeredFadeIn old) {
    super.didUpdateWidget(old);
    final structureChanged = old.children.length != widget.children.length ||
        old.startDelay != widget.startDelay ||
        old.interval != widget.interval ||
        old.itemDuration != widget.itemDuration;

    if (structureChanged) {
      _controller.duration = _totalDuration();
      _buildAnimations();
    }

    if (old.animationKey != widget.animationKey && widget.animationKey != null) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final items = List<Widget>.generate(widget.children.length, (i) {
          final t = _animations[i].value;
          // (1 - t) gives the initial offset, then eases to 0.
          final dy = (1 - t) * widget.slideOffset;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: widget.direction == Axis.vertical
                  ? Offset(0, dy)
                  : Offset(dy, 0),
              child: widget.children[i],
            ),
          );
        });

        if (widget.direction == Axis.vertical) {
          return Column(
            mainAxisAlignment: widget.mainAxisAlignment,
            crossAxisAlignment: widget.crossAxisAlignment,
            mainAxisSize: widget.mainAxisSize,
            children: items,
          );
        } else {
          return Row(
            mainAxisAlignment: widget.mainAxisAlignment,
            crossAxisAlignment: widget.crossAxisAlignment,
            mainAxisSize: widget.mainAxisSize,
            children: items,
          );
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StaggeredGroup + StaggeredChild
//
// Use this when you can't replace your Column / Row with [StaggeredFadeIn] —
// for example because you have `Expanded`, `Spacer`, or `Flexible` children
// that must remain *direct* children of the Flex parent.
//
// The group is an InheritedWidget that publishes timing config. Each
// [StaggeredChild] looks it up via `dependOnInheritedWidgetOfExactType`,
// schedules its own start by `startDelay + index * interval`, and animates
// its own opacity + slide. Because the animation wrapping happens *inside*
// the StaggeredChild, the StaggeredChild itself is free to live anywhere —
// `StaggeredChild(index: 2, child: Foo())` works as a direct child of a
// Column, *or* wrapped in `Expanded(child: StaggeredChild(...))`.
//
// Example:
//
// ```dart
// StaggeredGroup(
//   replayKey: ValueKey(_isRegister),
//   interval: const Duration(milliseconds: 80),
//   child: Column(
//     children: [
//       StaggeredChild(index: 0, child: Header()),
//       const Spacer(),
//       StaggeredChild(index: 1, child: Body()),
//       Expanded(child: StaggeredChild(index: 2, child: Scroller())),
//     ],
//   ),
// )
// ```
// ─────────────────────────────────────────────────────────────────────────────
class StaggeredGroup extends StatelessWidget {
  final Widget child;

  /// Delay before the first child starts animating.
  final Duration startDelay;

  /// Delay added between each index step.
  final Duration interval;

  /// How long each individual child's fade + slide takes.
  final Duration itemDuration;

  /// Pixels the child slides upward from. 12-16 looks "Apple-ish".
  final double slideOffset;

  /// Curve applied to the per-item animation.
  final Curve curve;

  /// If this value changes, every descendant [StaggeredChild] replays its
  /// animation from the beginning. Use e.g. `ValueKey(someToggle)` to
  /// re-stagger when the contents semantically change.
  final Object? replayKey;

  const StaggeredGroup({
    super.key,
    required this.child,
    this.startDelay = const Duration(milliseconds: 180),
    this.interval = const Duration(milliseconds: 70),
    this.itemDuration = const Duration(milliseconds: 480),
    this.slideOffset = 14,
    this.curve = Curves.easeOutCubic,
    this.replayKey,
  });

  @override
  Widget build(BuildContext context) {
    return _StaggeredScope(
      startDelay: startDelay,
      interval: interval,
      itemDuration: itemDuration,
      slideOffset: slideOffset,
      curve: curve,
      replayKey: replayKey,
      child: child,
    );
  }
}

class _StaggeredScope extends InheritedWidget {
  final Duration startDelay;
  final Duration interval;
  final Duration itemDuration;
  final double slideOffset;
  final Curve curve;
  final Object? replayKey;

  const _StaggeredScope({
    required this.startDelay,
    required this.interval,
    required this.itemDuration,
    required this.slideOffset,
    required this.curve,
    required this.replayKey,
    required super.child,
  });

  static _StaggeredScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_StaggeredScope>();
  }

  @override
  bool updateShouldNotify(_StaggeredScope old) {
    return old.startDelay != startDelay ||
        old.interval != interval ||
        old.itemDuration != itemDuration ||
        old.slideOffset != slideOffset ||
        old.curve != curve ||
        old.replayKey != replayKey;
  }
}

class StaggeredChild extends StatefulWidget {
  /// Position in the stagger sequence. The child starts animating at
  /// `group.startDelay + index * group.interval`.
  final int index;

  final Widget child;

  /// If the surrounding group has no key, [StaggeredChild] still plays once
  /// when first mounted. Set this to disable that initial play (e.g. you're
  /// embedding it in a list that hasn't finished laying out yet).
  final bool playOnMount;

  const StaggeredChild({
    super.key,
    required this.index,
    required this.child,
    this.playOnMount = true,
  });

  @override
  State<StaggeredChild> createState() => _StaggeredChildState();
}

class _StaggeredChildState extends State<StaggeredChild>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Object? _lastReplayKey;
  bool _hasScheduled = false;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _StaggeredScope.maybeOf(context);
    if (scope == null) {
      // No group around us — fall back to "already visible".
      _controller.value = 1.0;
      return;
    }
    _controller.duration = scope.itemDuration;

    final key = scope.replayKey;
    final firstTime = !_hasScheduled;
    final replayRequested = !firstTime && key != null && key != _lastReplayKey;

    if (firstTime && widget.playOnMount) {
      _scheduleStart(scope);
      _hasScheduled = true;
      _lastReplayKey = key;
    } else if (replayRequested) {
      _controller.reset();
      _scheduleStart(scope);
      _lastReplayKey = key;
    } else if (firstTime && !widget.playOnMount) {
      _controller.value = 1.0;
      _hasScheduled = true;
      _lastReplayKey = key;
    }
  }

  void _scheduleStart(_StaggeredScope scope) {
    _startTimer?.cancel();
    final delay = scope.startDelay + scope.interval * widget.index;
    _startTimer = Timer(delay, () {
      if (!mounted) return;
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _StaggeredScope.maybeOf(context);
    final curve = scope?.curve ?? Curves.easeOutCubic;
    final slideOffset = scope?.slideOffset ?? 14;

    return AnimatedBuilder(
      animation: _controller,
      // Pass the user's widget through `child:` so it's *not* rebuilt every
      // tick — only the Opacity / Transform layer rebuilds.
      child: widget.child,
      builder: (context, child) {
        final t = curve.transform(_controller.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * slideOffset),
            child: child,
          ),
        );
      },
    );
  }
}
