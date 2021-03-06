part of broker;

class DsSimpleLinkManager implements ServerLinkManager {
  final Map<String, HttpServerLink> _links = new Map<String, HttpServerLink>();

  bool addLink(ServerLink link) {
    _links[link.dsId] = link;
    return true;
  }

  ServerLink getLinkAndConnectNode(String dsId, {String sessionId: ''}) {
    return _links[dsId];
  }

  void removeLink(ServerLink link, String id) {
    if (_links[id] == link) {
      _links.remove(id);
    }
  }

  Requester getRequester(String dsId) {
    return new Requester();
  }

  Responder getResponder(String dsId, NodeProvider nodeProvider,
      [String sessionId = '']) {
    return new Responder(nodeProvider);
  }

  void updateLinkData(String dsId, Map m) {
  }

  String getLinkPath(String dsId, String token) {
    return '/$dsId';
  }
}

class DsHttpServer {
  String dsId = "broker-dsa-VLK07CSRoX_bBTQm4uDIcgfU-jV-KENsp52KvDG_o8g";
  String publicKey =
      "vvOSmyXM084PKnlBz3SeKScDoFs6I_pdGAdPAB8tOKmA5IUfIlHefdNh1jmVfi1YBTsoYeXm2IH-hUZang48jr3DnjjI3MkDSPo1czrI438Cr7LKrca8a77JMTrAlHaOS2Yd9zuzphOdYGqOFQwc5iMNiFsPdBtENTlx15n4NGDQ6e3d8mrKiSROxYB9LrF1-53goDKvmHYnDA_fbqawokM5oA3sWUIq5uNdp55_cF68Lfo9q-ea8JEsHWyDH73FqNjUaPLFdgMl8aYl-sUGpdlMMMDwRq-hnwG3ad_CX5iFkiHpW-uWucta9i3bljXgyvJ7dtVqEUQBH-GaUGkC-w";
  int updateInterval = 200;
  final NodeProvider nodeProvider;
  final ServerLinkManager _linkManager;

  /// to open a secure server, SecureSocket.initialize() need to be called before start()
  DsHttpServer.start(dynamic address, //
      {int httpPort: 8080,
      int httpsPort: 8443,
      String certificateName,
      linkManager,
      this.nodeProvider})
      : _linkManager =
            (linkManager == null) ? new DsSimpleLinkManager() : linkManager {
    var completer = new Completer();
    onServerReady = completer.future;
    if (httpPort > 0) {
      HttpServer.bind(address, httpPort).then((server) {
        logger.info('Listening on HTTP port $httpPort');
        server.listen(_handleRequest);
        if (!completer.isCompleted) {
          completer.complete();
        }
        httpServer = server;
      }).catchError((Object err) {
        logger.severe(err);
      });
    }

    if (httpsPort > 0 && certificateName != null) {
      HttpServer
          .bindSecure(address, httpsPort, certificateName: certificateName)
          .then((server) {
        logger.info('Listening on HTTPS port $httpsPort');
        server.listen(_handleRequest);
      }).catchError((Object err) {
        logger.severe(err);
      });
    }
  }

  HttpServer httpServer;
  Future onServerReady;

  Future stop() async {
    await httpServer.close();
  }

  void _handleRequest(HttpRequest request) {
    try {
      if (request.method == "HEAD" || request.method == "OPTIONS") {
        var response = request.response;

        if (!(const ["/conn", "/http", "/ws"].contains(request.uri.path))) {
          response.statusCode = HttpStatus.NOT_FOUND;
        }

        response.headers
            .set("Access-Control-Allow-Methods", "POST, OPTIONS, GET");
        response.headers.set("Access-Control-Allow-Headers", "Content-Type");

        String origin = request.headers.value("origin");

        if (request.headers.value("x-proxy-origin") != null) {
          origin = request.headers.value("x-proxy-origin");
        }

        if (origin == null) {
          origin = "*";
        }

        response.headers.set('Access-Control-Allow-Origin', origin);
        response.close();
        return;
      }

      if (!(const ["/conn", "/http", "/ws"].contains(request.uri.path))) {
        updateResponseBeforeWrite(request, HttpStatus.NOT_FOUND, null, true);
        request.response.statusCode = HttpStatus.NOT_FOUND;
        request.response.writeln("Not Found.");
        request.response.close();
        return;
      }

      String dsId = request.uri.queryParameters['dsId'];

      if (dsId == null || dsId.length < 43) {
//        updateResponseBeforeWrite(request, HttpStatus.BAD_REQUEST);
        request.response.close();
        return;
      }

      switch (request.requestedUri.path) {
        case '/conn':
          _handleConn(request, dsId);
          break;
//        case '/http':
//          _handleHttpUpdate(request, dsId);
//          break;
        case '/ws':
          _handleWsUpdate(request, dsId);
          break;
        default:
//          updateResponseBeforeWrite(request, HttpStatus.BAD_REQUEST);
          request.response.close();
          break;
      }
    } catch (err) {
      if (err is int) {
        request.response.statusCode = err;
      }
      request.response.close();
    }
  }

  void _handleConn(HttpRequest request, String dsId) {
    String tokenHash = request.requestedUri.queryParameters["token"];
    bool trusted = false;

    if (tokenHash != null) {
      var tkn = tokenHash.substring(0, 16);
      trusted = TokenGroupNode.trustedTokens.values.any((x) => x.id == tkn);
    }

    request.fold([], foldList).then((List<int> merged) {
      try {
        if (merged.length > 1024) {
          updateResponseBeforeWrite(request /*, HttpStatus.BAD_REQUEST*/);
          // invalid connection request
          request.response.close();
          return;
        } else if (merged.length == 0) {
          updateResponseBeforeWrite(request /*, HttpStatus.BAD_REQUEST*/);
          request.response.close();
          return;
        }
        String str = const Utf8Decoder().convert(merged);
        Map m = DsJson.decode(str);
        
        HttpServerLink link = _linkManager.getLinkAndConnectNode(dsId);
             
        if (link == null) {
          String publicKeyPointStr = m['publicKey'];
          var bytes = Base64.decode(publicKeyPointStr);
          if (bytes == null) {
            // public key is invalid
            throw HttpStatus.BAD_REQUEST;
          }
          
          link = new HttpServerLink(
              dsId, new PublicKey.fromBytes(bytes), _linkManager, token: tokenHash,
              nodeProvider: nodeProvider, enableTimeout: true);
          if (trusted) {
            link.trustedTokenHash = tokenHash;
          } else if (!link.isDsIdValid) {
            // dsId doesn't match public key
            throw HttpStatus.BAD_REQUEST;
          }
          
          if (!_linkManager.addLink(link) ) {
            throw HttpStatus.UNAUTHORIZED;
          }
        }
        
        link.initLink(request, m['isRequester'] == true,
            m['isResponder'] == true, dsId, publicKey,
            updateInterval: updateInterval, linkData:m['linkData']);
      } catch (err) {
        if (err is int) {
          // TODO need protection because changing statusCode itself can throw
          updateResponseBeforeWrite(request, err);
        } else {
          updateResponseBeforeWrite(request);
        }
        request.response.close();
      }
    });
  }

//  void _handleHttpUpdate(HttpRequest request, String dsId) {
//    bool trusted = request.requestedUri.host == '127.0.0.1';
//
//    HttpServerLink link = _linkManager.getLink(dsId);
//    if (link != null) {
//      link.handleHttpUpdate(request, trusted);
//    } else {
//      throw HttpStatus.UNAUTHORIZED;
//    }
//  }

  void _handleWsUpdate(HttpRequest request, String dsId) {
    HttpServerLink link = _linkManager.getLinkAndConnectNode(dsId);
    if (link != null) {
      bool trusted = link.trustedTokenHash != null && request.requestedUri.queryParameters["token"] == link.trustedTokenHash;
      if (link.pendingLinkData != null) {
        _linkManager.updateLinkData(link.dsId, link.pendingLinkData);
        link.pendingLinkData = null;
      }
      link.handleWsUpdate(request, trusted);
    } else {
      throw HttpStatus.UNAUTHORIZED;
    }
  }
}
