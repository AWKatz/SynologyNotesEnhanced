import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shelf.dart';
import 'app_mode_provider.dart';

final shelvesProvider = FutureProvider<List<Shelf>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listShelves();
});
