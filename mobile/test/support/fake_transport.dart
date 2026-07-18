import 'package:skyoverhead/src/data/http.dart';

/// A configurable [HttpTransport] fake for tests: returns a canned
/// response or throws a preset error, and records the last URL requested.
class FakeTransport implements HttpTransport {
  final HttpResponse? _response;
  final Object? _error;

  Uri? lastUrl;
  Map<String, String>? lastHeaders;

  FakeTransport.reply(this._response) : _error = null;

  FakeTransport.fail(this._error) : _response = null;

  factory FakeTransport.json(int status, String body) =>
      FakeTransport.reply(HttpResponse(status, const {}, body));

  @override
  Future<HttpResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 12),
    int maxBody = 262144,
  }) async {
    lastUrl = url;
    lastHeaders = headers;
    if (_error != null) throw _error;
    return _response!;
  }
}
