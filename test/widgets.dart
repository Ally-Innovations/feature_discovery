import 'package:feature_discovery/feature_discovery.dart';
import 'package:flutter/material.dart';

@visibleForTesting
class TestWidget extends StatelessWidget {

  final Iterable<String> featureIds;

  const TestWidget({
    Key key,
    @required this.featureIds
  }) : 
    super(key: key);

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

  const TestIcon({
    Key key,
    @required this.featureId
  }) : 
    super(key: key);

  @override
  TestIconState createState() => TestIconState();
}

@visibleForTesting
class TestIconState extends State<TestIcon> {

  @override
  Widget build (BuildContext context) {
    const Icon icon = Icon(Icons.more_horiz);
    return DescribedFeatureOverlay(
      featureId: widget.featureId,
      enablePulsingAnimation: false, // mandatory to use pumpAndSettle in tests
      child: icon,
      tapTarget: icon,
      title: const Text('This is it'),
      description: Text('Test has passed for ${widget.featureId}'),
    );
  }
}
