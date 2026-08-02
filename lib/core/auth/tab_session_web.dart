import 'dart:html' as html;

const _kTabUid = 'mt_tab_auth_uid';

/// Web sessionStorage — sekme/pencereye özel (localStorage paylaşılmaz).
void tabSetUid(String uid) {
  html.window.sessionStorage[_kTabUid] = uid;
}

String? tabGetUid() => html.window.sessionStorage[_kTabUid];

void tabClearUid() {
  html.window.sessionStorage.remove(_kTabUid);
}
