import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// يلتقط تنزيلات الملفات من نوع blob (Excel / النسخ الاحتياطي)
/// ويرسلها إلى Flutter لمشاركتها أو حفظها.
const String kBlobHook = r'''
(function(){
  if (window.__tdHook) return;
  window.__tdHook = true;
  function send(a){
    var name = a.getAttribute('download') || 'file';
    fetch(a.href).then(function(r){ return r.blob(); }).then(function(b){
      var fr = new FileReader();
      fr.onloadend = function(){
        var d = String(fr.result), i = d.indexOf(',');
        window.flutter_inappwebview.callHandler(
          'saveFile', name, d.slice(i + 1), b.type || 'application/octet-stream');
      };
      fr.readAsDataURL(b);
    });
  }
  var oc = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function(){
    if (this.hasAttribute('download') && /^blob:/.test(this.href)) { send(this); return; }
    return oc.apply(this, arguments);
  };
})();
''';

/// زر الرجوع: يغلق القائمة الجانبية، ثم يعود للرئيسية، ثم يخرج.
const String kBackJs = r'''
(function(){
  var s = document.getElementById('side');
  if (s && s.classList.contains('o')) { s.classList.remove('o'); return 1; }
  var h = document.getElementById('v-home');
  if (h && h.hidden && typeof show === 'function') { show('home'); return 1; }
  return 0;
})();
''';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0B1E45),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0B1E45),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const TeacherApp());
}

class TeacherApp extends StatelessWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تطبيق الأستاذ',
      home: WebPage(),
    );
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  InAppWebViewController? _c;

  Future<void> _saveFile(String name, String b64, String mime) async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final f = File('${dir.path}/$safe');
      await f.writeAsBytes(base64Decode(b64));
      await Share.shareXFiles([XFile(f.path, mimeType: mime)], subject: safe);
    } catch (e) {
      debugPrint('saveFile error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final r = await _c?.evaluateJavascript(source: kBackJs);
        if (r != 1) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1E45),
        body: SafeArea(
          child: InAppWebView(
            initialFile: 'assets/index.html',
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              allowFileAccess: true,
              allowContentAccess: true,
              mediaPlaybackRequiresUserGesture: false,
              supportZoom: false,
              transparentBackground: false,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: kBlobHook,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              _c = controller;
              controller.addJavaScriptHandler(
                handlerName: 'saveFile',
                callback: (args) async {
                  if (args.length >= 3) {
                    await _saveFile(
                        args[0].toString(), args[1].toString(), args[2].toString());
                  }
                  return null;
                },
              );
            },
          ),
        ),
      ),
    );
  }
}