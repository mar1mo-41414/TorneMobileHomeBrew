/// Maps the core's unified errors (plan 12.6) to user-facing Japanese
/// messages. The core holds only message keys; the wording lives here
/// so the core stays UI- and locale-free.
library;

import '../core/core.dart';

/// A user-facing explanation for [error] (usually a [NasneError]).
String userMessageForError(Object error) {
  if (error is NasneError) {
    final code = error.code ?? '';
    return switch (error.messageKey) {
      'error.unreachable' => 'nasne に接続できませんでした。電源とネットワークを確認してください。',
      'error.notImplemented' => 'このファームウェアでは未対応の機能です。',
      'error.http' => 'nasne からエラーが返りました (HTTP $code)。',
      'error.webapi' => 'nasne がエラーを返しました (コード $code)。',
      'error.invalidArgs' => '要求の形式が正しくありませんでした。',
      'error.invalidIdFormat' => 'ID の形式が正しくありませんでした。',
      'error.soapFault' => '操作に失敗しました (コード $code)。',
      'error.parse' => 'nasne の応答を読み取れませんでした。',
      'error.validation' => error.detail ?? '入力内容を確認してください。',
      'error.unsupported' => 'この機能は未実装です。',
      _ => 'エラーが発生しました。',
    };
  }
  return 'エラーが発生しました。';
}
