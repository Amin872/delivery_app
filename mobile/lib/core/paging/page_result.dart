/// Records per admin list page — one server request per "Load more".
const kAdminPageSize = 25;

/// One page of a cursor-paginated query.
///
/// [cursor] is opaque to callers (in practice the last Firestore document
/// snapshot of the page): it's handed back unchanged to fetch the page that
/// follows. [hasMore] is decided by asking the server for one record more
/// than the page holds, so a list never shows a "Load more" that would
/// return nothing.
class PageResult<T> {
  const PageResult({required this.items, required this.cursor, required this.hasMore});

  final List<T> items;
  final Object? cursor;
  final bool hasMore;

  /// Same page position (cursor, hasMore) with [items] transformed — e.g.
  /// joined with records from another collection.
  PageResult<R> withItems<R>(List<R> items) => PageResult(items: items, cursor: cursor, hasMore: hasMore);
}
