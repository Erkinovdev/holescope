/// Ключи фраз помощницы «Холи». Тексты и озвучка — в assets/holi (генерируются tool/make_holi_audio.py), в коде текстов нет.
enum HoliPhrase {
  listening('listening'),
  wakeYes('wake_yes'),
  wakeListen('wake_listen'),
  markPothole('mark_pothole'),
  markDeep('mark_deep'),
  markBump('mark_bump'),
  markManhole('mark_manhole'),
  markCancel('mark_cancel'),
  markCancelNone('mark_cancel_none'),
  thanks('thanks'),
  askConfirm('ask_confirm'),
  confirmYes('confirm_yes'),
  confirmNo('confirm_no'),
  noAnswer('no_answer'),
  aheadDeep('ahead_deep'),
  aheadBump('ahead_bump'),
  repeat('repeat'),
  unknown('unknown'),
  kmSmooth('km_smooth'),
  kmRough('km_rough'),
  tripDone('trip_done'),
  errMic('err_mic'),
  errSpeech('err_speech'),
  errNet('err_net'),
  okEnd('ok_end'),
  help('help'),
  notPothole('mark_not_pothole'),

  /// Фразы с расстоянием: реальный ключ — `ahead_pothole_<метры>`, см. [distanceKey].
  aheadPothole('ahead_pothole'),
  aheadRough('ahead_rough');

  const HoliPhrase(this.key);
  final String key;

  /// Расстояния, для которых записаны фразы.
  static const distances = [50, 100, 150, 200, 250, 300];

  /// Ближайшее записанное расстояние (50…300 м).
  static int nearestDistance(int meters) {
    var best = distances.first;
    for (final d in distances) {
      if ((d - meters).abs() < (best - meters).abs()) best = d;
    }
    return best;
  }

  /// Ключ файла для фразы с расстоянием, например `ahead_pothole_100`.
  String distanceKey(int meters) => '${key}_${nearestDistance(meters)}';
}
