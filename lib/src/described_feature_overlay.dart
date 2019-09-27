part of 'package:feature_discovery/src/feature_discovery.dart';

class DescribedFeatureOverlay extends StatefulWidget {
  /// This id should be unique among all the [DescribedFeatureOverlay] widgets.
  /// Otherwise, multiple overlays would show at once, which is currently
  /// only possible if [allowShowingDuplicate] is set to `true`.
  final String featureId;

  /// By default, for every feature id, i.e. for every step in the feature discovery,
  /// there can only be a single active overlay at a time.
  /// This measure was taken primarily to prevent duplicate overlays from showing
  /// when the same widget is inserted into the widget tree multiple times,
  /// e.g. when there is an open [DropdownButton].
  final bool allowShowingDuplicate;

  /// The color of the large circle, where the text sits on.
  /// If null, defaults to [ThemeData.primaryColor].
  final Color backgroundColor;

  /// Color of the target, that is the small circle behind the tap target.
  final Color targetColor;

  /// Color for title and text.
  final Color textColor;

  final Widget title;
  final Widget description;

  /// This is usually an [Icon].
  /// The final tap target will already have a tap listener to finish each step.
  ///
  /// If you want to hit the tap target in integration tests, you should pass a [Key]
  /// to this [Widget] instead of as the [Key] of [DescribedFeatureOverlay].
  final Widget tapTarget;

  final Widget child;
  final ContentOrientation contentLocation;
  final bool enablePulsingAnimation;

  /// Called just before the overlay is displayed.
  /// This function needs to return a [bool], either from an `async` scope
  /// or as a [Future].
  ///
  /// If this function returns `false`, this step will be marked complete
  /// and therefore be skipped, i.e. it will not be opened.
  /// In this case, we try to open the next step.
  ///
  /// When the [Future] finishes and evaluates to `true`, this step will be shown.
  final Future<bool> Function() onOpen;

  /// Called whenever the user taps outside the overlay area.
  /// This function needs to return a [bool], either from an `async` scope
  /// or as a [Future].
  ///
  /// If the function returns `false`, nothing happens. If it returns `true`,
  /// all of the current steps are dismissed.
  final Future<bool> Function() onDismiss;

  /// Called when the tap target is tapped.
  /// Whenever the [Future] this function returns is finished, the feature discovery
  /// will continue and the next step will try to open after a closing animation.
  final Future<void> Function() onComplete;

  /// Controls what happens with content that overflows the background's area.
  ///
  /// Defaults to [OverflowMode.doNothing].
  ///
  /// See also:
  ///
  ///  * [OverflowMode], which has explanations for the different modes.
  final OverflowMode overflowMode;

  const DescribedFeatureOverlay({
    Key key,
    @required this.featureId,
    @required this.tapTarget,
    this.backgroundColor,
    this.targetColor = Colors.white,
    this.textColor = Colors.white,
    this.title,
    this.description,
    @required this.child,
    this.onComplete,
    this.onDismiss,
    this.onOpen,
    this.contentLocation = ContentOrientation.trivial,
    this.enablePulsingAnimation = true,
    this.allowShowingDuplicate = false,
    this.overflowMode = OverflowMode.doNothing,
  })  : assert(featureId != null),
        assert(tapTarget != null),
        assert(child != null),
        assert(contentLocation != null),
        assert(enablePulsingAnimation != null),
        assert(targetColor != null),
        assert(textColor != null),
        assert(overflowMode != null),
        super(key: key);

  @override
  _DescribedFeatureOverlayState createState() =>
      _DescribedFeatureOverlayState();
}

class _DescribedFeatureOverlayState extends State<DescribedFeatureOverlay>
    with TickerProviderStateMixin {
  Size _screenSize;

  bool _showOverlay;

  _OverlayState _state;

  double _transitionProgress;

  AnimationController _openController;
  AnimationController _completeController;
  AnimationController _dismissController;
  AnimationController _pulseController;

  Stream<String> _startStream;
  Stream<String> _dismissStream;
  Stream<String> _completeStream;
  StreamSubscription<String> _startStreamSubscription;
  StreamSubscription<String> _dismissStreamSubscription;
  StreamSubscription<String> _completeStreamSubscription;

  @override
  void initState() {
    _showOverlay = false;

    _state = _OverlayState.closed;

    _transitionProgress = 1;

    _initAnimationControllers();
    super.initState();
  }

  @override
  void dispose() {
    _openController.dispose();
    _completeController.dispose();
    _dismissController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DescribedFeatureOverlay oldWidget) {
    if (oldWidget.enablePulsingAnimation != widget.enablePulsingAnimation) {
      if (widget.enablePulsingAnimation)
        _pulseController.forward(from: 0);
      else {
        _pulseController.stop();
        setState(() => _transitionProgress = 0);
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Bloc bloc = FeatureDiscovery._blocOf(context);
    final Stream<String> newDismissStream = bloc.outDismiss;
    final Stream<String> newCompleteStream = bloc.outComplete;
    final Stream<String> newStartStream = bloc.outStart;
    if (_dismissStream != newDismissStream) _setDismissStream(newDismissStream);
    if (_completeStream != newCompleteStream)
      _setCompleteStream(newCompleteStream);
    if (_startStream != newStartStream) _setStartStream(newStartStream);
    _screenSize = MediaQuery.of(context).size;
  }

  void _setDismissStream(Stream<void> newStream) {
    _dismissStreamSubscription?.cancel();
    _dismissStream = newStream;
    _dismissStreamSubscription = _dismissStream.listen((featureId) async {
      assert(featureId != null);
      if (featureId == widget.featureId) await _dismiss();
    });
  }

  void _setCompleteStream(Stream<void> newStream) {
    _completeStreamSubscription?.cancel();
    _completeStream = newStream;
    _completeStreamSubscription = _completeStream.listen((featureId) async {
      assert(featureId != null);
      if (featureId == widget.featureId) await _complete();
    });
  }

  void _setStartStream(Stream<void> newStream) {
    _startStreamSubscription?.cancel();
    _startStream = newStream;
    _startStreamSubscription = _startStream.listen((featureId) async {
      assert(featureId != null);
      if (featureId == widget.featureId) await _open();
    });
  }

  void _initAnimationControllers() {
    _openController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 250))
          ..addListener(
              () => setState(() => _transitionProgress = _openController.value))
          ..addStatusListener(
            (AnimationStatus status) {
              if (status == AnimationStatus.forward)
                setState(() => _state = _OverlayState.opening);
              else if (status == AnimationStatus.completed &&
                  widget.enablePulsingAnimation == true)
                _pulseController.forward(from: 0.0);
            },
          );

    _pulseController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 1000))
          ..addListener(() {
            setState(() => _transitionProgress = _pulseController.value);
          })
          ..addStatusListener(
            (AnimationStatus status) {
              if (status == AnimationStatus.forward)
                setState(() => _state = _OverlayState.pulsing);
              else if (status == AnimationStatus.completed)
                _pulseController.forward(from: 0.0);
            },
          );

    _completeController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 250))
      ..addListener(
          () => setState(() => _transitionProgress = _completeController.value))
      ..addStatusListener(
        (AnimationStatus status) {
          if (status == AnimationStatus.forward)
            setState(() => _state = _OverlayState.activating);
        },
      );

    _dismissController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 250))
      ..addListener(
          () => setState(() => _transitionProgress = _dismissController.value))
      ..addStatusListener(
        (AnimationStatus status) {
          if (status == AnimationStatus.forward)
            setState(() => _state = _OverlayState.dismissing);
        },
      );
  }

  void _show() {
    // The activeStep might have changed by now because onOpen is asynchronous.
    // TODO
    //if (activeStep != widget.featureId) return;

    _openController.forward(from: 0.0);
    setState(() => _showOverlay = true);
  }

  Future<void> _open() async {
    if (widget.onOpen != null) {
      final bool shouldOpen = await widget.onOpen();
      assert(shouldOpen != null,
          "You must return true or false at the end of the [onOpen] function");
      if (shouldOpen)
        _show();
      else
        FeatureDiscovery.completeCurrentStep(context);
    } else
      _show();
  }

  Future<void> _complete() async {
    if (_completeController.isAnimating) return;

    if (widget.onComplete != null) await widget.onComplete();
    _openController.stop();
    _pulseController.stop();
    await _completeController.forward(from: 0.0);
    setState(() => _showOverlay = false);
  }

  Future<void> _dismiss() async {
    // The method might be triggered multiple times, especially when swiping.
    if (_dismissController.isAnimating) return;

    if (widget.onDismiss != null) {
      final bool shouldDismiss = await widget.onDismiss();
      assert(shouldDismiss != null);
      if (!shouldDismiss) return;
    }
    _openController.stop();
    _pulseController.stop();
    await _dismissController.forward(from: 0.0);
    setState(() => _showOverlay = false);
  }

  bool _isCloseToTopOrBottom(Offset position) {
    return position.dy <= 88.0 || (_screenSize.height - position.dy) <= 88.0;
  }

  bool _isOnTopHalfOfScreen(Offset position) {
    return position.dy < (_screenSize.height / 2.0);
  }

  bool _isOnLeftHalfOfScreen(Offset position) {
    return position.dx < (_screenSize.width / 2.0);
  }

  double _backgroundRadius(Offset anchor) {
    final bool isBackgroundCentered = _isCloseToTopOrBottom(anchor);
    final double backgroundRadius = min(_screenSize.width, _screenSize.height) *
        (isBackgroundCentered ? 1.0 : 0.7);
    switch (_state) {
      case _OverlayState.opening:
        final double adjustedPercent =
            const Interval(0.0, 0.8, curve: Curves.easeOut)
                .transform(_transitionProgress);
        return backgroundRadius * adjustedPercent;
      case _OverlayState.activating:
        return backgroundRadius + _transitionProgress * 40.0;
      case _OverlayState.dismissing:
        return backgroundRadius * (1 - _transitionProgress);
      default:
        return backgroundRadius;
    }
  }

  Offset _backgroundPosition(Offset anchor) {
    final double width = min(_screenSize.width, _screenSize.height);
    final bool isBackgroundCentered = _isCloseToTopOrBottom(anchor);

    if (isBackgroundCentered) {
      return anchor;
    } else {
      final startingBackgroundPosition = anchor;

      Offset endingBackgroundPosition;
      switch (widget.contentLocation) {
        case ContentOrientation.trivial:
          endingBackgroundPosition = Offset(
              width / 2.0 + (_isOnLeftHalfOfScreen(anchor) ? -20.0 : 20.0),
              anchor.dy +
                  (_isOnTopHalfOfScreen(anchor)
                      ? -(width / 2.0) + 40.0
                      : (width / 2.0) - 40.0));
          break;
        case ContentOrientation.above:
          endingBackgroundPosition = Offset(
              width / 2.0 + (_isOnLeftHalfOfScreen(anchor) ? -20.0 : 20.0),
              anchor.dy - (width / 2.0) + 40.0);
          break;
        case ContentOrientation.below:
          endingBackgroundPosition = Offset(
              width / 2.0 + (_isOnLeftHalfOfScreen(anchor) ? -20.0 : 20.0),
              anchor.dy + (width / 2.0) - 40.0);
          break;
      }

      switch (_state) {
        case _OverlayState.opening:
          final double adjustedPercent =
              const Interval(0.0, 0.8, curve: Curves.easeOut)
                  .transform(_transitionProgress);
          return Offset.lerp(startingBackgroundPosition,
              endingBackgroundPosition, adjustedPercent);
        case _OverlayState.activating:
          return endingBackgroundPosition;
        case _OverlayState.dismissing:
          return Offset.lerp(endingBackgroundPosition,
              startingBackgroundPosition, _transitionProgress);
        default:
          return endingBackgroundPosition;
      }
    }
  }

  Widget _buildOverlay(Offset anchor) {
    final backgroundPosition = _backgroundPosition(anchor),
        backgroundRadius = _backgroundRadius(anchor);

    return Stack(
      children: <Widget>[
        GestureDetector(
          onTap: () => FeatureDiscovery.dismiss(context),
          // According to the spec, the user should be able to dismiss by swiping.
          onPanUpdate: (DragUpdateDetails _) =>
              FeatureDiscovery.dismiss(context),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
          ),
        ),
        _Background(
          transitionProgress: _transitionProgress,
          color: widget.backgroundColor ?? Theme.of(context).primaryColor,
          state: _state,
          overflowMode: widget.overflowMode,
          position: backgroundPosition,
          radius: backgroundRadius,
        ),
        _Content(
          state: _state,
          transitionProgress: _transitionProgress,
          anchor: anchor,
          screenSize: _screenSize,
          touchTargetRadius: 44.0,
          title: widget.title,
          description: widget.description,
          orientation: widget.contentLocation,
          textColor: widget.textColor,
          overflowMode: widget.overflowMode,
          backgroundPosition: backgroundPosition,
          backgroundRadius: backgroundRadius,
        ),
        _Pulse(
          state: _state,
          transitionProgress: _transitionProgress,
          anchor: anchor,
          color: widget.targetColor,
        ),
        _TapTarget(
          state: _state,
          transitionProgress: _transitionProgress,
          anchor: anchor,
          color: widget.targetColor,
          onPressed: () => FeatureDiscovery.completeCurrentStep(context),
          child: widget.tapTarget,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredOverlay(
      showOverlay: _showOverlay,
      overlayBuilder: (BuildContext context, Offset anchor) {
        return _buildOverlay(anchor);
      },
      child: widget.child,
    );
  }
}

class _Background extends StatelessWidget {
  final _OverlayState state;
  final double transitionProgress;
  final Color color;
  final OverflowMode overflowMode;

  final double radius;
  final Offset position;

  const _Background({
    Key key,
    this.color,
    this.state,
    this.transitionProgress,
    this.overflowMode,
    this.position,
    this.radius,
  })  : assert(color != null),
        assert(state != null),
        assert(transitionProgress != null),
        assert(position != null),
        assert(radius != null),
        super(key: key);

  double backgroundOpacity() {
    switch (state) {
      case _OverlayState.opening:
        final double adjustedPercent =
            const Interval(0.0, 0.3, curve: Curves.easeOut)
                .transform(transitionProgress);
        return 0.96 * adjustedPercent;

      case _OverlayState.activating:
        final double adjustedPercent =
            const Interval(0.1, 0.6, curve: Curves.easeOut)
                .transform(transitionProgress);

        return 0.96 * (1 - adjustedPercent);
      case _OverlayState.dismissing:
        final double adjustedPercent =
            const Interval(0.2, 1.0, curve: Curves.easeOut)
                .transform(transitionProgress);
        return 0.96 * (1 - adjustedPercent);
      default:
        return 0.96;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (state == _OverlayState.closed) {
      return Container();
    }

    return CenterAbout(
      position: position,
      child: Container(
        width: 2 * radius,
        height: 2 * radius,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(backgroundOpacity())),
      ),
    );
  }
}

class _Pulse extends StatelessWidget {
  final _OverlayState state;
  final double transitionProgress;
  final Offset anchor;
  final Color color;

  const _Pulse({
    Key key,
    this.state,
    this.transitionProgress,
    this.anchor,
    this.color,
  })  : assert(state != null),
        assert(transitionProgress != null),
        assert(anchor != null),
        assert(color != null),
        super(key: key);

  double radius() {
    switch (state) {
      case _OverlayState.pulsing:
        double expandedPercent;
        if (transitionProgress >= 0.3 && transitionProgress <= 0.8) {
          expandedPercent = (transitionProgress - 0.3) / 0.5;
        } else {
          expandedPercent = 0.0;
        }
        return 44.0 + (35.0 * expandedPercent);
      case _OverlayState.dismissing:
      case _OverlayState.activating:
        return 0.0; //(44.0 + 35.0) * (1.0 - transitionProgress);
      default:
        return 0.0;
    }
  }

  double opacity() {
    switch (state) {
      case _OverlayState.pulsing:
        final double percentOpaque =
            1.0 - ((transitionProgress.clamp(0.3, 0.8) - 0.3) / 0.5);
        return (percentOpaque * 0.75).clamp(0.0, 1.0);
      case _OverlayState.activating:
      case _OverlayState.dismissing:
        return 0.0; //((1.0 - transitionProgress) * 0.5).clamp(0.0, 1.0);
      default:
        return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return state == _OverlayState.closed
        ? Container(height: 0, width: 0)
        : CenterAbout(
            position: anchor,
            child: Container(
              width: radius() * 2,
              height: radius() * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(opacity()),
              ),
            ),
          );
  }
}

class _TapTarget extends StatelessWidget {
  final _OverlayState state;
  final double transitionProgress;
  final Offset anchor;
  final Widget child;
  final Color color;
  final VoidCallback onPressed;

  const _TapTarget({
    Key key,
    this.anchor,
    this.child,
    this.onPressed,
    this.color,
    this.state,
    this.transitionProgress,
  })  : assert(anchor != null),
        assert(child != null),
        assert(state != null),
        assert(transitionProgress != null),
        assert(color != null),
        super(key: key);

  double opacity() {
    switch (state) {
      case _OverlayState.opening:
        return const Interval(0.0, 0.3, curve: Curves.easeOut)
            .transform(transitionProgress);
      case _OverlayState.activating:
      case _OverlayState.dismissing:
        return 1.0 -
            const Interval(0.7, 1.0, curve: Curves.easeOut)
                .transform(transitionProgress);
      default:
        return 1.0;
    }
  }

  double radius() {
    switch (state) {
      case _OverlayState.closed:
        return 0.0;
      case _OverlayState.opening:
        return 20.0 + 24.0 * transitionProgress;
      case _OverlayState.pulsing:
        double expandedPercent;
        if (transitionProgress < 0.3)
          expandedPercent = transitionProgress / 0.3;
        else if (transitionProgress < 0.6)
          expandedPercent = 1.0 - ((transitionProgress - 0.3) / 0.3);
        else
          expandedPercent = 0.0;
        return 44.0 + (20.0 * expandedPercent);
      case _OverlayState.activating:
      case _OverlayState.dismissing:
        return 20.0 + 24.0 * (1 - transitionProgress);
      default:
        return 44.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CenterAbout(
      position: anchor,
      child: Container(
        height: 2 * radius(),
        width: 2 * radius(),
        child: Opacity(
          opacity: opacity(),
          child: RawMaterialButton(
            fillColor: color,
            shape: const CircleBorder(),
            child: child,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _Content extends StatefulWidget {
  final _OverlayState state;
  final double transitionProgress;
  final Offset anchor;
  final Size screenSize;
  final double touchTargetRadius;

  // Can be null.
  final Widget title;

  // Can be null.
  final Widget description;

  final ContentOrientation orientation;
  final Color textColor;

  final OverflowMode overflowMode;
  final double backgroundRadius;
  final Offset backgroundPosition;

  const _Content({
    Key key,
    this.anchor,
    this.screenSize,
    this.touchTargetRadius,
    this.title,
    this.description,
    this.state,
    this.transitionProgress,
    this.orientation,
    this.textColor,
    this.overflowMode,
    this.backgroundRadius,
    this.backgroundPosition,
  })  : assert(anchor != null),
        assert(screenSize != null),
        assert(touchTargetRadius != null),
        assert(state != null),
        assert(transitionProgress != null),
        assert(orientation != null),
        assert(textColor != null),
        super(key: key);

  @override
  __ContentState createState() => __ContentState();
}

class __ContentState extends State<_Content> {
  bool isCloseToTopOrBottom(Offset position) {
    return position.dy <= 88.0 ||
        (widget.screenSize.height - position.dy) <= 88.0;
  }

  bool isOnTopHalfOfScreen(Offset position) {
    return position.dy < (widget.screenSize.height / 2.0);
  }

  bool isOnLeftHalfOfScreen(Offset position) {
    return position.dx < (widget.screenSize.width / 2.0);
  }

  _DescribedFeatureContentOrientation getContentOrientation(Offset position) {
    if (isCloseToTopOrBottom(position))
      return isOnTopHalfOfScreen(position)
          ? _DescribedFeatureContentOrientation.below
          : _DescribedFeatureContentOrientation.above;
    else
      return isOnTopHalfOfScreen(position)
          ? _DescribedFeatureContentOrientation.above
          : _DescribedFeatureContentOrientation.below;
  }

  double opacity() {
    switch (widget.state) {
      case _OverlayState.closed:
        return 0.0;
      case _OverlayState.opening:
        final double adjustedPercent =
            const Interval(0.6, 1.0, curve: Curves.easeOut)
                .transform(widget.transitionProgress);
        return adjustedPercent;
      case _OverlayState.activating:
      case _OverlayState.dismissing:
        final double adjustedPercent =
            const Interval(0.0, 0.4, curve: Curves.easeOut)
                .transform(widget.transitionProgress);
        return 1.0 - adjustedPercent;
      default:
        return 1.0;
    }
  }

  Offset centerPosition() {
    final double width = min(widget.screenSize.width, widget.screenSize.height);
    final bool isBackgroundCentered = isCloseToTopOrBottom(widget.anchor);

    if (isBackgroundCentered)
      return widget.anchor;
    else {
      final Offset startingBackgroundPosition = widget.anchor;
      final Offset endingBackgroundPosition = Offset(
          width / 2.0 + (isOnLeftHalfOfScreen(widget.anchor) ? -20.0 : 20.0),
          widget.anchor.dy +
              (isOnTopHalfOfScreen(widget.anchor)
                  ? -(width / 2) + 40.0
                  : (width / 20.0) - 40.0));

      switch (widget.state) {
        case _OverlayState.opening:
          final double adjustedPercent =
              const Interval(0.0, 0.8, curve: Curves.easeOut)
                  .transform(widget.transitionProgress);
          return Offset.lerp(startingBackgroundPosition,
              endingBackgroundPosition, adjustedPercent);
        case _OverlayState.activating:
          return endingBackgroundPosition;
        case _OverlayState.dismissing:
          return Offset.lerp(endingBackgroundPosition,
              startingBackgroundPosition, widget.transitionProgress);
        default:
          return endingBackgroundPosition;
      }
    }
  }

  bool laidOut;

  @override
  Widget build(BuildContext context) {
    double contentOffsetMultiplier;

    switch (widget.orientation) {
      case ContentOrientation.trivial:
        contentOffsetMultiplier = getContentOrientation(widget.anchor) ==
                _DescribedFeatureContentOrientation.below
            ? 1.0
            : -1.0;
        break;
      case ContentOrientation.above:
        contentOffsetMultiplier = -1.0;
        break;
      case ContentOrientation.below:
        contentOffsetMultiplier = 1.0;
        break;
    }

    final double width = min(widget.screenSize.width, widget.screenSize.height);

    final double contentY = widget.anchor.dy +
        contentOffsetMultiplier * (widget.touchTargetRadius + 20);

    final double contentFractionalOffset =
        contentOffsetMultiplier.clamp(-1.0, 0.0);

    final double dx = centerPosition().dx - width;
    final double contentX = (dx.isNegative) ? 0.0 : dx;

    Widget result = FractionalTranslation(
        translation: Offset(0.0, contentFractionalOffset),
        child: Opacity(
            opacity: opacity(),
            child: Container(
                width: width,
                child: Material(
                    color: Colors.transparent,
                    child: Padding(
                        padding: const EdgeInsets.only(left: 40.0, right: 40.0),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (widget.title != null)
                                DefaultTextStyle(
                                  style: Theme.of(context)
                                      .textTheme
                                      .title
                                      .copyWith(color: widget.textColor),
                                  child: widget.title,
                                ),
                              if (widget.title != null &&
                                  widget.description != null)
                                const SizedBox(height: 8.0),
                              if (widget.description != null)
                                DefaultTextStyle(
                                  style: Theme.of(context)
                                      .textTheme
                                      .body1
                                      .copyWith(
                                          color: widget.textColor
                                              .withOpacity(0.9)),
                                  child: widget.description,
                                )
                            ]))))));

    if (widget.overflowMode == OverflowMode.clip) {
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.
      // TODO(creativecreatorormaybenot) Move this into a SingleChildRenderObjectWidget as this is horrible.


      // If we want to know the current location of our context, we will have to build it twice
      // because the RenderObject for the current position will only be attached after the build phase.
      // For that reason we schedule a callback after the build phase, which will render the clipper.
      if (laidOut != true)
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {
              laidOut = true;
            }));
      else {
        // The next build might change the position of our widget, so we need to reset
        // laidOut to rebuild it in order to work with the RenderObject again.
        laidOut = false;

        // The _ContentClipper, i.e. CustomClipper's in general, work with local positions.
        // Thus, we need to convert the global backgroundPosition to a local position.
        final localPosition = (context.findRenderObject() as RenderBox)
            .globalToLocal(widget.backgroundPosition);

        result = ClipOval(
            clipper: _ContentClipper(
              radius: widget.backgroundRadius,
              position: localPosition,
            ),
            child: result);
      }
    }

    result = Positioned(top: contentY, left: contentX, child: result);

    return result;
  }
}

class _ContentClipper extends CustomClipper<Rect> {
  final double radius;
  final Offset position;

  const _ContentClipper({this.radius, this.position});

  @override
  Rect getClip(Size size) {
    return Rect.fromCircle(center: position, radius: radius);
  }

  @override
  bool shouldReclip(_ContentClipper oldClipper) {
    return oldClipper.radius != radius || oldClipper.position != position;
  }
}

/// Controls how content that overflows the background should be handled.
///
/// The default for [DescribedFeatureOverlay] is [doNothing].
///
/// Modes:
///
///  * [doNothing] will render the content as is, even if it exceeds the
///    boundaries of the background circle.
///  * [clip] will not render any content that is outside the background's area,
///    i.e. clip the content.
///  * [cover] will expand the background circle. The radius will be increased until
///    the content fits within the circle's area.
enum OverflowMode {
  doNothing,
  clip,
  cover,
}

enum _OverlayState {
  closed,
  opening,
  pulsing,
  activating,
  dismissing,
}

enum _DescribedFeatureContentOrientation {
  above,
  below,
}
