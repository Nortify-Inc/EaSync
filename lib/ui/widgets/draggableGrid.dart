import 'package:flutter/material.dart';

class DraggableGrid<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(T item) itemBuilder;
  final void Function(List<T>) onReorder;

  const DraggableGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
  });

  @override
  State<DraggableGrid<T>> createState() => _DraggableGridState<T>();
}

class _DraggableGridState<T> extends State<DraggableGrid<T>> {
  late List<T> internal;

  @override
  void initState() {
    super.initState();
    internal = List.from(widget.items);
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      itemCount: (internal.length / 2).ceil(),
      onReorder: _onReorder,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, index) {
        final firstIndex = index * 2;
        final secondIndex = firstIndex + 1;

        return Padding(
          key: ValueKey(index),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(child: widget.itemBuilder(internal[firstIndex])),
              const SizedBox(width: 12),
              if (secondIndex < internal.length)
                Expanded(child: widget.itemBuilder(internal[secondIndex]))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        );
      },
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    final oldItemIndex = oldIndex * 2;
    var newItemIndex = newIndex * 2;

    if (newItemIndex > oldItemIndex) {
      newItemIndex -= 2;
    }

    if (oldItemIndex < 0 || oldItemIndex >= internal.length) return;
    if (newItemIndex < 0 || newItemIndex >= internal.length) return;

    setState(() {
      final item = internal.removeAt(oldItemIndex);
      internal.insert(newItemIndex, item);
    });

    widget.onReorder(internal);
  }
}
