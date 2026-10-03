@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;

import 'package:comic_read/frequency/web_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A valid one-pixel PNG keeps navigation tests independent of asset loading.
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=';
const pages = [
  ComicPage('z-page', '第一页', png, embedded: true),
  ComicPage('a-page', '第二页', png, embedded: true),
];
const progressKey = 'frequency.comic.progress.test-album';

void clearStorage() {
  for (final key in html.window.localStorage.keys.toList()) {
    if (key.startsWith('frequency.comic.'))
      html.window.localStorage.remove(key);
  }
}

Future<void> mount(WidgetTester tester, Widget widget) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    clearStorage();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {

  setUp(clearStorage);

  test('图册 JSON 保留导入顺序、图像字节和嵌入标记', () {
    final restored =
        (jsonDecode(jsonEncode(pages.map((p) => p.toJson()).toList())) as List)
            .map((p) => ComicPage.fromJson(p as Map<String, dynamic>))
            .toList();
    expect(restored.map((p) => p.id), ['z-page', 'a-page']);
    expect(restored.map((p) => p.toJson()).toList(),
        pages.map((p) => p.toJson()).toList());
    expect(base64Decode(restored.first.path), base64Decode(png));
    expect(restored.every((p) => p.embedded), isTrue);
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets('图像阅览入口在 ${width.toInt()}px 显示本地样例', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await mount(tester, const ComicApp());
      expect(find.text('图像阅览'), findsOneWidget);
      expect(find.text('收听夜晚'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '打开图册'))
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('本地书目损坏时保留原数据和原创故事入口', (tester) async {
    html.window.localStorage['frequency.comic.pages.v1'] = '{broken';
    await mount(tester, const ComicApp());
    expect(find.text('本地图像书目读取失败。原有数据保留，可重新导入。'), findsOneWidget);
    expect(find.text('打开故事'), findsOneWidget);
    expect(html.window.localStorage['frequency.comic.pages.v1'], '{broken');
  });

  testWidgets('续读按页 ID 恢复并在翻页时重置缩放和进度', (tester) async {
    html.window.localStorage[progressKey] =
        jsonEncode({'page': 'a-page', 'fraction': 0});
    await mount(
        tester,
        const MaterialApp(
          home: ComicRead(id: 'test-album', title: '测试图册', pages: pages),
        ));
    expect(find.text('第 2 / 2 页'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '已到末页'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('放大'));
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
    await tester.tap(find.text('上一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    final saved = jsonDecode(html.window.localStorage[progressKey]!);
    expect(saved['page'], 'z-page');
    expect(saved['fraction'], 0);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '上一页'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('放大限制为 300% 且适合宽度恢复真实变换矩阵', (tester) async {
    await mount(
        tester,
        const MaterialApp(
          home: ComicRead(id: 'test-album', title: '测试图册', pages: pages),
        ));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
    }
    expect(find.text('300%'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '放大')).onPressed, isNull);
    var viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 3);
    await tester.tap(find.text('适合宽度'));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '缩小')).onPressed, isNull);
  });

  testWidgets('损坏图像显示错误与重试按钮', (tester) async {
    await mount(
        tester,
        const MaterialApp(
            home: ComicRead(
          id: 'broken',
          title: '损坏图册',
          pages: [ComicPage('broken', '损坏页', '%%%not-base64', embedded: true)],
        )));
    expect(find.text('这一页无法显示。图像可能缺失或格式不受支持。'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    expect(find.text('这一页无法显示。图像可能缺失或格式不受支持。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空图册不建立虚假页码或进度', (tester) async {
    await mount(
        tester,
        const MaterialApp(
            home: ComicRead(
          id: 'test-album',
          title: '空图册',
          pages: [],
        )));
    expect(find.text('图册里还没有图片。'), findsOneWidget);
    expect(find.text('下一页'), findsNothing);
    expect(html.window.localStorage[progressKey], isNull);
  });
}
