import 'package:flutter/material.dart';

/// The configuration of transition animation between loading/loaded states
///
/// Containing all parameters supported by the [AnimatedSwitcher] widget which is
/// used for the animation.
class VectorGraphicsStateTransitionConfig {

  /// Creates a [VectorGraphicsStateTransitionConfig] with the given parameters.
  ///
  /// All parameters are optional and have default values to simplify usage.
  const VectorGraphicsStateTransitionConfig({
    this.duration = const Duration(milliseconds: 400),
    this.reverseDuration,
    this.switchInCurve = Curves.linear,
    this.switchOutCurve = Curves.linear,
    this.transitionBuilder = AnimatedSwitcher.defaultTransitionBuilder,
    this.layoutBuilder = AnimatedSwitcher.defaultLayoutBuilder,
  });

  /// The duration of the transition from one state to the next.
  ///
  /// Defaults to 400 milliseconds.
  final Duration duration;

  /// The duration of the reverse transition from the next state to the previous one.
  final Duration? reverseDuration;

  /// The curve to apply when transitioning in.
  ///
  /// Defaults to [Curves.linear].
  final Curve switchInCurve;

  /// The curve to apply when transitioning out.
  ///
  /// Defaults to [Curves.linear].
  final Curve switchOutCurve;

  /// The builder for constructing the transition animations.
  ///
  /// Defaults to [AnimatedSwitcher.defaultTransitionBuilder].
  final AnimatedSwitcherTransitionBuilder transitionBuilder;

  /// The builder for laying out the child widgets during the transition.
  ///
  /// Defaults to [AnimatedSwitcher.defaultLayoutBuilder].
  final AnimatedSwitcherLayoutBuilder layoutBuilder;
}
