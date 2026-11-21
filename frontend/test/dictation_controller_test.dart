import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/speech/speech_service.dart';
import 'package:frontend/features/shell/dictation_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/spreadsheet_controller.dart';
import 'package:frontend/features/spreadsheet/controllers/viewport_controller.dart';
import 'package:frontend/features/spreadsheet/models/cell_model.dart';
import 'package:frontend/features/spreadsheet/models/row_model.dart';
import 'package:frontend/features/spreadsheet/models/sheet_model.dart';

import 'support/fake_spreadsheet_service.dart';
import 'support/fake_speech_service.dart';

/// Speech to text: what happens between "start listening" and the text
/// appearing in the cell's editor, against a scripted speech engine.

SheetModel sheet() {
  CellModel cell(int row, int column, [String value = '']) =>
      CellModel(row: row, column: column, value: value);

  return SheetModel(
    name: 'Sheet1',
    headers: const ['A'],
    allRows: [
      RowModel(index: 0, cells: [cell(0, 0, '1')]),
    ],
    sheetId: 's1',
    rowIds: const ['r1'],
    columnIds: const ['c1'],
  );
}

(DictationController, FakeSpeechService, ViewportController) make({
  bool supported = true,
  bool withDocument = true,
}) {
  final speech = FakeSpeechService(supported: supported);
  final controller = SpreadsheetController(FakeService());
  final viewport = ViewportController();

  if (withDocument) {
    controller.showSheetForTesting(sheet(), filename: 'book.xlsx');
  }

  final dictation = DictationController(
    speech: speech,
    spreadsheetController: controller,
    viewportController: viewport,
    stopGrace: const Duration(milliseconds: 20),
  );

  addTearDown(controller.dispose);
  addTearDown(viewport.dispose);
  addTearDown(dictation.dispose);

  return (dictation, speech, viewport);
}

void main() {
  test(
    'a final result goes into the cell editor, to be kept with Enter',
    () async {
      final (dictation, speech, viewport) = make();

      await dictation.start();
      expect(dictation.isListening, isTrue);

      speech.say('total sales', isFinal: true);

      expect(dictation.state, DictationState.idle);
      expect(viewport.isEditing, isTrue);
      expect(viewport.initialEditValue, 'total sales');
      expect(viewport.replaceInitialValue, isTrue);
      expect(dictation.message, DictationController.placed);
    },
  );

  test(
    'the selected recognition locale is passed to the speech engine',
    () async {
      final (dictation, speech, _) = make();
      dictation.localeId = 'ar_SA';

      await dictation.start();

      expect(speech.lastLocaleId, 'ar_SA');
    },
  );

  test(
    'when listening ends without a final result, what was heard is used',
    () async {
      final (dictation, speech, viewport) = make();

      await dictation.start();
      speech.say('hello', isFinal: false);
      expect(dictation.heard, 'hello');
      expect(viewport.isEditing, isFalse); // not placed yet

      speech.end();

      expect(viewport.initialEditValue, 'hello');
      expect(dictation.isBusy, isFalse);
    },
  );

  test('toggling while listening stops and places the text', () async {
    final (dictation, speech, viewport) = make();

    await dictation.toggle();
    speech.say('abc');
    await dictation.toggle();

    expect(speech.calls, ['start', 'stop']);
    expect(viewport.initialEditValue, 'abc');
  });

  test(
    'if the engine never answers after stop, what was heard so far is used',
    () async {
      final (dictation, speech, viewport) = make();
      speech.endOnStop = false;

      await dictation.start();
      speech.say('late words');
      await dictation.stop();

      expect(dictation.isListening, isTrue); // still waiting for the engine

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(dictation.isBusy, isFalse);
      expect(viewport.initialEditValue, 'late words');
    },
  );

  test('hearing nothing says so and leaves the cell alone', () async {
    final (dictation, speech, viewport) = make();

    await dictation.start();
    speech.end();

    expect(dictation.message, DictationController.heardNothing);
    expect(viewport.isEditing, isFalse);
    expect(dictation.isBusy, isFalse);
  });

  test('whitespace only counts as nothing', () async {
    final (dictation, speech, viewport) = make();

    await dictation.start();
    speech.say('   ', isFinal: true);

    expect(dictation.message, DictationController.heardNothing);
    expect(viewport.isEditing, isFalse);
  });

  test('without a document it asks for one and does not listen', () async {
    final (dictation, speech, _) = make(withDocument: false);

    await dictation.start();

    expect(dictation.message, DictationController.needsDocument);
    expect(speech.calls, isEmpty);
    expect(dictation.canStart, isFalse);
  });

  test(
    'while a cell is being edited it declines and points to Win+H',
    () async {
      final (dictation, speech, viewport) = make();
      viewport.startEditing();

      await dictation.start();

      expect(dictation.message, DictationController.finishEditing);
      expect(dictation.message, contains('Win+H'));
      expect(speech.calls, isEmpty);
    },
  );

  test('on a platform without speech it says so', () async {
    final (dictation, speech, _) = make(supported: false);

    expect(dictation.isSupported, isFalse);

    await dictation.toggle();

    expect(dictation.message, DictationController.notSupported);
    expect(speech.calls, isEmpty);
  });

  test(
    'if listening cannot start the user is told what to check, and can retry',
    () async {
      final (dictation, speech, _) = make();
      speech.startResult = const SpeechStartResult.failed(
        SpeechProblem.unavailable,
      );

      await dictation.start();

      expect(dictation.message, DictationController.unavailable);
      expect(dictation.isBusy, isFalse);

      speech.startResult = const SpeechStartResult.ok();
      await dictation.start();

      expect(dictation.isListening, isTrue);
    },
  );

  test(
    'a missing offline model explains first-use requirements',
    () async {
      final (dictation, speech, _) = make();
      speech.startResult = const SpeechStartResult.failed(
        SpeechProblem.modelUnavailable,
      );

      await dictation.start();

      expect(dictation.message, DictationController.modelUnavailable);
      expect(dictation.message, contains('internet connection'));
      expect(dictation.isBusy, isFalse);
    },
  );

  test('a transcription failure is surfaced to the user', () async {
    final (dictation, speech, _) = make();

    await dictation.start();
    speech.fail(SpeechProblem.transcriptionFailed);

    expect(dictation.message, DictationController.transcriptionFailed);
    expect(dictation.isBusy, isFalse);
  });

  test('a blocked microphone is explained', () async {
    final (dictation, speech, _) = make();

    await dictation.start();
    speech.fail(SpeechProblem.permissionDenied);

    expect(dictation.message, DictationController.permissionDenied);
    expect(dictation.isBusy, isFalse);
  });

  test(
    '"no speech" after something was heard still uses what was heard',
    () async {
      final (dictation, speech, viewport) = make();

      await dictation.start();
      speech.say('half a sentence');
      speech.fail(SpeechProblem.noSpeech);

      expect(viewport.initialEditValue, 'half a sentence');
    },
  );

  test('any other error stops with a plain message', () async {
    final (dictation, speech, viewport) = make();

    await dictation.start();
    speech.fail(SpeechProblem.other);

    expect(dictation.message, DictationController.stoppedUnexpectedly);
    expect(viewport.isEditing, isFalse);
  });

  test('pressing start twice starts once', () async {
    final (dictation, speech, _) = make();
    speech.startGate = Completer<void>();

    final first = dictation.toggle();
    final second = dictation.toggle(); // ignored: still starting

    speech.startGate!.complete();
    await first;
    await second;

    expect(speech.calls, ['start']);
    expect(dictation.isListening, isTrue);
  });

  test('results that arrive after the session ended are ignored', () async {
    final (dictation, speech, viewport) = make();

    await dictation.start();
    speech.say('first', isFinal: true);
    viewport.stopEditing();

    speech.say('late', isFinal: true);
    speech.end();

    expect(viewport.isEditing, isFalse);
  });

  test(
    'text is not forced into a cell the user started editing meanwhile',
    () async {
      final (dictation, speech, viewport) = make();

      await dictation.start();
      viewport.startEditing(replaceInitialValue: true, initialValue: 'typed');

      speech.say('spoken', isFinal: true);

      expect(viewport.initialEditValue, 'typed');
      expect(dictation.message, contains('not inserted'));
    },
  );

  test(
    'every notice gets its own number, so the screen shows each once',
    () async {
      final (dictation, speech, _) = make();
      final before = dictation.messageSerial;

      await dictation.start();
      speech.end();
      await dictation.start();
      speech.end();

      expect(dictation.messageSerial, before + 2);
    },
  );

  test('listeners hear listening start and end', () async {
    final (dictation, speech, _) = make();
    final states = <DictationState>[];
    dictation.addListener(() => states.add(dictation.state));

    await dictation.start();
    speech.say('x', isFinal: true);

    expect(states, contains(DictationState.listening));
    expect(states.last, DictationState.idle);
  });

  test('closing the app while listening cancels the engine', () async {
    final (dictation, speech, _) = make();

    await dictation.start();
    dictation.dispose();

    expect(speech.calls, contains('cancel'));
  });
}
