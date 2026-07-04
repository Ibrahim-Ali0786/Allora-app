import 'package:matrix/matrix.dart';

/// A ready-to-load media source: a URL plus the auth headers to fetch it.
class MediaSource {
  final String url;
  final Map<String, String> headers;
  const MediaSource(this.url, this.headers);
}

/// Builds **authenticated** Matrix media URLs.
///
/// WHY THIS EXISTS: modern Synapse (1.100+, and mandatory since the
/// authenticated-media rollout) rejects the old unauthenticated
/// `/_matrix/media/v3/{thumbnail,download}` endpoints — that's the
/// `statusCode: 404` you get when `Image.network` tries a plain
/// `mxcUri.getThumbnail(client)` URL. The current spec requires:
///
///   GET /_matrix/client/v1/media/thumbnail/{server}/{mediaId}
///   GET /_matrix/client/v1/media/download/{server}/{mediaId}
///   Authorization: Bearer <access token>
///
/// `Image.network(src.url, headers: src.headers)` and `VideoPlayerController`
/// (via `httpHeaders`) both accept the Bearer header, so this one helper
/// fixes photos, videos and avatars everywhere.
class MatrixMedia {
  MatrixMedia._();

  /// Extract the mxc URI string from any message event, handling both
  /// unencrypted (`content.url`) and encrypted (`content.file.url`) layouts.
  static String? mxcOf(Event event) {
    final url = event.content['url'];
    if (url is String && url.startsWith('mxc://')) return url;
    final file = event.content['file'];
    if (file is Map && file['url'] is String) {
      final u = file['url'] as String;
      if (u.startsWith('mxc://')) return u;
    }
    return null;
  }

  static ({String server, String mediaId})? _parse(String? mxc) {
    if (mxc == null || !mxc.startsWith('mxc://')) return null;
    final uri = Uri.tryParse(mxc);
    if (uri == null) return null;
    final server = uri.host;
    final mediaId =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (server.isEmpty || mediaId.isEmpty) return null;
    return (server: server, mediaId: mediaId);
  }

  static String _base(Client client) {
    final base = client.homeserver?.toString() ?? '';
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  static Map<String, String> _authHeaders(Client client) {
    final token = client.accessToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// Cropped thumbnail source, or null if the mxc can't be resolved.
  static MediaSource? thumbnail(
    Client client,
    String? mxc, {
    int width = 800,
    int height = 800,
    String method = 'crop',
  }) {
    final parts = _parse(mxc);
    if (parts == null) return null;
    final base = _base(client);
    if (base.isEmpty) return null;
    final url = '$base/_matrix/client/v1/media/thumbnail/'
        '${parts.server}/${parts.mediaId}'
        '?width=$width&height=$height&method=$method&animated=false';
    return MediaSource(url, _authHeaders(client));
  }

  /// Full-size download source (images opened full-screen, video, files).
  static MediaSource? download(Client client, String? mxc) {
    final parts = _parse(mxc);
    if (parts == null) return null;
    final base = _base(client);
    if (base.isEmpty) return null;
    final url = '$base/_matrix/client/v1/media/download/'
        '${parts.server}/${parts.mediaId}';
    return MediaSource(url, _authHeaders(client));
  }
}
