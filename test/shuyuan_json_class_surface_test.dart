/// Rhino 零使用族：JSON 类库面（org.json / fastjson / Gson）、
/// `java.lang.Class.forName` 注册类查找、okhttp3 FormBody / MultipartBody。
/// 覆盖 Android org.json 取值口径（字符串数值/布尔转换、缺失键异常）、
/// fastjson/Gson 解析与序列化、确定性边界 multipart 与 Content-Type 注入。
/// 全部为合成向量，不访问网络（重放键经 ajaxPending 取证）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(ShuyuanSourceContext.resetForTest);

  JsEngine engine() => JsEngine();

  test('org.json：解析、读取强制转换与 opt 默认值', () {
    final e = engine();
    expect(
        e.eval('''
(function(){
  var o = new org.json.JSONObject(
      '{"i":7,"f":"12.9","b":"true","n":null,"s":5}');
  return [o.getInt("i"), o.getInt("f"), o.getDouble("f"),
      o.getBoolean("b"), o.optBoolean("n"), o.getString("s"),
      o.optString("miss","d"), o.optInt("miss",3),
      String(o.optJSONArray("i"))].join("|");
})()'''),
        '7|12|12.9|true|false|5|d|3|null');
    expect(
        e.eval('''
(function(){
  var o = new org.json.JSONObject('{"i":7}');
  return [o.optInt("i"), o.getIntValue("i"), o.getIntValue("miss")].join("|");
})()'''),
        '7|7|0');
  });

  test('org.json：缺失键/类型不匹配/坏 JSON 抛 JSONException', () {
    final e = engine();
    expect(
        e.eval('(function(){try{'
            'new org.json.JSONObject(\'{"a":1}\').get("zz");'
            'return "no";}catch(e){return String(e);}})()'),
        allOf(contains('JSONException'), contains('No value for zz')));
    expect(
        e.eval('(function(){try{'
            'new org.json.JSONObject(\'{"s":"x"}\').getInt("s");'
            'return "no";}catch(e){return String(e);}})()'),
        contains('s is not an int'));
    expect(
        e.eval('(function(){try{'
            'new org.json.JSONObject("not json");'
            'return "no";}catch(e){return String(e);}})()'),
        contains('JSONException'));
    expect(
        e.eval('(function(){try{'
            'new org.json.JSONObject("[1]");'
            'return "no";}catch(e){return String(e);}})()'),
        allOf(contains('JSONException'), contains('cannot be converted')));
  });

  test('org.json：keys 迭代、put/remove、嵌套对象与数组', () {
    final e = engine();
    expect(
        e.eval('''
(function(){
  var o = new org.json.JSONObject('{"b":2,"a":1}');
  var it = o.keys(); var out = [];
  while (it.hasNext()) out.push(it.next());
  return out.join(",");
})()'''),
        'b,a');
    expect(
        e.eval('''
(function(){
  var o = new org.json.JSONObject().put("x","y");
  var removed = o.remove("x");
  return [o.length(), o.isEmpty(), removed, String(o.remove("x"))].join("|");
})()'''),
        '0|true|y|null');
    expect(
        e.eval('''
(function(){
  var o = new org.json.JSONObject('{"d":{"n":2},"l":[1,{"k":"v"}]}');
  var a = o.getJSONArray("l");
  return [o.getJSONObject("d").getInt("n"), a.length(),
      a.getJSONObject(1).getString("k"), String(o.optJSONObject("zz")),
      a.getInt(0)].join("|");
})()'''),
        '2|2|v|null|1');
    // 包装对象复制（new JSONObject(JSONObject) / new JSONArray(JSONArray)）。
    expect(
        e.eval('''
(function(){
  var o = new org.json.JSONObject('{"a":1}');
  var c = new org.json.JSONObject(o).put("b",2);
  var arr = new org.json.JSONArray(new org.json.JSONArray('[1,2]'));
  return [o.length(), c.length(), arr.length()].join("|");
})()'''),
        '1|2|2');
  });

  test('顶层包名与 importClass：org.json / com.* 可达同一类', () {
    final e = engine();
    expect(
        e.eval('''
[String(org.json.JSONObject === Packages.org.json.JSONObject),
 String(com.alibaba.fastjson.JSON === Packages.com.alibaba.fastjson.JSON),
 String(com.google.gson.Gson === Packages.com.google.gson.Gson)].join("|")'''),
        'true|true|true');
    expect(
        e.eval('''
(function(){
  importClass(org.json.JSONObject);
  return String(new JSONObject('{"a":1}').getInt("a"));
})()'''),
        '1');
  });

  test('fastjson：parse/parseObject/parseArray/toJSONString', () {
    final e = engine();
    expect(
        e.eval('''
(function(){
  var o = com.alibaba.fastjson.JSON.parseObject('{"d":{"n":2},"l":[1,2]}');
  var arr = com.alibaba.fastjson.JSON.parseArray('[3,4]');
  var n = com.alibaba.fastjson.JSON.parse('123');
  return [o.getJSONObject("d").getInt("n"), arr.getInt(1), String(n),
      com.alibaba.fastjson.JSON.toJSONString(o)].join("|");
})()'''),
        '2|4|123|{"d":{"n":2},"l":[1,2]}');
    expect(
        e.eval('(function(){try{'
            'com.alibaba.fastjson.JSON.parseArray(\'{"a":1}\');'
            'return "no";}catch(e){return String(e);}})()'),
        allOf(contains('JSONException'), contains('cannot be converted')));
  });

  test('Gson：toJson/fromJson/GsonBuilder/JsonParser', () {
    final e = engine();
    expect(
        e.eval('''
(function(){
  var g = new com.google.gson.Gson();
  var parsed = g.fromJson('{"x":[1,2]}');
  var viaBuilder = new Packages.com.google.gson.GsonBuilder().create();
  return [g.toJson(Packages.com.alibaba.fastjson.JSON.parseObject('{"a":1}')),
      String(parsed.x[1]), viaBuilder.toJson("中"),
      com.google.gson.JsonParser.parseString('[1,2]').length].join("|");
})()'''),
        '{"a":1}|2|"中"|2');
  });

  test('Class.forName：已注册类返回自身，未注册抛 ClassNotFoundException', () {
    final e = engine();
    expect(
        e.eval('''
(function(){
  var C = Packages.java.lang.Class;
  return [String(C.forName("java.lang.String") === Packages.java.lang.String),
      C.forName("java.lang.String").getName(),
      String(C.forName("org.json.JSONObject") === org.json.JSONObject),
      String(C.forName("okhttp3.FormBody") === Packages.okhttp3.FormBody)]
      .join("|");
})()'''),
        'true|java.lang.String|true|true');
    expect(
        e.eval('(function(){try{'
            'Packages.java.lang.Class.forName("java.lang.Nope");'
            'return "no";}catch(e){return String(e);}})()'),
        contains('ClassNotFoundException'));
  });

  test('FormBody：urlencoded 编码与 Content-Type 注入（显式头优先）', () {
    final ctx = ShuyuanSourceContext('src_json_form');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      expect(
          e.eval('''
(function(){
  var b = new Packages.okhttp3.FormBody.Builder()
      .add("a","1 2").add("b","中文").build();
  return b.toString() + "|" + String(b.contentType());
})()'''),
          'a=1+2&b=%E4%B8%AD%E6%96%87|application/x-www-form-urlencoded');
      e.eval('''
(function(){
  var b = new Packages.okhttp3.FormBody.Builder().add("a","1").build();
  var r = new Packages.okhttp3.Request.Builder()
      .url("https://x.test/form").post(b).build();
  new Packages.okhttp3.OkHttpClient().newCall(r).execute();
})()''');
      expect(ctx.ajaxPending.last, contains('||POST||a=1'));
      expect(ctx.ajaxPending.last,
          contains('"Content-Type":"application/x-www-form-urlencoded"'));
      e.eval('''
(function(){
  var b = new Packages.okhttp3.FormBody.Builder().add("a","1").build();
  var r = new Packages.okhttp3.Request.Builder()
      .url("https://x.test/form2").addHeader("Content-Type","application/json")
      .post(b).build();
  new Packages.okhttp3.OkHttpClient().newCall(r).execute();
})()''');
      expect(ctx.ajaxPending.last, contains('"Content-Type":"application/json"'));
      expect(ctx.ajaxPending.last,
          isNot(contains('application/x-www-form-urlencoded')));
    });
  });

  test('MultipartBody：确定性边界、CRLF 结构与 form-data 部件', () {
    final e = engine();
    String buildScript(String value) => '''
(function(){
  var b = new Packages.okhttp3.MultipartBody.Builder()
      .addFormDataPart("field","$value")
      .addFormDataPart("file","a.txt",
          Packages.okhttp3.RequestBody.create("hello",
              Packages.okhttp3.MediaType.parse("text/plain")))
      .build();
  return String(b.contentType()) + "\\n" + b.toString();
})()''';
    final first = e.eval(buildScript('value 1')).split('\n');
    final second = e.eval(buildScript('value 1')).split('\n');
    final third = e.eval(buildScript('value 2')).split('\n');
    expect(first[0], startsWith('multipart/form-data; boundary=----NexHubBoundary'));
    expect(second[0], first[0]);
    expect(third[0], isNot(first[0]));
    final boundary = first[0].split('boundary=')[1];
    final body = first.sublist(1).join('\n');
    expect(body.split('--$boundary').length - 1, 3);
    expect(body, contains('Content-Disposition: form-data; name="field"'));
    expect(body,
        contains('Content-Disposition: form-data; name="file"; filename="a.txt"'));
    expect(body, contains('Content-Type: text/plain'));
    expect(body, contains('\r\n\r\nvalue 1\r\n'));
    expect(body, endsWith('--$boundary--\r\n'));
  });

  test('MultipartBody：POST 重放键携带 multipart Content-Type 与 body', () {
    final ctx = ShuyuanSourceContext('src_json_multipart');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      e.eval('''
(function(){
  var b = new Packages.okhttp3.MultipartBody.Builder()
      .addFormDataPart("k","v").build();
  var r = new Packages.okhttp3.Request.Builder()
      .url("https://x.test/upload").post(b).build();
  new Packages.okhttp3.OkHttpClient().newCall(r).execute();
})()''');
      final key = ctx.ajaxPending.last;
      expect(key, contains('||POST||--'));
      expect(key,
          contains('"Content-Type":"multipart/form-data; boundary=----NexHubBoundary'));
      expect(key, contains('Content-Disposition: form-data; name="k"'));
    });
  });
}
