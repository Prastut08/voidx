// Top-level context object for JS interoperability stubbing
class JsContextStub {
  const JsContextStub();

  void callMethod(String method, [List<dynamic>? args]) {
    // No-op on mobile devices
  }

  dynamic operator [](Object? key) => null;
  void operator []=(Object? key, dynamic value) {}
}

const JsContextStub context = JsContextStub();
