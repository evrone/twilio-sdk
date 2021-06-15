import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/core/network.dart';
import 'package:twilio_conversations/src/core/session/session.dart';
import 'package:twilio_conversations/src/enum/conversations/user_subscribtion_state.dart';
import 'package:twilio_conversations/src/enum/conversations/user_update_reason.dart';
import 'package:twilio_conversations/src/enum/sync/open_mode.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_map/sync_map.dart';

class UpdatedEventArgs {
  UpdatedEventArgs({this.updateReasons, this.user});
  User user;
  List<UserUpdateReason> updateReasons;
}

class UserState {
  UserState(
      {this.identity,
      this.attributes,
      this.entityName,
      this.friendlyName,
      this.notifiable,
      this.online});
  String identity;
  String entityName;
  String friendlyName;
  Map<String, dynamic> attributes;
  bool online;
  bool notifiable;
}

Map<String, dynamic> parseAttributes(String rawAttributes) {
  var attributes = {};

  try {
    attributes = json.decode(rawAttributes);
  } catch (e) {
    // warn(warningMessage, e);
  }

  return attributes;
}

/// @classdesc Extended user information.
/// Note that <code>isOnline</code> and <code>isNotifiable</code> properties are eligible
/// to use only if reachability is enabled.
/// You may check if it is enabled by reading value of {@link Client}'s <code>reachabilityEnabled</code> property.
///
/// @property [String] identity - User identity
/// @property [String] friendlyName - User friendly name, null if not set
/// @property {any} attributes - Object with custom attributes for user
/// @property {Boolean} isOnline - User real-time conversation connection status
/// @property {Boolean} isNotifiable - User push notification registration status
/// @property {Boolean} isSubscribed - Check if this user receives real-time status updates
///
/// @fires User#updated
/// @fires User#userSubscribed
/// @fires User#userUnsubscribed
///
/// @constructor
/// @param [String] identity - Identity of user
/// @param [String] entityId - id of user's object
/// @param {Object} datasync - datasync service
/// @param {Object} session - session service
class User extends Stendo {
  /// The update reason for <code>updated</code> event emitted on User
  /// @typedef {('friendlyName' | 'attributes' | 'reachabilityOnline' | 'reachabilityNotifiable')} User#UpdateReason
  User(String identity, String entityName,
      {this.session, this.network, this.syncClient})
      : super() {
    subscribed = UserSubscriptionState.initializing;
    setMaxListeners(0);

    state = UserState(
        identity: identity,
        entityName: entityName,
        friendlyName: null,
        attributes: {},
        online: null,
        notifiable: null);
  }

  UserSubscriptionState subscribed;
  SyncMap entity;

  Session session;
  ConversationNetwork network;
  SyncClient syncClient;
  Future promiseToFetch;

  String get identity => state.identity;

  set identity(String identity) {
    state.identity = identity;
  }

  set entityName(String name) {
    state.entityName = name;
  }

  get attributes => state.attributes;

  String get friendlyName => state.friendlyName;

  bool get isOnline => state.online;

  bool get isNotifiable => state.notifiable;

  bool get isSubscribed => subscribed == 'subscribed';

  UserState state;

  // Handles service updates
  void _update(String key, value) {
    final updateReasons = [];
    // debug('User for', state.identity, 'updated:', key, value);
    switch (key) {
      case 'friendlyName':
        if (state.friendlyName != value.value) {
          updateReasons.add(UserUpdateReason.friendlyName);
          state.friendlyName = value.value;
        }
        break;
      case 'attributes':
        final updateAttributes = parseAttributes(value.value);
        if (state.attributes == updateAttributes) {
          state.attributes = updateAttributes;
          updateReasons.add(UserUpdateReason.attributes);
        }
        break;
      case 'reachability':
        if (state.online != value.online) {
          state.online = value.online;
          updateReasons.add(UserUpdateReason.reachabilityOnline);
        }
        if (state.notifiable != value.notifiable) {
          state.notifiable = value.notifiable;
          updateReasons.add(UserUpdateReason.reachabilityNotifiable);
        }
        break;
      default:
        return;
    }
    if (updateReasons.isNotEmpty) {
      emit('updated', payload: {'user': this, 'updateReasons': updateReasons});
    }
  }

  // Fetch reachability info
  Future _updateReachabilityInfo(SyncMap map, Function update) async {
    if (!session.reachabilityEnabled) {
      return Future.value(null);
    }
    final info = await map.get('reachability');
    return update(info);
    // .catch(err) {
    //   // warn('Failed to get reachability info for ', state.identity, err); });
  }

  // Fetch user
  Future<User> _fetch() async {
    if (state.entityName == null) {
      return this;
    }
    final map = await syncClient
        .map(
            id: state.entityName,
            includeItems: true,
            mode: OpenMode.openExisting)
        .then((map) async {
      entity = map;
      map.on('itemUpdated', (args) {
        // debug(state.entityName + ' (' + state.identity + ') itemUpdated: ' + args.item.key);
        _update(args.item.key, args.item.data);
      });
      await map.get('friendlyName').then((item) {
        _update(item.key, item.data);
      });
      await map.get('attributes').then((item) {
        _update(item.key, item.data);
      });

      await _updateReachabilityInfo(
          map, (item) => _update(item.key, item.data));
    });

    // debug('Fetched for', identity);
    subscribed = UserSubscriptionState.subscribed;
    emit('userSubscribed', payload: this);
    return this;
  }

  Future<User> ensureFetched() {
    return promiseToFetch ?? _fetch();
  }

  /// Updates user attributes.
  /// @param {any} attributes new attributes for User.
  /// @returns {Future<User>}
  Future<User> updateAttributes(attributes) async {
    if (subscribed == UserSubscriptionState.unsubscribed) {
      throw Exception('Can\'t modify unsubscribed object');
    }
    await session.addCommand('editUserAttributes',
        {'username': state.identity, 'attributes': json.encode(attributes)});
    return this;
  }

  /// Update Users friendlyName.
  /// @param {String|null} friendlyName - Updated friendlyName
  /// @returns {Future<User>}
  Future<User> updateFriendlyName(String friendlyName) async {
    if (subscribed == UserSubscriptionState.unsubscribed) {
      throw Exception('Can\'t modify unsubscribed object');
    }
    await session.addCommand('editUserFriendlyName',
        {'username': state.identity, 'friendlyName': friendlyName});
    return this;
  }

  /// Removes User from subscription list.
  /// @returns {Future<void>} Promise of completion
  Future<void> unsubscribe() async {
    if (promiseToFetch != null) {
      await promiseToFetch;
      entity.close();
      promiseToFetch = null;
      subscribed = UserSubscriptionState.unsubscribed;
      emit('userUnsubscribed', payload: this);
    }
  }
}
// __decorate([
// twilio_sdk_type_validator_1.validateTypesAsync(['String', 'int', 'bool', 'object', twilio_sdk_type_validator_1.literal(null)]),
// __metadata('design:type', Function),
// __metadata('design:paramtypes', [Object]),
// __metadata('design:returntype', Promise)
// ], User.prototype, 'updateAttributes', null);
// __decorate([
// twilio_sdk_type_validator_1.validateTypesAsync(['String', twilio_sdk_type_validator_1.literal(null)]),
// __metadata('design:type', Function),
// __metadata('design:paramtypes', [String]),
// __metadata('design:returntype', Promise)
// ], User.prototype, 'updateFriendlyName', null);

//
// Fired when User's properties or reachability status have been updated.
// @event User#updated
// @type {Object}
// @property {User} user - Updated User
// @property {User#UpdateReason[]} updateReasons - List of User's updated event reasons
//
//
// Fired when Client is subscribed to User.
// @event User#userSubscribed
// @type {User}
//
//
// Fired when Client is unsubscribed from this User.
// @event User#userUnsubscribed
// @type {User}
//
