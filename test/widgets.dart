import 'package:feature_discovery/feature_discovery.dart';
import 'package:flutter/material.dart';

@visibleForTesting
class TestWidget extends StatelessWidget {
  final Iterable<String> featureIds;

  const TestWidget({Key key, @required this.featureIds}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FeatureDiscovery(
      child: MaterialApp(
        title: 'FeatureDiscovery Test',
        home: Scaffold(
          appBar: AppBar(
            title: const Text('TestWidget'),
          ),
          body: Center(
            child: Column(
              children: featureIds
                  .map((featureId) => TestIcon(featureId: featureId))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class TestIcon extends StatefulWidget {
  final String featureId;

  const TestIcon({Key key, @required this.featureId}) : super(key: key);

  @override
  TestIconState createState() => TestIconState();
}

@visibleForTesting
class TestIconState extends State<TestIcon> {
  @override
  Widget build(BuildContext context) {
    const Icon icon = Icon(Icons.more_horiz);
    return DescribedFeatureOverlay(
      featureId: widget.featureId,
      enablePulsingAnimation: false,
      // mandatory to use pumpAndSettle in tests
      child: icon,
      tapTarget: icon,
      title: const Text('This is it'),
      description: Text('Test has passed for ${widget.featureId}'),
    );
  }
}

/// This contains the complete tree necessary to pump it to the [WidgetTester]
/// and contains an icon that is covered by the overlay because it is overflowing.
/// If [OverflowMode.clipContent] is used, the tester should be able to trigger dismissal.
@visibleForTesting
class OverflowingDescriptionFeature extends StatelessWidget {
  final String featureId;
  final IconData icon;

  final void Function(BuildContext context) onContext;
  final void Function() onDismiss;

  final OverflowMode mode;

  const OverflowingDescriptionFeature({
    Key key,
    this.onContext,
    this.featureId,
    this.icon,
    this.mode,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(_) => FeatureDiscovery(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                onContext(context);

                return Stack(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.topLeft,
                      child: DescribedFeatureOverlay(
                        featureId: featureId,
                        tapTarget: Icon(Icons.arrow_drop_down_circle),
                        description: Container(
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.height,
                          color: Color(0xff000000),
                        ),
                        contentLocation: ContentLocation.below,
                        enablePulsingAnimation: false,
                        overflowMode: mode,
                        onDismiss: () async {
                          onDismiss?.call();
                          return true;
                        },
                        child: Container(
                          width: 1e2,
                          height: 1e2,
                          color: Color(0xfffffff),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Icon(icon),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}
