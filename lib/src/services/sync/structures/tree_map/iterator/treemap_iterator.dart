import '../models/tree_node.dart';
import '../tree.dart';

class TreeMapIterator<Key, Value> implements Iterator<Node<Key, Value>> {
  TreeMapIterator(this._map, {Key key}) {
    _init(key: key);
  }
  final TreeMap<Key, Value> _map;
  final List _nodes = [];
  Node<Key, Value> _currentNode;
  @override
  Node<Key, Value> get current => _currentNode;

  void _init({Key key}) {
    var currentNode = _map.root;
    while (currentNode != null) {
      if (_map.isEqual(key, currentNode.key) ||
          ((key == null) && currentNode.left == null)) {
        break;
      }
      if (_map.isLessThan(key, currentNode.key) || (key == null)) {
        currentNode = currentNode.left;
      } else {
        currentNode = currentNode.right;
      }
    }
    if (currentNode == null) {
      return null;
    }
    var fromLeft = true;
    for (;;) {
      if (fromLeft) {
        _nodes.add(currentNode);
        fromLeft = false;
        if (currentNode.right != null) {
          currentNode = currentNode.right;
          while (currentNode.left != null) {
            currentNode = currentNode.left;
          }
          fromLeft = true;
        } else if (currentNode.parent != null) {
          fromLeft = (currentNode.parent.left == currentNode);
          currentNode = currentNode.parent;
        } else {
          break;
        }
      } else if (currentNode.parent != null) {
        fromLeft = (currentNode.parent.left == currentNode);
        currentNode = currentNode.parent;
      } else {
        break;
      }
    }
    return;
  }

  @override
  bool moveNext() {
    if (_currentNode == null && _nodes.isNotEmpty) {
      _currentNode = _nodes.first;
      return _nodes.length > 1;
    } else if (_currentNode != null) {
      final index = _nodes.indexOf(_currentNode) + 1;
      _currentNode = _nodes[index];
      return _nodes.length > index + 1;
    }
    return false;
  }
}
