import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Screen demonstrating various animation types
class AnimationsScreen extends StatefulWidget {
  const AnimationsScreen({super.key});

  @override
  State<AnimationsScreen> createState() => _AnimationsScreenState();
}

class _AnimationsScreenState extends State<AnimationsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isAnimating = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleAnimation() {
    setState(() {
      _isAnimating = !_isAnimating;
      if (_isAnimating) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Animations Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isAnimating ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleAnimation,
            tooltip: _isAnimating ? 'Pause' : 'Play',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAnimationCard(
            'Fade Animation',
            FadeTransition(
              opacity: TweenSequence<double>([
                TweenSequenceItem(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: 0.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 40.0,
                ),
                TweenSequenceItem(
                  tween: ConstantTween<double>(0.0),
                  weight: 20.0,
                ),
                TweenSequenceItem(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 40.0,
                ),
              ]).animate(_controller),
              child: Container(
                width: 100,
                height: 100,
                color: Colors.blue,
                child: const Center(
                  child: Text('Fade', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          _buildAnimationCard(
            'Scale Animation',
            ScaleTransition(
              scale: TweenSequence<double>([
                TweenSequenceItem(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: 0.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50.0,
                ),
                TweenSequenceItem(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50.0,
                ),
              ]).animate(_controller),
              child: Container(
                width: 100,
                height: 100,
                color: Colors.green,
                child: const Center(
                  child: Text('Scale', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          _buildAnimationCard(
            'Rotation Animation',
            RotationTransition(
              turns: TweenSequence<double>([
                TweenSequenceItem(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50.0,
                ),
                TweenSequenceItem(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: 0.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50.0,
                ),
              ]).animate(_controller),
              child: Container(
                width: 100,
                height: 100,
                color: Colors.cyan,
                child: const Center(
                  child: Text('Rotate', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          _buildAnimationCard(
            'Slide Animation',
            SlideTransition(
              position: TweenSequence<Offset>([
                TweenSequenceItem(
                  tween: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(1.0, 0.0),
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50.0,
                ),
                TweenSequenceItem(
                  tween: Tween<Offset>(
                    begin: const Offset(1.0, 0.0),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50.0,
                ),
              ]).animate(_controller),
              child: Container(
                width: 100,
                height: 100,
                color: Colors.purple,
                child: const Center(
                  child: Text('Slide', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          _buildAnimationCard(
            'Size Animation',
            MixpanelMask(
              child: SizeTransition(
                sizeFactor: TweenSequence<double>([
                  TweenSequenceItem(
                    tween: Tween<double>(
                      begin: 1.0,
                      end: 0.0,
                    ).chain(CurveTween(curve: Curves.easeInOut)),
                    weight: 50.0,
                  ),
                  TweenSequenceItem(
                    tween: Tween<double>(
                      begin: 0.0,
                      end: 1.0,
                    ).chain(CurveTween(curve: Curves.easeInOut)),
                    weight: 50.0,
                  ),
                ]).animate(_controller),
                axis: Axis.horizontal,
                child: Container(
                  width: 200,
                  height: 100,
                  color: Colors.teal,
                  child: Center(
                    child: ScaleTransition(
                      scale: TweenSequence<double>([
                        TweenSequenceItem(
                          tween: Tween<double>(
                            begin: 1.0,
                            end: 0.0,
                          ).chain(CurveTween(curve: Curves.easeInOut)),
                          weight: 50.0,
                        ),
                        TweenSequenceItem(
                          tween: Tween<double>(
                            begin: 0.0,
                            end: 1.0,
                          ).chain(CurveTween(curve: Curves.easeInOut)),
                          weight: 50.0,
                        ),
                      ]).animate(_controller),
                      child: const Text(
                        'Size & Scale',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimationCard(String title, Widget animation) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Center(child: animation),
          ],
        ),
      ),
    );
  }
}
