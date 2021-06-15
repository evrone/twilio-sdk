class Node<K, V> {
  Node(this.key, this.value, {this.balanceFactor = 0});
  int balanceFactor;
  K key;
  V value;
  Node parent;
  Node left;
  Node right;

  bool get isRoot => parent == null;
  bool get isLeaf => left == null && right == null;
  bool get isLeftChild => parent.left == this;
  void update(V value) {
    this.value = value;
  }

  void replace({Node<K, V> target, Node<K, V> replacement}) {
    if (target == null) {
      return;
    }
    if (left == replacement) {
      left = replacement;
    } else if (right == replacement) {
      right = replacement;
    }
  }
}
