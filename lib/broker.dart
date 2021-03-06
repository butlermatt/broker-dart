/// DSA Broker Implementation
library broker;

import 'package:dslink/client.dart' show LinkProvider;
import 'package:dslink/responder.dart';
import 'package:dslink/requester.dart';
import 'package:dslink/common.dart';
import 'package:dslink/server.dart';
import 'dart:async';
import 'package:dslink/utils.dart';
import 'dart:io';
import 'dart:convert';
import 'src/http/websocket_conn.dart';
import 'dart:typed_data';
import 'package:dslink/query.dart';

part 'src/broker/broker_node_provider.dart';
part 'src/broker/broker_node.dart';
part 'src/broker/remote_node.dart';
part 'src/broker/remote_root_node.dart';
part 'src/broker/remote_requester.dart';
part 'src/broker/broker_discovery.dart';
part 'src/broker/broker_permissions.dart';
part 'src/broker/broker_alias.dart';
part 'src/broker/user_node.dart';
part 'src/broker/trace_node.dart';
part 'src/broker/throughput.dart';
part 'src/broker/data_nodes.dart';
part 'src/broker/tokens.dart';

part 'src/http/server_link.dart';
part 'src/http/server.dart';

part 'src/broker/query_node.dart';

Future<DsHttpServer> startBrokerServer(int port, {bool persist: true}) async {
  var broker = new BrokerNodeProvider();
  broker.shouldSaveFiles = persist;
  var server = new DsHttpServer.start(
      "0.0.0.0",
      httpPort: port,
      linkManager: broker,
      nodeProvider: broker
  );
  await server.onServerReady;
  return server;
}
