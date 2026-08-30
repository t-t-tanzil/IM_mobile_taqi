/// Generates a reasonably unique identifier for batches/images without
/// pulling in a dedicated uuid package for a single call site.
class IdGenerator {
  const IdGenerator._();

  static String generate() => DateTime.now().microsecondsSinceEpoch.toString();
}
