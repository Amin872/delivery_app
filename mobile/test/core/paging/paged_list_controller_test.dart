import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/paging/page_result.dart';
import 'package:delivery_app/core/paging/paged_list_controller.dart';

/// A fake paged source over ids 0..total-1, [pageSize] per page; the
/// cursor is the last id returned. Each request can be held open with
/// [gate] and failed with [failNext].
class _Source {
  _Source(this.total, {this.pageSize = 3});

  final int total;
  final int pageSize;
  final requests = <Object?>[];
  Completer<void>? gate;
  bool failNext = false;

  Future<PageResult<int>> fetch(Object? cursor) async {
    requests.add(cursor);
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failNext) {
      failNext = false;
      throw StateError('boom');
    }
    final start = cursor == null ? 0 : (cursor as int) + 1;
    final end = (start + pageSize).clamp(0, total);
    final items = [for (var i = start; i < end; i++) i];
    return PageResult(items: items, cursor: items.isEmpty ? cursor : items.last, hasMore: end < total);
  }
}

PagedListController<int> _controller(_Source source) =>
    PagedListController<int>(fetchPage: source.fetch, idOf: (i) => '$i');

void main() {
  test('first page, then each "load more" appends the next page until the end', () async {
    final source = _Source(7);
    final controller = _controller(source);

    await controller.refresh();
    expect(controller.items, [0, 1, 2]);
    expect(controller.hasLoaded, isTrue);
    expect(controller.hasMore, isTrue);

    await controller.loadMore();
    expect(controller.items, [0, 1, 2, 3, 4, 5]);
    await controller.loadMore();
    expect(controller.items, [0, 1, 2, 3, 4, 5, 6]);
    expect(controller.hasMore, isFalse);

    // At the end: no further request.
    await controller.loadMore();
    expect(source.requests, [null, 2, 5]);
  });

  test('an empty source loads as an empty, finished list', () async {
    final controller = _controller(_Source(0));
    await controller.refresh();
    expect(controller.items, isEmpty);
    expect(controller.hasLoaded, isTrue);
    expect(controller.hasMore, isFalse);
  });

  test('a second "load more" while one is in flight sends nothing', () async {
    final source = _Source(9);
    final controller = _controller(source);
    await controller.refresh();

    source.gate = Completer<void>();
    final first = controller.loadMore();
    expect(controller.isLoadingMore, isTrue);
    final second = controller.loadMore();
    source.gate!.complete();
    await Future.wait([first, second]);

    expect(source.requests, [null, 2]);
    expect(controller.items, [0, 1, 2, 3, 4, 5]);
  });

  test('a record repeated across pages is shown once', () async {
    var call = 0;
    final controller = PagedListController<int>(
      idOf: (i) => '$i',
      fetchPage: (cursor) async {
        call++;
        // The second page overlaps the first (e.g. a record's sort field
        // changed between requests).
        return call == 1
            ? const PageResult(items: [1, 2, 3], cursor: 3, hasMore: true)
            : const PageResult(items: [3, 4], cursor: 4, hasMore: false);
      },
    );
    await controller.refresh();
    await controller.loadMore();
    expect(controller.items, [1, 2, 3, 4]);
  });

  test('refresh (search/filter changed) drops a response from the previous query', () async {
    final source = _Source(9);
    final controller = _controller(source);

    source.gate = Completer<void>();
    final stale = controller.refresh();
    final staleGate = source.gate!;
    source.gate = null;
    final fresh = controller.refresh();
    await fresh;
    expect(controller.items, [0, 1, 2]);

    staleGate.complete();
    await stale;
    expect(controller.items, [0, 1, 2]);
    expect(controller.isLoading, isFalse);
  });

  test('a failed first page leaves nothing loaded; retry loads it', () async {
    final source = _Source(4)..failNext = true;
    final controller = _controller(source);

    await controller.refresh();
    expect(controller.hasLoaded, isFalse);
    expect(controller.error, isA<StateError>());
    expect(controller.items, isEmpty);

    await controller.retry();
    expect(controller.error, isNull);
    expect(controller.items, [0, 1, 2]);
  });

  test('a failed "load more" keeps the loaded records; retry continues from the same cursor', () async {
    final source = _Source(5);
    final controller = _controller(source);
    await controller.refresh();

    source.failNext = true;
    await controller.loadMore();
    expect(controller.error, isNotNull);
    expect(controller.items, [0, 1, 2]);
    expect(controller.hasMore, isTrue);

    await controller.retry();
    expect(controller.items, [0, 1, 2, 3, 4]);
    expect(source.requests, [null, 2, 2]);
  });

  test('replace and remove patch one loaded record without a reload', () async {
    final source = _Source(3);
    final controller = PagedListController<int>(fetchPage: source.fetch, idOf: (i) => '${i % 10}');
    await controller.refresh();

    controller.replace(11); // same id as 1
    expect(controller.items, [0, 11, 2]);
    controller.remove('0');
    expect(controller.items, [11, 2]);
    controller.replace(99); // not loaded: no-op
    expect(controller.items, [11, 2]);
    expect(source.requests, [null]);
  });

  test('nothing is applied after dispose', () async {
    final source = _Source(3)..gate = Completer<void>();
    final controller = _controller(source);
    final pending = controller.refresh();
    controller.dispose();
    source.gate!.complete();
    await pending; // completes without throwing on a disposed notifier
  });
}
