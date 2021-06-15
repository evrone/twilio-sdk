import 'dart:async';

import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/config/sync.dart';
import 'package:twilio_conversations/src/errors/transportunavailableerror.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/entity.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/subscribed_entity/subscribed_entity.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff.dart';

import 'network.dart';
import 'router.dart';

/// @class Subscriptions
/// @classdesc A manager which, in batches of varying size, continuously persists the
///      subscription intent of the caller to the Sync backend until it achieves a
///      converged state.
class Subscriptions {
  /// @constructor
  /// Prepares a new Subscriptions manager object with zero subscribed or persisted subscriptions.
  ///
  /// @param {object} config may include a key 'backoffConfig', wherein any of the parameters
  ///      of Backoff.exponential (from npm 'backoff') are valid and will override the defaults.
  ///
  /// @param {Network} must be a viable running Sync Network object, useful for routing requests.
  Subscriptions(
      {this.config,
      this.network,
      this.storage,
      this.subscriptions,
      this.router}) {
    final defaultBackoffConfig = {
      'randomisationFactor': 0.2,
      'initialDelay': 100,
      'maxDelay': 2 * 60 * 1000
    };
    defaultBackoffConfig.addAll(config.backoffConfig.toMap);
    backoff = Backoff.exponential(
        maxDelay: defaultBackoffConfig['maxDelay'],
        initialDelay: defaultBackoffConfig['initialDelay'],
        randomisationFactor: defaultBackoffConfig['randomisationFactor']);
    backoff.on('ready', (_) {
      final updateBatch = getSubscriptionUpdateBatch();
      final action = updateBatch['action'];
      final subscriptions = updateBatch['subscriptions'];

      if (action != null) {
        applyNewSubscriptionUpdateBatch(action, subscriptions);
      } else {
        backoff.reset();
        // logger_1.default.debug('All subscriptions resolved.');
      }
    });
  }

  SyncConfiguration config;
  SyncNetwork network;
  Storage storage;
  SyncRouter router;
  bool isConnected = false;
  int maxBatchSize = 100;
  // If the server includes a `ttl_in_s` attribute in the poke response, subscriptionTtlTimer is started for that duration
  // such that when it fires, it repokes the entire sync set (i.e., emulates a reconnect). Every reconnect resets the timer.
  // After the timer has fired, the first poke request includes a `reason: ttl` attribute in the body.
  Timer subscriptionTtlTimer;
  var pendingPokeReason;

  Map<String, dynamic> subscriptions = {};
  Map<String, dynamic> persisted = {};
  Map<int, DateTime> latestPokeResponseArrivalTimestampByCorrelationId = {};

  Backoff backoff;
  // This block is triggered by #_persist. Every request is executed in a series of (ideally 1)
  // backoff 'ready' event, at which point a new subscription set is calculated.

  Map<String, dynamic> getSubscriptionUpdateBatch() {
    final subtract = (Map<String, dynamic> these, Map<String, dynamic> those,
        String action, int limit) {
      final result = [];
      for (var key in these.keys) {
        final otherValue = those[key];
        if (otherValue == null &&
            action != these[key].pendingAction &&
            !these[key].rejectedWithError) {
          //todo
          result.add(these[key]);
          if (limit != null && result.length >= limit) {
            break;
          }
        }
      }
      return result;
    };
    final listToAdd =
        subtract(subscriptions, persisted, 'establish', maxBatchSize);
    if (listToAdd.isNotEmpty) {
      return {'action': 'establish', 'subscriptions': listToAdd};
    }
    final listToRemove =
        subtract(persisted, subscriptions, 'cancel', maxBatchSize);
    if (listToRemove.isNotEmpty) {
      return {'action': 'cancel', 'subscriptions': listToRemove};
    }
    return {'action': null, 'subscriptions': null};
  }

  void persist() {
    backoff.backoff();
  }

  void applyNewSubscriptionUpdateBatch(String action, requests) async {
    if (!isConnected) {
      //logger_1.default.debug(`Twilsock connection (required for subscription) not ready; waiting…`);
      backoff.reset();
      return;
    }
    // Keeping in mind that events may begin flowing _before_ we receive the response
    requests = processLocalActions(action, requests);
    final correlationId = DateTime.now().millisecondsSinceEpoch;
    for (final subscribed in requests) {
      recordActionAttemptOn(subscribed, action, correlationId);
    }
    final reason = pendingPokeReason;
    pendingPokeReason = null;
    // Send this batch to the service
    try {
      final response = await request(action, correlationId, reason, requests);
      final newMaxBatchSize = response.body.max_batch_size;
      if (int.tryParse(newMaxBatchSize) != null &&
          (newMaxBatchSize as int).isFinite &&
          newMaxBatchSize > 0) {
        maxBatchSize = newMaxBatchSize;
      }
      if (subscriptionTtlTimer == null) {
        final subscriptionTtlInS = response.body.ttl_in_s;
        final isNumeric = double.tryParse(subscriptionTtlInS) != null &&
            subscriptionTtlInS.isFinite;
        final isValidTtl = isNumeric && subscriptionTtlInS > 0;
        if (isValidTtl) {
          subscriptionTtlTimer =
              Timer(Duration(milliseconds: (subscriptionTtlInS * 1000)), () {
            onSubscriptionTtlElapsed();
          });
        }
      }
      if (action == 'establish') {
        final estimatedDeliveryInMs = response.body.estimatedDeliveryInMs;
        final isNumeric = double.tryParse(estimatedDeliveryInMs) != null &&
            estimatedDeliveryInMs.isFinite;
        final isValidTimeout = isNumeric && estimatedDeliveryInMs > 0;
        if (isValidTimeout) {
          Timer(estimatedDeliveryInMs, () {
            verifyPokeDelivery(correlationId, estimatedDeliveryInMs, requests);
          });
        } else {
          //logger_1.default.error(`Invalid timeout: ${estimatedDeliveryInMs}`);
        }
        requests
            .filter((r) => r.pendingCorrelationId == correlationId)
            .forEach((r) => r.setSubscriptionState('response_in_flight'));
      }
      backoff.reset();
    } catch (e) {
      for (var attemptedSubscription in requests) {
        recordActionFailureOn(attemptedSubscription, action);
      }
      if (e is TransportUnavailableError) {
        //logger_1.default.debug(`Twilsock connection (required for subscription) not ready (c:${correlationId}); waiting…`);
        backoff.reset();
      } else {
        //logger_1.default.debug(`Failed an attempt to ${action} subscriptions (c:${correlationId}); retrying`, e);
        persist();
      }
    }
  }

  void verifyPokeDelivery(
      int correlationId, Duration estimatedDeliveryInMs, requests) {
    final lastReceived =
        latestPokeResponseArrivalTimestampByCorrelationId[correlationId];
    final silencePeriod = lastReceived != null
        ? (lastReceived.difference(DateTime.now()))
        : estimatedDeliveryInMs;
    if (silencePeriod >= estimatedDeliveryInMs) {
      // If we haven't received _any_ responses from that poke request for the duration of estimated_delivery_in_ms, poke again
      requests
          .filter((r) => r.pendingCorrelationId == correlationId)
          .forEach((r) {
        r.updatePending(null, null);
        r.retryCount++;
        persisted.remove(r.sid);
      });
      persist();
      latestPokeResponseArrivalTimestampByCorrelationId.remove(correlationId);
    } else {
      // Otherwise, the poke responses are probably in transit and we should wait for them
      final timeoutExtension = estimatedDeliveryInMs - silencePeriod;

      Timer(timeoutExtension, () {
        verifyPokeDelivery(correlationId, estimatedDeliveryInMs, requests);
      });
    }
  }

  dynamic processLocalActions(String action, requests) {
    if (action == 'cancel') {
      return requests.filter((request) => !request.rejectedWithError);
    }
    return requests;
  }

  void recordActionAttemptOn(
      attemptedSubscription, String action, int correlationId) {
    attemptedSubscription.setSubscriptionState('request_in_flight');
    if (action == 'establish') {
      persisted[attemptedSubscription.sid] = attemptedSubscription;
      attemptedSubscription.updatePending(action, correlationId);
    } else {
      // cancel
      final persistedSubscription = persisted[attemptedSubscription.sid];
      if (persistedSubscription) {
        persistedSubscription.updatePending(action, correlationId);
      }
    }
  }

  void recordActionFailureOn(attemptedSubscription, String action) {
    attemptedSubscription.setSubscriptionState('none');
    attemptedSubscription.updatePending(null, null);
    if (action == 'establish') {
      persisted.remove(attemptedSubscription.sid);
    }
  }

  Future request(String action, int correlationId, reason, objects) {
    final requests = objects.map((object) => {
          'object_sid': object.sid,
          'object_type': object.type,
          'last_event_id': action == 'establish' ? object.lastEventId : null,
          'index_name': action == 'establish' ? object.indexName : null,
          'query_string': action == 'establish' ? object.queryString : null,
        });
    final retriedRequests = objects.filter((a) => a.retryCount > 0).length;
    //logger_1.default.debug(`Attempting '${action}' request (c:${correlationId}):`, requests);
    final requestBody = {
      'event_protocol_version': 3,
      'action': action,
      'correlation_id': correlationId,
      'retried_requests': retriedRequests,
      'ttl_in_s': -1,
      'requests': requests
    };
    if (reason == 'ttl') {
      requestBody['reason'] = reason;
    }
    return network.post(config.subscriptionsUri, body: requestBody);
  }

  /// Establishes intent to be subscribed to this entity. That subscription will be effected
  /// asynchronously.
  /// If subscription to the given sid already exists, it will be overwritten.
  ///
  /// @param {String} sid should be a well-formed SID, uniquely identifying a single instance of a Sync entity.
  /// @param {Object} entity should represent the (singular) local representation of this entity.
  ///      Incoming events and modifications to the entity will be directed at the _update() function
  ///      of this provided reference.
  ///
  /// @return undefined
  void add(String sid, SyncEntity entity) {
    //logger_1.default.debug(`Establishing intent to subscribe to ${sid}`);
    final existingSubscription = subscriptions[sid];
    if (existingSubscription != null &&
        entity != null &&
        existingSubscription.lastEventId == entity.lastEventId) {
      // If last event id is the same as before - we're fine
      return;
    }
    persisted.remove(sid);
    subscriptions[sid] = SubscribedEntity(entity);
    persist();
  }

  /// Establishes the caller's intent to no longer be subscribed to this entity. Following this
  /// call, no further events shall be routed to the local representation of the entity, even
  /// though a server-side subscription may take more time to actually terminate.
  ///
  /// @param {string} sid should be any well-formed SID, uniquely identifying a Sync entity.
  ///      This call only has meaningful effect if that entity is subscribed at the
  ///      time of call. Otherwise does nothing.
  ///
  /// @return undefined
  void remove(String sid) {
    //logger_1.default.debug(`Establishing intent to unsubscribe from ${sid}`);
    final removed = subscriptions.remove(sid);
    if (removed != null) {
      persist();
    }
  }

  /// The point of ingestion for remote incoming messages (e.g. new data was written to a map
  /// to which we are subscribed).
  ///
  /// @param {object} message is the full, unaltered body of the incoming notification.
  ///
  /// @return undefined
  void acceptMessage(Map<String, dynamic> message, bool isStrictlyOrdered) {
    //logger_1.default.trace('Subscriptions received', message);
    if (message['correlation_id'] != null) {
      latestPokeResponseArrivalTimestampByCorrelationId[
          message['correlation_id']] = DateTime.now();
    }
    var eventType;
    switch (message['eventType']) {
      case 'subscription_established':
        applySubscriptionEstablishedMessage(
            message['event'], message['correlation_id']);
        break;
      case 'subscription_canceled':
        applySubscriptionCancelledMessage(
            message['event'], message['correlation_id']);
        break;
      case 'subscription_failed':
        applySubscriptionFailedMessage(
            message['event'], message['correlation_id']);
        break;
      default:
        if ((message['event_type'] as String)
            .contains(RegExp('^(?:map|list|document|stream|live_query)_'))) {
          final List<String> split = message['event_type'].split('_');
          final type =
              split.length > 2 ? '${split[0]}_${split[1]}' : split.first;
          var typedSid;
          switch (type) {
            case 'map':
              typedSid = message['event']['map_sid'];
              break;
            case 'list':
              typedSid = message['event']['list_sid'];
              break;
            case 'document':
              typedSid = message['event']['document_sid'];
              break;
            case 'stream':
              typedSid = message['event']['stream_sid'];
              break;
            case 'live_query':
              typedSid = message['event']['query_id'];
              // hack to mark replay events for LiveQuery as strictly ordered, due to lack of special type of notification for them
              // (normally only replay events would have `twilio.sync.event` type, but LiveQuery non-replay events were also assigned
              // to this type in legacy clients, which we have to support now; hence a hack)
              isStrictlyOrdered =
                  false; // explicitly override it due to code in router.ts does not know about LiveQueries
              if (message['strictly_ordered'] == true) {
                isStrictlyOrdered = true;
              }
              break;
            default:
              typedSid = null;
          }
          applyEventToSubscribedEntity(typedSid, message, isStrictlyOrdered);
        }

        //logger_1.default.debug(`Dropping unknown message type ${message.event_type}`);
        break;
    }
  }

  void applySubscriptionEstablishedMessage(message, int correlationId) {
    final sid = message.objectSid;
    final subscriptionIntent = persisted[message.objectSid];
    if (subscriptionIntent &&
        subscriptionIntent.pendingCorrelationId == correlationId) {
      if (message.replayStatus == 'interrupted') {
        //logger_1.default.debug(`Event Replay for subscription to ${sid} (c:${correlationId}) interrupted; continuing eagerly.`);
        subscriptionIntent.updatePending(null, null);
        persisted.remove(subscriptionIntent.sid);
        backoff.reset();
      } else if (message.replayStatus == 'completed') {
        //logger_1.default.debug(`Event Replay for subscription to ${sid} (c:${correlationId}) completed. Subscription is ready.`);
        subscriptionIntent.complete(message.lastEventId);
        persisted[message.objectSid] = subscriptionIntent;
        subscriptionIntent.setSubscriptionState('established');
        backoff.reset();
      }
    } else {
      //logger_1.default.debug(`Late message for ${message.object_sid} (c:${correlationId}) dropped.`);
    }
    persist();
  }

  void applySubscriptionCancelledMessage(message, correlationId) {
    final persistedSubscription = persisted[message.objectSid];
    if (persistedSubscription != null &&
        persistedSubscription.pendingCorrelationId == correlationId) {
      persistedSubscription.updatePending(null, null);
      persistedSubscription.setSubscriptionState('none');
      persisted.remove(message.objectSid);
    } else {
      //logger_1.default.debug(`Late message for ${message.object_sid} (c:${correlationId}) dropped.`);
    }
    persist();
  }

  void applySubscriptionFailedMessage(message, int correlationId) {
    final sid = message.objectSid;
    final subscriptionIntent = subscriptions[sid];
    final subscription = persisted[sid];
    if (subscriptionIntent && subscription) {
      if (subscription.pendingCorrelationId == correlationId) {
        //logger_1.default.error(`Failed to subscribe on ${subscription.sid}`, message.error);
        subscription.markAsFailed(message);
        subscription.setSubscriptionState('none');
      }
    } else if (!subscriptionIntent && subscription) {
      persisted.remove(sid);
      subscription.setSubscriptionState('none');
    }
    persist();
  }

  void applyEventToSubscribedEntity(
      String sid, message, bool isStrictlyOrdered) {
    if (sid == null) {
      return;
    }
    // Looking for subscription descriptor to check if poke has been completed
    isStrictlyOrdered = isStrictlyOrdered ??
        (() {
          final subscription = persisted[sid];
          return subscription && subscription.isEstablished;
        });
    // Still searching for subscriptionIntents. User could remove subscription already
    final subscriptionIntent = subscriptions[sid];
    if (subscriptionIntent) {
      message.event.type = message.event_type;
      subscriptionIntent.update(message.event, isStrictlyOrdered);
    } else {
      //logger_1.default.debug(`Message dropped for SID '${sid}', for which there is no subscription.`);
    }
  }

  void onConnectionStateChanged(isConnected) {
    this.isConnected = isConnected;
    if (isConnected) {
      poke('reconnect');
    }
  }

  void onSubscriptionTtlElapsed() {
    if (isConnected) {
      poke('ttl');
    }
  }

  /// Prompts a playback of any missed changes made to any subscribed object. This method
  /// should be invoked whenever the connectivity layer has experienced cross-cutting
  /// delivery failures that would affect the entire local sync set. Any tangible result
  /// of this operation will result in calls to the _update() function of subscribed
  /// Sync entities.
  void poke(reason) {
    //logger_1.default.debug(`Triggering event replay for all subscriptions, reason=${reason}`);
    pendingPokeReason = reason;
    if (subscriptionTtlTimer != null) {
      clearTimeout(subscriptionTtlTimer);
      subscriptionTtlTimer = null;
    }
    final failedSubscriptions = [];
    for (var it in persisted.values) {
      it.reset();
      if (it.rejectedWithError) {
        failedSubscriptions.add(it);
      }
    }
    persisted.clear();
    for (var it in failedSubscriptions) {
      persisted[it.sid] = it;
    }
    persist();
  }

  /// Stops all communication, clears any subscription intent, and returns.
  void shutdown() {
    backoff.reset();
    subscriptions.clear();
  }

  void clearTimeout(subscriptionTtlTimer) {}
}
