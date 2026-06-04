import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 语音服务 — 封装 STT（语音识别）和 TTS（文字转语音）
class SpeechService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  /// STT 是否可用
  Future<bool> get isSttAvailable => (!kIsWeb && !Platform.isLinux) ? _stt.initialize() : Future.value(false); // STT 在 Web 和 Linux 上不可用

  /// TTS 是否可用（通常总是可用）
  bool get isTtsAvailable => true;

  /// 开始语音识别，返回识别到的文本流
  Stream<String> startListening() {
    if (_isListening) return const Stream.empty();

    final controller = StreamController<String>(
      onCancel: () {
        _stt.stop();
        _isListening = false;
      },
    );

    _stt
        .initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              _isListening = false;
              if (!controller.isClosed) controller.close();
            }
          },
          onError: (error) {
            _isListening = false;
            if (!controller.isClosed) controller.addError(error);
          },
        )
        .then((available) {
          if (!available) {
            if (!controller.isClosed) controller.close();
            return;
          }

          _isListening = true;

          _stt.listen(
            onResult: (result) {
              if (!controller.isClosed) {
                controller.add(result.recognizedWords);
              }
            },
            // ignore: deprecated_member_use
            listenFor: const Duration(seconds: 60),
            // ignore: deprecated_member_use
            pauseFor: const Duration(seconds: 3),
            // ignore: deprecated_member_use
            partialResults: true,
            // ignore: deprecated_member_use
            listenMode: ListenMode.dictation,
          );
        });

    return controller.stream;
  }

  /// 停止语音识别
  Future<void> stopListening() async {
    if (_isListening) {
      await _stt.stop();
      _isListening = false;
    }
  }

  /// 获取最后一次识别结果
  String get lastRecognizedText => _stt.lastRecognizedWords;

  /// 获取当前识别的状态文本
  String get statusText => _stt.isListening ? 'listening' : 'notListening';

  // --- TTS ---

  /// 朗读文字
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    _isSpeaking = true;

    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);

    await _tts.speak(text);

    // 等待朗读完成
    await _tts.awaitSpeakCompletion(true);
    _isSpeaking = false;
  }

  /// 停止朗读
  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _tts.stop();
      _isSpeaking = false;
    }
  }

  /// 暂停朗读
  Future<void> pauseSpeaking() async {
    await _tts.pause();
  }

  /// 设置 TTS 语言
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  /// 设置朗读速度 (0.0 ~ 1.0)
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  /// 释放资源
  Future<void> dispose() async {
    await stopListening();
    await stopSpeaking();
  }
}
