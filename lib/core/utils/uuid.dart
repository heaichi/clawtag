import 'dart:math';
import 'dart:typed_data';

final _random = Random.secure();

/// Generates a time-sortable UUID v7 string conforming to RFC 9562.
///
/// ## Byte layout (16 bytes)
/// ```
/// [ 0 … 5 ]  Unix-millisecond timestamp (48 bits, big-endian)
/// [ 6 … 15]  Random bytes (with version/variant nibbles applied)
/// ```
///
/// - **Byte 6, high nibble** → set to `0x70` (UUID version 7).
/// - **Byte 8, high nibble** → set to `0x80` (IETF variant 10xx).
///
/// Because the timestamp occupies the most-significant bytes, UUIDs
/// generated close together sort chronologically — ideal for database
/// primary keys.
String generateUuidV7() {
  // Snapshot the current UTC timestamp in milliseconds
  final ts = DateTime.now().millisecondsSinceEpoch;
  final bytes = Uint8List(16);

  // Encode timestamp into the first 6 bytes (48 bits, big-endian)
  bytes[0] = (ts >> 40) & 0xFF;
  bytes[1] = (ts >> 32) & 0xFF;
  bytes[2] = (ts >> 24) & 0xFF;
  bytes[3] = (ts >> 16) & 0xFF;
  bytes[4] = (ts >> 8) & 0xFF;
  bytes[5] = ts & 0xFF;

  // Fill bytes 6–15 with random data (16 - 6 = 10 bytes of randomness)
  for (int i = 6; i < 16; i++) {
    bytes[i] = _random.nextInt(256);
  }

  // Apply UUID v7 version marker (clear top nibble, set to 0x70 → 7xxx)
  bytes[6] = (bytes[6] & 0x0F) | 0x70;
  // Apply IETF variant marker (clear top 2 bits, set to 10xx)
  bytes[8] = (bytes[8] & 0x3F) | 0x80;

  return _formatUuid(bytes);
}

/// Formats 16 raw bytes as an 8-4-4-4-12 hex string
/// (e.g. `017f22e2-79b0-7cc3-98c4-dc0c0c07398f`).
String _formatUuid(Uint8List bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}'
      '-${hex.substring(8, 12)}'
      '-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}'
      '-${hex.substring(20)}';
}

/// Derives a deterministic, positive 31-bit integer from [uuid] for use
/// as a platform notification ID.  Uses the final 8 hex characters (the
/// random segment of a UUID v7) so IDs stay stable across restarts.
///
/// The ID space is 0 … 2^31-1 (fits Android's `int` notification id).
int notificationIdFromUuid(String uuid) {
  final clean = uuid.replaceAll('-', '');
  final suffix = clean.length >= 12 ? clean.substring(clean.length - 8) : clean;
  final hash = suffix.codeUnits.fold<int>(0, (h, c) => ((h << 5) + h) ^ c);
  return hash & 0x7FFFFFFF; // keep it positive (31 bits)
}
