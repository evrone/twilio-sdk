// todo сделать хранилище для каждой платформы
// todo сделать window доступным в вебе

import 'dart:html' as html;

class TokenStorage {
  static html.Storage get sessionStorage {
    try {
      return html.window.sessionStorage;
    } catch (err) {
      return null;
    }
  }

  static html.WindowBase get window {
    try {
      return html.window.window;
    } catch (err) {
      return null;
    }
  }

  static void storeToken(String continuationToken, String productId) {
    if (TokenStorage.canStore) {
      TokenStorage.sessionStorage[TokenStorage.getKeyName(productId)] =
          continuationToken;
    }
  }

  static String getStoredToken(String productId) {
    if (!TokenStorage.canStore) {
      return null;
    }
    return TokenStorage.sessionStorage[TokenStorage.getKeyName(productId)];
  }

  static void initialize() {
    if (TokenStorage.canStore) {
      final flag = TokenStorage.sessionStorage[TokenStorage.initializedFlag];
      // Duplicated tab, cleaning up all stored keys
      if (flag != null) {
        clear();
      }
      TokenStorage.sessionStorage[TokenStorage.initializedFlag] = 'true';
      // When leaving page or refreshing
      TokenStorage.window.addEventListener('unload', (e) {
        TokenStorage.sessionStorage[TokenStorage.initializedFlag];
      });
    }
  }

  static void clear() {
    if (TokenStorage.canStore) {
      TokenStorage.sessionStorage.clear();
    }
  }

  static String getKeyName(String productId) {
    return '${TokenStorage.tokenStoragePrefix}$productId';
  }

  static bool get canStore {
    return TokenStorage.sessionStorage != null && TokenStorage.window != null;
  }

  static String initializedFlag = 'twilio_twilsock_token_storage';
  static String tokenStoragePrefix = 'twilio_continuation_token_';
}

//TokenStorage.initialize();
