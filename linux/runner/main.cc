#include "my_application.h"

#include <stdlib.h>

int main(int argc, char** argv) {
  // AT-SPI アクセシビリティブリッジを無効化する (plan §51)。
  // 有効なままだと、AT-SPI レジストリが稼働する通常のデスクトップセッションで
  // テキスト入力欄にフォーカスした際、Flutter GTK エンベーダのブリッジが
  // AT-SPI バス経由の同期問い合わせ (GetExtents) で自己デッドロックし、
  // UI スレッドが D-Bus のタイムアウト (25 秒) までブロックされる実測不具合が
  // あるため。スクリーンリーダー連携は使えなくなるが、本アプリの利用形態では
  // フリーズ回避を優先する。利用者が明示的に設定済みの場合は上書きしない。
  setenv("NO_AT_BRIDGE", "1", 0);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
