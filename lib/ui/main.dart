import 'package:flutter/material.dart';
import 'ffi.dart';
import 'package:ffi/ffi.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: TodoPage());
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    initCore();
  }

  List<Map<String, dynamic>> fetchTodos() {
    final count = getTodoCount();
    final list = <Map<String, dynamic>>[];

    for (var i = 0; i < count; i++) {
      final raw = getTodo(i).toDartString();
      final parts = raw.split('|');
      list.add({
        'id': int.parse(parts[0]),
        'done': parts[1] == '1',
        'title': parts[2],
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final todos = fetchTodos();

    return Scaffold(
      appBar: AppBar(title: const Text('TODO FFI')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: controller)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final ptr = controller.text.toNativeUtf8();
                    addTodo(ptr);
                    malloc.free(ptr);
                    controller.clear();
                    setState(() {});
                  },
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: todos.length,
              itemBuilder: (_, i) {
                final t = todos[i];
                return ListTile(
                  title: Text(
                    t['title'],
                    style: TextStyle(
                      decoration:
                          t['done'] ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  leading: Checkbox(
                    value: t['done'],
                    onChanged: (_) {
                      toggleTodo(t['id']);
                      setState(() {});
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      removeTodo(t['id']);
                      setState(() {});
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
