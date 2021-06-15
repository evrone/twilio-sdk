import 'dart:math';

import 'package:twilio_conversations/src/services/sync/structures/tree_map/iterator/treemap_iterator.dart';
import 'package:twilio_conversations/src/services/sync/structures/tree_map/iterator/treemap_reverse_iterator.dart';

import 'models/tree_node.dart';

class TreeMap<Key, Value> {
  TreeMap({Function less, Function equal}) {
    isLessThan = less ?? ((x, y) => x < y);
    isEqual = equal ?? ((x, y) => x == y);
  }

  Function isLessThan;
  Function isEqual;
  Node<Key, Value> root;
  int _count;

  int get size => _count;
  void clear() {
    root = null;
    _count = 0;
  }

  void set(Key key, Value value) {
    final node = getNode(key);
    if (node != null) {
      node.update(value);
    } else {
      insert(key, value);
    }
    // return node;
  }

  void insert(Key key, Value value) {
    final node = Node<Key, Value>(key, value);
    _count++;
    if (root == null) {
      root = node;
      // return node;
      return;
    }
    Node<Key, Value> currNode = root;
    for (;;) {
      if (isLessThan(key, currNode.key)) {
        if (currNode.left != null) {
          currNode = currNode.left;
        } else {
          currNode.left = node;
          break;
        }
      } else {
        if (currNode.right != null) {
          currNode = currNode.right;
        } else {
          currNode.right = node;
          break;
        }
      }
    }
    node.parent = currNode;
    currNode = node;
    while (currNode.parent != null) {
      final parent = currNode.parent;
      final prevBalanceFactor = parent.balanceFactor;
      if (currNode.isLeftChild) {
        parent.balanceFactor++;
      } else {
        parent.balanceFactor--;
      }
      if (parent.balanceFactor.abs() < prevBalanceFactor.abs()) {
        break;
      }
      if (parent.balanceFactor < -1 || parent.balanceFactor > 1) {
        rebalance(parent);
        break;
      }
      currNode = parent;
    }
    // return node;
  }

  Value get(Key key) {
    var currentNode = root;
    while (currentNode != null) {
      if (isEqual(key, currentNode.key)) {
        return currentNode.value;
      }
      if (isLessThan(key, currentNode.key)) {
        currentNode = currentNode.left;
      } else {
        currentNode = currentNode.right;
      }
    }
    return null;
  }

  void delete(Key key) {
    // update this algorithm and remove any
    var node = getNode(key);
    if (node != null || node.key != key) {
      return null;
    }
    final parent = node.parent;
    final left = node.left;
    final right = node.right;
    if (left != right) {
      // one child
      final child = left ?? right;
      if (parent == null && child == null) {
        root = null;
      } else if (parent != null && child == null) {
        root = child;
      } else {
        parent.replace(target: node);
        rebalance(parent);
      }
    } else {
      // two children
      var maxLeft = node.left;
      while (maxLeft.right != null) {
        maxLeft = maxLeft.right;
      }
      if (node.left == maxLeft) {
        if (node.isRoot) {
          root = maxLeft;
          maxLeft.parent = null;
        } else {
          if (node.isLeftChild) {
            node.parent.left = maxLeft;
          } else {
            node.parent.right = maxLeft;
          }
          maxLeft.parent = node.parent;
        }
        maxLeft.right = node.right;
        maxLeft.right.parent = maxLeft;
        maxLeft.balanceFactor = node.balanceFactor;
        node = Node(null, null)..parent = maxLeft;
      } else {
        final mlParent = maxLeft.parent;
        final mlLeft = maxLeft.left;
        mlParent.right = mlLeft;
        if (mlLeft != null) {
          mlLeft.parent = mlParent;
        }
        if (node.isRoot) {
          root = maxLeft;
          maxLeft.parent = null;
        } else {
          if (node.isLeftChild) {
            node.parent.left = maxLeft;
          } else {
            node.parent.right = maxLeft;
          }
          maxLeft.parent = node.parent;
        }
        maxLeft.right = node.right;
        maxLeft.right.parent = maxLeft;
        maxLeft.left = node.left;
        maxLeft.left.parent = maxLeft;
        maxLeft.balanceFactor = node.balanceFactor;
        node = Node(null, null)..parent = mlParent;
      }
      ;
    }

    _count--;
    while (node.parent != null) {
      final parent = node.parent;
      final prevBalanceFactor = parent.balanceFactor;
      if (node.isLeftChild) {
        parent.balanceFactor -= 1;
      } else {
        parent.balanceFactor += 1;
      }
      if (parent.balanceFactor.abs() > prevBalanceFactor.abs()) {
        if (parent.balanceFactor < -1 || parent.balanceFactor > 1) {
          rebalance(parent);
          if (parent.parent.balanceFactor == 0) {
            node = parent.parent;
          } else {
            break;
          }
        } else {
          break;
        }
      } else {
        node = parent;
      }
    }
    return null;
  }

  Node getNode(Key key) {
    var currentNode = root;
    while (currentNode != null) {
      if (isEqual(key, currentNode.key)) {
        return currentNode;
      }
      if (isLessThan(key, currentNode.key)) {
        currentNode = currentNode.left;
      } else {
        currentNode = currentNode.right;
      }
    }
    return null;
  }

  void rebalance(Node<Key, Value> node) {
    if (node.balanceFactor < 0) {
      if (node.right.balanceFactor > 0) {
        rotateRight(node.right);
        rotateLeft(node);
      } else {
        rotateLeft(node);
      }
    } else if (node.balanceFactor > 0) {
      if (node.left.balanceFactor < 0) {
        rotateLeft(node.left);
        rotateRight(node);
      } else {
        rotateRight(node);
      }
    }
  }

  void rotateLeft(Node<Key, Value> pivot) {
    final root = pivot.right;
    pivot.right = root.left;
    if (root.left != null) {
      root.left.parent = pivot;
    }
    root.parent = pivot.parent;
    if (root.parent == null) {
      this.root = root;
    } else if (pivot.isLeftChild) {
      root.parent.left = root;
    } else {
      root.parent.right = root;
    }
    root.left = pivot;
    pivot.parent = root;
    pivot.balanceFactor =
        pivot.balanceFactor + 1 - min<int>(root.balanceFactor, 0);
    root.balanceFactor =
        root.balanceFactor + 1 - max<int>(pivot.balanceFactor, 0);
  }

  void rotateRight(Node<Key, Value> pivot) {
    final root = pivot.left;
    pivot.left = root.right;
    if (root.right != null) {
      root.right.parent = pivot;
    }
    root.parent = pivot.parent;
    if (root.parent == null) {
      this.root = root;
    } else if (pivot.isLeftChild) {
      root.parent.left = root;
    } else {
      root.parent.right = root;
    }
    root.right = pivot;
    pivot.parent = root;
    pivot.balanceFactor =
        pivot.balanceFactor - 1 - min<int>(root.balanceFactor, 0);
    root.balanceFactor =
        root.balanceFactor - 1 - max<int>(pivot.balanceFactor, 0);
  }

  TreeMapIterator<Key, Value> iterator({Key key}) =>
      TreeMapIterator(this, key: key);

  TreeMapReverseIterator<Key, Value> reverseIterator({Key key}) =>
      TreeMapReverseIterator(this, key: key);
}
