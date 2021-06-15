import '../models/tree_node.dart';
import '../tree.dart';

class TreeMapReverseIterator<Key, Value> implements Iterator<Node<Key, Value>> {
  TreeMapReverseIterator(this._map, {Key key}) {
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
          ((key == null) && currentNode.right == null)) {
        break;
      }
      if (!_map.isLessThan(key, currentNode.key) || (key == null)) {
        currentNode = currentNode.right;
      } else {
        currentNode = currentNode.left;
      }
    }
    if (currentNode == null) {
      return;
    }
    var fromRight = true;
    for (;;) {
      if (fromRight) {
        _nodes.add(currentNode);
        fromRight = false;
        if (currentNode.left != null) {
          currentNode = currentNode.left;
          while (currentNode.right != null) {
            currentNode = currentNode.right;
          }
          fromRight = true;
        } else if (currentNode.parent != null) {
          fromRight = (currentNode.parent.right == currentNode);
          currentNode = currentNode.parent;
        } else {
          break;
        }
      } else if (currentNode.parent != null) {
        fromRight = (currentNode.parent.right == currentNode);
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
