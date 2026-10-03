import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_common/flutter_common.dart';
import 'browser_io.dart';

void start() => runApp(const ComicApp());

class ComicPage {
  final String id, title, path;
  final bool embedded;
  const ComicPage(this.id, this.title, this.path, {this.embedded = false});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'path': path, 'embedded': embedded};
  factory ComicPage.fromJson(Map<String, dynamic> j) => ComicPage(j['id'] as String, j['title'] as String, j['path'] as String, embedded: j['embedded'] == true);
}

class ComicApp extends StatelessWidget {
  const ComicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: '图像阅览 · 频率站', debugShowCheckedModeBanner: false, theme: FrequencyTheme.dark(), home: const ComicShelf());
}

class ComicShelf extends StatefulWidget {
  const ComicShelf({super.key});
  @override
  State<ComicShelf> createState() => _ComicShelfState();
}

class _ComicShelfState extends State<ComicShelf> {
  final pages = <ComicPage>[];
  String error = '';
  static const samplePages = [ComicPage('radio-moth-v1', '收听夜晚 · 六格故事', 'assets/images/frequency-story.webp')];
  @override
  void initState() {
    super.initState();
    try { final raw = readLocal('frequency.comic.pages.v1'); if (raw != null) pages.addAll((jsonDecode(raw) as List).map((p) => ComicPage.fromJson(p as Map<String, dynamic>))); }
    catch (_) { error = '本地图像书目读取失败。原有数据保留，可重新导入。'; }
  }
  Future<void> addPage() async {
    try {
      final file = await pickFile('.png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp', maxBytes: 3 * 1024 * 1024);
      if (file == null || !mounted) return;
      if (file.bytes.isEmpty) throw StateError('图像文件为空');
      final next = [...pages, ComicPage('image-${DateTime.now().microsecondsSinceEpoch}', file.name, base64Encode(file.bytes), embedded: true)];
      writeLocal('frequency.comic.pages.v1', jsonEncode(next.map((p) => p.toJson()).toList()));
      setState(() { pages.clear(); pages.addAll(next); error = ''; });
    } catch (e) { if (mounted) setState(() => error = '导入失败：$e。原有图像未改变，可使用较小的 PNG/JPG/WebP。'); }
  }
  Future<void> open(String id, String title, List<ComicPage> content) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ComicRead(id: id, title: title, pages: List.of(content))));
    if (mounted) setState(() {});
  }
  bool hasProgress(String id) { try { return readLocal('frequency.comic.progress.$id') != null; } catch (_) { return false; } }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('图像阅览'), actions: [TextButton.icon(onPressed: addPage, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('导入图片')), const SizedBox(width: 12)]), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: ListView(padding: const EdgeInsets.all(24), children: [
    const Text('READING / 02', style: TextStyle(color: FrequencyPalette.accent, fontSize: 12)), const SizedBox(height: 12), const Text('把夜晚，\n翻成一页故事。', style: TextStyle(fontSize: 40, height: 1.2, fontWeight: FontWeight.w700)), const SizedBox(height: 16), const Text('看图、缩放、接着读。也可以按顺序导入自己的图片，组成一本本地图册。', style: TextStyle(color: FrequencyPalette.muted)), const SizedBox(height: 32),
    if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 24), child: Text(error, style: const TextStyle(color: FrequencyPalette.error))),
    Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.auto_stories_outlined, color: FrequencyPalette.accent, size: 32), const SizedBox(width: 16), const Expanded(child: Text('收听夜晚', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)))]), const SizedBox(height: 16), const Text('AI 生成原创视觉样例 · 一页六格无字短篇', style: TextStyle(color: FrequencyPalette.muted)), const SizedBox(height: 12), const Text('修理铺的记录员听见神秘频率，跟随一只发光的机械飞蛾来到屋顶，在黎明把发现写进笔记。'), const SizedBox(height: 24), FilledButton.icon(onPressed: () => open('sample-moth-v1', '收听夜晚', samplePages), icon: const Icon(Icons.arrow_forward), label: Text(hasProgress('sample-moth-v1') ? '继续看图' : '打开故事'))]))),
    const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('我的本地图册', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)), const SizedBox(height: 12), Text(pages.isEmpty ? '还没有图片。每次导入一张，按导入顺序排列；单张不超过 3 MB。' : '${pages.length} 页 · 图片与进度只保存在本浏览器', style: const TextStyle(color: FrequencyPalette.muted)), const SizedBox(height: 20), Wrap(spacing: 12, runSpacing: 8, children: [FilledButton.icon(onPressed: pages.isEmpty ? null : () => open('personal-v1', '我的本地图册', pages), icon: const Icon(Icons.menu_book), label: const Text('打开图册')), OutlinedButton.icon(onPressed: addPage, icon: const Icon(Icons.add), label: const Text('添加一页'))])]))),
  ]))));
}

class ComicRead extends StatefulWidget {
  final String id, title;
  final List<ComicPage> pages;
  const ComicRead({super.key, required this.id, required this.title, required this.pages});
  @override
  State<ComicRead> createState() => _ComicReadState();
}

class _ComicReadState extends State<ComicRead> {
  bool exiting = false;
  final scaffold = GlobalKey<ScaffoldState>();
  final scroll = ScrollController();
  final transform = TransformationController();
  Timer? debounce;
  int index = 0, attempt = 0;
  double scale = 1;
  double savedFraction = 0;
  double? pendingFraction;
  String status = '';
  @override
  void initState() {
    super.initState();
    double fraction = 0;
    try {
      final raw = readLocal(key);
      if (raw != null) { final p = jsonDecode(raw); final found = widget.pages.indexWhere((page) => page.id == p['page']); if (found >= 0) { index = found; fraction = (p['fraction'] as num? ?? 0).toDouble().clamp(0, 1); } }
    } catch (_) { status = '本地进度不可读，从第一页开始。'; }
    pendingFraction = fraction;
    savedFraction = fraction;
    scroll.addListener(() { cachePosition(); debounce?.cancel(); debounce = Timer(const Duration(milliseconds: 500), save); });
  }
  String get key => 'frequency.comic.progress.${widget.id}';
  void cachePosition() {
    if (pendingFraction == null && scroll.hasClients) {
      final max = scroll.position.maxScrollExtent;
      savedFraction = max > 0 ? (scroll.offset / max).clamp(0, 1) : 0;
    }
  }
  void save() {
    if (widget.pages.isEmpty) return;
    try { cachePosition(); writeLocal(key, jsonEncode({'page': widget.pages[index].id, 'fraction': savedFraction})); }
    catch (_) { if (mounted && !exiting && status.isEmpty) setState(() => status = '本浏览器未能保存进度。仍可继续看图。'); }
  }
  void select(int next) {
    if (next < 0 || next >= widget.pages.length) return;
    debounce?.cancel();
    setState(() { index = next; attempt = 0; scale = 1; pendingFraction = null; savedFraction = 0; });
    transform.value = Matrix4.identity();
    if (scroll.hasClients) scroll.jumpTo(0);
    save();
  }
  void zoom(double value) { setState(() => scale = value); transform.value = Matrix4.identity()..scale(value); }
  @override
  void dispose() { exiting = true; debounce?.cancel(); save(); scroll.dispose(); transform.dispose(); super.dispose(); }
  Widget failure() => Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.broken_image_outlined, size: 48, color: FrequencyPalette.error), const SizedBox(height: 16), const Text('这一页无法显示。图像可能缺失或格式不受支持。', textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: () => setState(() => attempt++), icon: const Icon(Icons.refresh), label: const Text('重新加载'))]));
  Widget restoreWhenLoaded(BuildContext context, Widget child, int? frame, bool synchronous) {
    if (frame != null && pendingFraction != null) {
      final fraction = pendingFraction!;
      pendingFraction = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent * fraction);
      });
    }
    return child;
  }
  Widget picture(ComicPage page) {
    if (page.embedded) {
      try { return Image.memory(Uint8List.fromList(base64Decode(page.path)), key: ValueKey('${page.id}:$attempt'), fit: BoxFit.contain, frameBuilder: restoreWhenLoaded, errorBuilder: (_, __, ___) => failure()); }
      catch (_) { return failure(); }
    }
    return Image.asset(page.path, key: ValueKey('${page.id}:$attempt'), fit: BoxFit.contain, frameBuilder: restoreWhenLoaded, errorBuilder: (_, __, ___) => failure());
  }
  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: Text('图册里还没有图片。')));
    return Scaffold(key: scaffold, appBar: AppBar(leading: IconButton(tooltip: '返回书目', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)), title: Text(widget.title), actions: [IconButton(tooltip: '页目录', onPressed: () => scaffold.currentState?.openDrawer(), icon: const Icon(Icons.format_list_numbered))]), drawer: Drawer(child: SafeArea(child: Column(children: [Padding(padding: const EdgeInsets.all(24), child: Text(widget.title, style: const TextStyle(fontSize: 24))), Expanded(child: ListView(children: [for (int i = 0; i < widget.pages.length; i++) ListTile(selected: i == index, leading: Text('${i + 1}'), title: Text(widget.pages[i].title), onTap: () { select(i); Navigator.pop(context); })]))]))), body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.center, children: [Text('第 ${index + 1} / ${widget.pages.length} 页'), IconButton(tooltip: '缩小', onPressed: scale > 1 ? () => zoom((scale - .5).clamp(1, 3)) : null, icon: const Icon(Icons.zoom_out)), Text('${(scale * 100).round()}%'), IconButton(tooltip: '放大', onPressed: scale < 3 ? () => zoom((scale + .5).clamp(1, 3)) : null, icon: const Icon(Icons.zoom_in)), TextButton(onPressed: () => zoom(1), child: const Text('适合宽度'))])),
      if (status.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(status, style: const TextStyle(color: FrequencyPalette.amber))),
      Expanded(child: SingleChildScrollView(controller: scroll, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: InteractiveViewer(transformationController: transform, minScale: 1, maxScale: 3, panEnabled: scale > 1, onInteractionEnd: (_) { if (mounted) setState(() => scale = transform.value.getMaxScaleOnAxis()); }, child: Padding(padding: const EdgeInsets.all(12), child: picture(widget.pages[index]))))))),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: index > 0 ? () => select(index - 1) : null, icon: const Icon(Icons.chevron_left), label: const Text('上一页'))), const SizedBox(width: 16), Expanded(child: FilledButton.icon(onPressed: index < widget.pages.length - 1 ? () => select(index + 1) : null, icon: const Icon(Icons.chevron_right), label: Text(index == widget.pages.length - 1 ? '已到末页' : '下一页')))]))),
    ]));
  }
}
