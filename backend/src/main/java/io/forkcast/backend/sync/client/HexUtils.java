package io.forkcast.backend.sync.client;

public final class HexUtils {

  private HexUtils() {

  }

  public static String toHex(long value) {
    return "0x" + Long.toHexString(value);
  }

  public static long hexToLong(String hex) {
    if (hex == null || !hex.startsWith("0x")) {
      throw new IllegalArgumentException("invalid hex: " + hex);
    }
    return Long.parseUnsignedLong(hex.substring(2), 16);
  }
}
