import 'dart:async';

class Command {
  Command({this.commandId, this.request});
  String commandId;
  Completer _completer;
  Function get resolve => _completer.complete;
  Function get reject => _completer.completeError;

  var request;
}
