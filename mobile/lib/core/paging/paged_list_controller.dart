import 'package:flutter/foundation.dart';

import 'page_result.dart';

/// Fetches the page that follows [cursor] (null = the first page).
typedef PageFetcher<T> = Future<PageResult<T>> Function(Object? cursor);

/// State for one cursor-paginated list: the records loaded so far, whether
/// more exist, and the outcome of the latest request.
///
/// Pages are one-time reads appended in order, never a live listener, so
/// the cursor always points into a stable result set:
/// - only one request runs at a time (a "Load more" tapped twice sends one);
/// - [refresh] (search or filter changed) starts a new generation, and a
///   response from an older generation is dropped instead of being mixed
///   into the new list;
/// - records are de-duplicated by [idOf] when a page is appended, so a
///   record that moved between pages (its sort field changed) shows once;
/// - a failed first load leaves nothing loaded ([hasLoaded] false), a
///   failed "Load more" keeps every record already shown.
///
/// Records changed by an admin action are patched in place with [replace]
/// or [remove] rather than reloading the whole list.
class PagedListController<T> extends ChangeNotifier {
  PagedListController({required this.fetchPage, required this.idOf});

  final PageFetcher<T> fetchPage;
  final String Function(T item) idOf;

  List<T> _items = const [];
  Object? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _hasLoaded = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;

  List<T> get items => _items;
  bool get hasMore => _hasMore;
  bool get isLoading => _loading;

  /// True once the first page of the current generation has arrived.
  bool get hasLoaded => _hasLoaded;

  /// A "Load more" is in flight (the first page already arrived).
  bool get isLoadingMore => _loading && _hasLoaded;

  /// The error from the latest request, cleared by the next one.
  Object? get error => _error;

  /// Drops everything loaded and fetches the first page again.
  Future<void> refresh() {
    _generation++;
    _items = const [];
    _cursor = null;
    _hasMore = true;
    _hasLoaded = false;
    _error = null;
    _loading = false;
    return _load();
  }

  /// Fetches the next page; a no-op while a request is in flight, before
  /// the first page arrived, or once the end was reached.
  Future<void> loadMore() {
    if (_loading || !_hasLoaded || !_hasMore) return Future.value();
    return _load();
  }

  /// Retries whatever failed: the first page, or the next one.
  Future<void> retry() => _hasLoaded ? loadMore() : refresh();

  /// Replaces the loaded record with [item]'s id (no-op if not loaded).
  void replace(T item) {
    final id = idOf(item);
    final index = _items.indexWhere((existing) => idOf(existing) == id);
    if (index < 0) return;
    _items = [..._items]..[index] = item;
    _notify();
  }

  /// Removes the loaded record with [id] (e.g. it no longer matches the
  /// active filter). The cursor is unaffected.
  void remove(String id) {
    final next = _items.where((item) => idOf(item) != id).toList();
    if (next.length == _items.length) return;
    _items = next;
    _notify();
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = _generation;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await fetchPage(_cursor);
      if (generation != _generation || _disposed) return;
      final seen = {for (final item in _items) idOf(item)};
      _items = [
        ..._items,
        for (final item in page.items)
          if (seen.add(idOf(item))) item,
      ];
      _cursor = page.cursor;
      _hasMore = page.hasMore;
      _hasLoaded = true;
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _error = error;
    } finally {
      if (generation == _generation && !_disposed) {
        _loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
