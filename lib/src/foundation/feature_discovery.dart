import 'package:feature_discovery/src/foundation.dart';
import 'package:flutter/material.dart';

/// Specifies how the content should be positioned relative to the tap target.
///
/// Orientations:
///
///  * [trivial], which lets the library decide where the content should be placed.
///    Make sure to test this for every overlay because the trivial positioning can fail sometimes.
///  * [above], which will layout the content above the tap target.
///  * [below], which will layout the content below the tap target.
enum ContentLocation {
  above,
  below,
  trivial,
}

class FeatureDiscovery extends StatelessWidget {
  /// Steps are the featureIds of the overlays.
  /// Though they can be placed in any [Iterable], it is recommended to pass them as a [Set]
  /// because this ensures that every step is only shown once.
  static void discoverFeatures(BuildContext context, Iterable<String> steps) =>
      Bloc.of(context).discoverFeatures(steps: steps.toList());

  /// This will schedule completion of the current discovery step and continue
  /// onto the step after the completion animation of the current overlay if successful.
  ///
  /// The [stepId] ensures that you are marking the correct feature for completion.
  /// If the provided [stepId] does not match the feature that is currently shown, i.e.
  /// the currently active step, nothing will happen.
  static void completeCurrentStep(BuildContext context) =>
      Bloc.of(context).completeStep();

  /// This will schedule dismissal of the current discovery step and with that
  /// of the current feature discovery. The dismissal animation will play if successful.
  /// If you want to complete the step and continue the feature discovery,
  /// call [completeCurrentStep] instead.
  static void dismissAll(BuildContext context) => Bloc.of(context).dismiss();

  @Deprecated("Use [dismissAll] instead.")
  static void dismiss(BuildContext context) => dismissAll(context);

  /// This returns the feature id of the current feature discovery step, i.e.
  /// of the [DescribedFeatureOverlay] that is currently supposed to be shown, or `null`.
  ///
  /// Note that this will also return the feature id of the current step of the steps
  /// you passed to [discoverFeature] even when there is no [DescribedFeatureOverlay]
  /// in the tree to display the overlay.
  /// This means that you cannot use this to check if a feature overlay is being displayed.
  static String currentFeatureIdOf(BuildContext context) =>
      Bloc.of(context).activeFeatureId;

  @Deprecated("Use [currentFeatureIdOf] instead.")
  static String activeFeatureId(BuildContext context) =>
      currentFeatureIdOf(context);

  final Widget child;

  const FeatureDiscovery({Key key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) => BlocProvider(child: child);
}
