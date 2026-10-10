import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// Likes, saves, "I'm going" and follows, shared across every screen so a tap
/// on the trip page shows up on the feed card and the profile immediately.
/// Updates are optimistic and roll back if the server disagrees.
class Reactions extends ChangeNotifier {
  Reactions(this.api);

  static late Reactions instance;

  final Api api;
  final Map<String, ({bool saved, int saves})> _saves = {};
  final Map<String, ({bool liked, int likes})> _likes = {};
  final Map<String, ({bool going, int count})> _going = {};
  final Map<String, ({bool following, int followers})> _follows = {};

  /// Bumped whenever saved/going/follow sets change, so lists can refresh.
  int version = 0;

  Creator applyCreator(Creator c) {
    final f = _follows[c.id];
    return f == null ? c : c.copyWith(isFollowing: f.following, followers: f.followers);
  }

  Journey apply(Journey j) {
    final s = _saves[j.id];
    final l = _likes[j.id];
    final g = _going[j.id];
    return j.copyWith(
      saved: s?.saved,
      saves: s?.saves,
      liked: l?.liked,
      likes: l?.likes,
      isGoing: g?.going,
      goingCount: g?.count,
      creator: applyCreator(j.creator),
    );
  }

  Future<T> _optimistic<K, T>(Map<String, K> map, String id, K next, Future<K> Function() call, T Function(K) result) async {
    final previous = map[id];
    map[id] = next;
    version++;
    notifyListeners();
    try {
      final confirmed = await call();
      map[id] = confirmed;
      notifyListeners();
      return result(confirmed);
    } catch (e) {
      if (previous == null) {
        map.remove(id);
      } else {
        map[id] = previous;
      }
      version++;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> toggleSave(Journey j) {
    final c = apply(j);
    return _optimistic(_saves, j.id, (saved: !c.saved, saves: (c.saves + (c.saved ? -1 : 1)).clamp(0, 1 << 30)), () => api.toggleSave(j.id), (r) => r.saved);
  }

  Future<bool> toggleLike(Journey j) {
    final c = apply(j);
    return _optimistic(_likes, j.id, (liked: !c.liked, likes: c.likes + (c.liked ? -1 : 1)), () => api.toggleLike(j.id), (r) => r.liked);
  }

  Future<bool> toggleGoing(Journey j) {
    final c = apply(j);
    return _optimistic(
      _going,
      j.id,
      (going: !c.isGoing, count: (c.goingCount + (c.isGoing ? -1 : 1)).clamp(0, 1 << 30)),
      () async {
        final r = await api.toggleGoing(j.id);
        return (going: r.going, count: r.goingCount);
      },
      (r) => r.going,
    );
  }

  Future<bool> toggleFollow(Creator creator) {
    final c = applyCreator(creator);
    return _optimistic(
      _follows,
      creator.id,
      (following: !c.isFollowing, followers: (c.followers + (c.isFollowing ? -1 : 1)).clamp(0, 1 << 30)),
      () => api.toggleFollow(creator.id),
      (r) => r.following,
    );
  }
}
