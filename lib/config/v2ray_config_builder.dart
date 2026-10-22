import 'dart:convert';

import '../url/url.dart';

/// Composes Xray configurations without changing the existing V2RayURL API.
///
/// This builder keeps arbitrary Xray sections intact (including observatory,
/// policy, DNS, and future core options) so it can also edit hand-written JSON.
/// The first outbound is the default when no routing rule chooses another one.
class V2RayConfigBuilder {
  V2RayConfigBuilder._(this._config);

  final Map<String, dynamic> _config;

  static Map<String, dynamic> _cloneMap(Map<String, dynamic> source) =>
      (jsonDecode(jsonEncode(source)) as Map<String, dynamic>);

  /// Begin with the legacy share-link parser's full configuration.
  factory V2RayConfigBuilder.fromUrl(V2RayURL url) {
    final decoded = jsonDecode(url.getFullConfiguration(indent: 0));
    return V2RayConfigBuilder._(decoded as Map<String, dynamic>);
  }

  /// Compose several share links while retaining the first link's local
  /// inbound, DNS defaults and direct/blackhole outbounds.
  ///
  /// Generated tags are proxy, proxy-2, proxy-3, etc. Supply [tags] to
  /// override them. Use addBalancer and route to choose among servers.
  factory V2RayConfigBuilder.fromUrls(
    Iterable<V2RayURL> urls, {
    List<String>? tags,
  }) {
    final links = urls.toList(growable: false);
    if (links.isEmpty) {
      throw ArgumentError('At least one share link is required');
    }
    if (tags != null && tags.length != links.length) {
      throw ArgumentError('tags length must equal urls length');
    }
    final builder = V2RayConfigBuilder.fromUrl(links.first);
    final firstTag = tags == null ? 'proxy' : tags.first;
    if (firstTag.trim().isEmpty) {
      throw ArgumentError('Outbound tag cannot be empty');
    }
    final first = builder._listSection('outbounds').first as Map;
    first['tag'] = firstTag;
    for (var i = 1; i < links.length; i++) {
      builder.addOutboundFromUrl(links[i],
          tag: tags == null ? 'proxy-${i + 1}' : tags[i]);
    }
    return builder;
  }

  /// Preserve all existing sections in a full Xray JSON configuration.
  factory V2RayConfigBuilder.fromJson(String config) {
    final dynamic value;
    try {
      value = jsonDecode(config);
    } on FormatException {
      throw const FormatException('Xray configuration must be valid JSON');
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Xray configuration must be a JSON object');
    }
    return V2RayConfigBuilder._(_cloneMap(value));
  }

  /// Start with a local SOCKS inbound and no outbound servers.
  ///
  /// Add at least one outbound before building the configuration.
  factory V2RayConfigBuilder.empty({
    int socksPort = 1080,
    String listen = '127.0.0.1',
  }) {
    if (socksPort < 1 || socksPort > 65535) {
      throw RangeError.range(socksPort, 1, 65535, 'socksPort');
    }
    return V2RayConfigBuilder._({
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'tag': 'in_proxy',
          'listen': listen,
          'port': socksPort,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
        }
      ],
      'outbounds': <Map<String, dynamic>>[],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': <Map<String, dynamic>>[],
      },
    });
  }

  List<dynamic> _listSection(String key) {
    final value = _config.putIfAbsent(key, () => <dynamic>[]);
    if (value is! List) {
      throw StateError('Xray section "$key" must be a JSON array');
    }
    return value;
  }

  Map<String, dynamic> _mapSection(String key) {
    final value =
        _config.putIfAbsent(key, () => <String, dynamic>{});
    if (value is! Map<String, dynamic>) {
      throw StateError('Xray section "$key" must be a JSON object');
    }
    return value;
  }

  Set<String> get outboundTags => _listSection('outbounds')
      .whereType<Map>()
      .map((outbound) => outbound['tag'])
      .whereType<String>()
      .toSet();

  /// Append an Xray outbound (VLESS, VMess, direct, blackhole, etc.).
  ///
  /// Its tag must be unique. The first outbound remains the default.
  V2RayConfigBuilder addOutbound(Map<String, dynamic> outbound,
      {String? tag}) {
    final copy = _cloneMap(outbound);
    if (tag != null) copy['tag'] = tag;
    final effectiveTag = copy['tag'];
    if (effectiveTag is! String || effectiveTag.trim().isEmpty) {
      throw ArgumentError('Every outbound needs a nonempty tag');
    }
    if (outboundTags.contains(effectiveTag)) {
      throw ArgumentError('Duplicate outbound tag: $effectiveTag');
    }
    if (copy['protocol'] is! String) {
      throw ArgumentError('Outbound needs a protocol');
    }
    _listSection('outbounds').add(copy);
    return this;
  }

  /// Parse a share link and add its generated outbound under a unique tag.
  V2RayConfigBuilder addOutboundFromUrl(V2RayURL url,
      {required String tag}) {
    return addOutbound(url.outbound1, tag: tag);
  }

  /// Edit a named outbound while preserving the other outbounds.
  V2RayConfigBuilder replaceOutbound(
      String tag, Map<String, dynamic> outbound) {
    final items = _listSection('outbounds');
    final index = items.indexWhere(
        (item) => item is Map && item['tag'] == tag);
    if (index < 0) throw ArgumentError('Unknown outbound tag: $tag');
    final copy = _cloneMap(outbound);
    copy['tag'] = tag;
    items[index] = copy;
    return this;
  }

  /// Add a raw routing rule, for advanced matching options.
  V2RayConfigBuilder addRoutingRule(Map<String, dynamic> rule) {
    _routingRules().add(_cloneMap(rule));
    return this;
  }

  List<dynamic> _routingRules() {
    final routing = _mapSection('routing');
    final rules =
        routing.putIfAbsent('rules', () => <Map<String, dynamic>>[]);
    if (rules is! List) {
      throw StateError('routing.rules must be a JSON array');
    }
    return rules;
  }

  /// Route matching domains or IP ranges to an outbound or balancer.
  V2RayConfigBuilder route({
    List<String>? domains,
    List<String>? ips,
    List<String>? inboundTags,
    String? outboundTag,
    String? balancerTag,
  }) {
    if ((outboundTag == null) == (balancerTag == null)) {
      throw ArgumentError(
          'Provide exactly one of outboundTag or balancerTag');
    }
    if ((domains == null || domains.isEmpty) &&
        (ips == null || ips.isEmpty) &&
        (inboundTags == null || inboundTags.isEmpty)) {
      throw ArgumentError('A route needs at least one matching condition');
    }
    return addRoutingRule({
      'type': 'field',
      if (domains != null && domains.isNotEmpty) 'domain': domains,
      if (ips != null && ips.isNotEmpty) 'ip': ips,
      if (inboundTags != null && inboundTags.isNotEmpty)
        'inboundTag': inboundTags,
      if (outboundTag != null) 'outboundTag': outboundTag,
      if (balancerTag != null) 'balancerTag': balancerTag,
    });
  }

  /// Register an Xray balancer. [selector] contains outbound tag prefixes.
  ///
  /// For leastLoad you may also need a burstObservatory section; pass it
  /// via setSection('burstObservatory', ...).
  V2RayConfigBuilder addBalancer({
    required String tag,
    required List<String> selector,
    String strategy = 'roundRobin',
    Map<String, dynamic>? strategySettings,
  }) {
    if (tag.trim().isEmpty || selector.isEmpty) {
      throw ArgumentError('Balancer tag and selector cannot be empty');
    }
    final routing = _mapSection('routing');
    final balancers =
        routing.putIfAbsent('balancers', () => <Map<String, dynamic>>[]);
    if (balancers is! List) {
      throw StateError('routing.balancers must be a JSON array');
    }
    if (balancers.any((item) => item is Map && item['tag'] == tag)) {
      throw ArgumentError('Duplicate balancer tag: $tag');
    }
    balancers.add({
      'tag': tag,
      'selector': List<String>.of(selector),
      'strategy': {
        'type': strategy,
        if (strategySettings != null)
          'settings': _cloneMap(strategySettings),
      },
    });
    return this;
  }

  /// Set any top-level Xray section without dropping unknown fields.
  V2RayConfigBuilder setSection(String key, Object? value) {
    if (key.trim().isEmpty) throw ArgumentError('Section key is empty');
    _config[key] = jsonDecode(jsonEncode(value));
    return this;
  }

  /// Replace DNS servers (IP strings, DoH URLs or full server objects).
  V2RayConfigBuilder setDnsServers(List<dynamic> servers) {
    _mapSection('dns')['servers'] = jsonDecode(jsonEncode(servers));
    return this;
  }

  /// Return an independent copy so callers cannot mutate the builder.
  Map<String, dynamic> build() {
    final outputs = _listSection('outbounds');
    if (outputs.isEmpty) {
      throw StateError('Xray configuration needs at least one outbound');
    }
    final seen = <String>{};
    for (final item in outputs) {
      if (item is! Map || item['tag'] is! String ||
          (item['tag'] as String).trim().isEmpty) {
        throw StateError('Every outbound needs a nonempty tag');
      }
      if (!seen.add(item['tag'] as String)) {
        throw StateError('Duplicate outbound tag: ${item['tag']}');
      }
    }
    return _cloneMap(_config);
  }

  String buildJson({int indent = 2}) {
    if (indent < 0) throw RangeError.range(indent, 0, null, 'indent');
    final data = build();
    return indent == 0
        ? jsonEncode(data)
        : JsonEncoder.withIndent(' ' * indent).convert(data);
  }

  /// Alias for the legacy parser naming convention.
  String getFullConfiguration({int indent = 2}) =>
      buildJson(indent: indent);
}
