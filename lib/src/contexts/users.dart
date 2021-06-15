import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

import '../core/network.dart';
import '../core/session/session.dart';
import '../models/user.dart';

/// @classdesc Container for known users
/// @fires Users#userUpdated
class Users extends Stendo {
  Users({this.session, this.network, this.syncClient}) : super() {
    myself = User(null, null,
        session: session, network: network, syncClient: syncClient);
    myself.on('updated', (args) => emit('userUpdated', payload: args));
    myself.on('userSubscribed', (_) => emit('userSubscribed', payload: myself));
    myself.on('userUnsubscribed', (_) {
      emit('userUnsubscribed', payload: myself);
      myself.ensureFetched();
    });

    init();
  }

  void init() async {
    final links = await session.getSessionLinks();

    userUrl = links.usersUrl;

    final maxUserInfosToSubscribe = await session.getMaxUserInfosToSubscribe();

    fifoStackMaxLength = maxUserInfosToSubscribe;

    final data = await session.getUsersData();

    myself.identity = data['identity'];
    myself.entityName = data['user'];
    await myself.ensureFetched();
  }

  Map<String, dynamic> subscribedUsers = {};
  List fifoStack = [];
  int fifoStackMaxLength = 100;
  User myself;
  Session session;
  ConversationNetwork network;
  SyncClient syncClient;
  String userUrl;

  void handleUnsubscribeUser(User user) {
    if (subscribedUsers.containsKey(user.identity)) {
      subscribedUsers.remove(user.identity);
    }
    var foundItemIndex;
    final foundItem = fifoStack.firstWhere((item) {
      if (item == user.identity) {
        foundItemIndex = fifoStack.indexOf(item);
        return true;
      }
      return false;
    });
    if (foundItem != null) {
      fifoStack.removeRange(foundItemIndex, 1);
    }
    emit('userUnsubscribed', payload: user);
  }

  void handleSubscribeUser(user) {
    if (subscribedUsers.containsKey(user.identity)) {
      return;
    }
    if (fifoStack.length >= fifoStackMaxLength) {
      subscribedUsers[fifoStack.removeAt(0)].unsubscribe();
    }
    fifoStack.add(user.identity);
    subscribedUsers[user.identity] = user;
    emit('userSubscribed', payload: user);
  }

  /// Gets user, if it's in subscribed list - then return the user object from it,
  /// if not - then subscribes and adds user to the FIFO stack
  /// @returns {Future<User>} Fully initialized user
  Future getUser(String identity, {String entityName}) async {
    await session.getUsersData();
    await myself.ensureFetched();
    if (identity == myself.identity) {
      return myself;
    }
    final user = subscribedUsers[identity];
    if (user == null) {
      entityName ??= await getSyncUniqueName(identity);
      final user = User(identity, entityName,
          network: network, session: session, syncClient: syncClient);
      user.on('updated', (args) => emit('userUpdated', payload: args));
      user.on('userSubscribed', (_) => handleSubscribeUser(user));
      user.on('userUnsubscribed', (_) => handleUnsubscribeUser(user));
      await user.ensureFetched();
    }
    return user;
  }

  /// @returns {Future<List<User>>} returns list of subscribed User objects {@see User}
  Future getSubscribedUsers() async {
    await session.getUsersData();
    await myself.ensureFetched();
    final users = [myself];
    subscribedUsers.values.forEach((user) => users.add(user));
    return users;
  }

  /// @returns {Future<String>} User's sync unique name
  Future getSyncUniqueName(String identity) async {
    final url = UriBuilder(userUrl).addPathSegment(identity).build();
    final response = await network.get(url);
    return response.data['sync_unique_name'];
  }
}
