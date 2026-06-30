import 'dart:html' as html;
import 'dart:async';

Future<void> injectGoogleMaps(String apiKey) async {
  if (apiKey.isEmpty) return;
  if (html.document.getElementById('google-maps-script') != null) {
    return;
  }

  final completer = Completer<void>();
  final script = html.ScriptElement()
    ..id = 'google-maps-script'
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey'
    ..defer = true
    ..async = true;
  
  script.onLoad.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  
  script.onError.listen((_) {
    if (!completer.isCompleted) completer.completeError('Error loading Google Maps API');
  });

  html.document.head!.append(script);
  return completer.future;
}
