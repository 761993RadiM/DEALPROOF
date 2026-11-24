import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const DealProofApp());
}

class DealProofApp extends StatelessWidget {
  const DealProofApp({super.key});
  @override
  Widget build(BuildContext context) {
    final ready = supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
    return MaterialApp(
      title: 'DEALPROOF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16a6a0), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xff101719)),
      home: !ready ? const SetupPage() : StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, snapshot) => db.auth.currentSession == null ? const LoginPage() : const HomePage(),
      ),
    );
  }
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Padding(
    padding: EdgeInsets.all(24),
    child: Text('DEALPROOF čeká na nastavení Supabase. Použij pouze veřejný publishable/anon klíč, nikdy service-role klíč.', textAlign: TextAlign.center),
  )));
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String message = '';
  Future<void> submit() async {
    setState(() { busy = true; message = ''; });
    try {
      if (register) {
        final result = await db.auth.signUp(email: email.text.trim(), password: password.text);
        message = result.session == null ? 'Registrace proběhla. Potvrď e-mail a potom se přihlas.' : 'Účet byl vytvořen.';
      } else {
        await db.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) { message = e.message; }
      catch (e) { message = e.toString(); }
    if (mounted) setState(() => busy = false);
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('DEALPROOF')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.handshake_outlined, size: 64, color: Colors.tealAccent),
      Text(register ? 'Vytvořit účet' : 'Přihlášení', style: Theme.of(context).textTheme.headlineMedium),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Heslo')),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(message)),
      FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Pracuji…' : (register ? 'Zaregistrovat' : 'Přihlásit'))),
      TextButton(onPressed: () => setState(() { register = !register; message = ''; }), child: Text(register ? 'Už mám účet' : 'Vytvořit účet')),
    ]));
}

String statusLabel(String value) {
  switch (value) {
    case 'draft': return 'Rozpracovaná';
    case 'shared': return 'Odeslaná k podpisu';
    case 'accepted': return 'Potvrzená oběma stranami';
    case 'rejected': return 'Zamítnutá';
    case 'proposed': return 'Čeká na rozhodnutí';
    default: return value;
  }
}
double numValue(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<Map<String,dynamic>> agreements = [];
  bool busy = true;
  String error = '';
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { busy = true; error = ''; });
    try {
      await db.rpc('accept_agreement_invitations');
      final rows = await db.from('agreements').select().order('created_at', ascending: false);
      agreements = List<Map<String,dynamic>>.from(rows);
    } catch (e) {
      try {
        final rows = await db.from('agreements').select().order('created_at', ascending: false);
        agreements = List<Map<String,dynamic>>.from(rows);
      } catch (queryError) { error = queryError.toString(); }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> createAgreement() async {
    final title = TextEditingController(), description = TextEditingController();
    final item = TextEditingController(), qty = TextEditingController(text: '1');
    final unit = TextEditingController(text: 'ks'), price = TextEditingController(text: '0');
    final currency = TextEditingController(text: 'CZK'), invite = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Nová dohoda'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Název dohody *')),
        TextField(controller: description, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Podmínky a rozsah')),
        const Divider(),
        TextField(controller: item, decoration: const InputDecoration(labelText: 'Položka / práce *')),
        Row(children: [
          Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Množství'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Jednotka'))),
        ]),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cena za jednotku')),
        TextField(controller: currency, decoration: const InputDecoration(labelText: 'Měna')),
        const Divider(),
        TextField(controller: invite, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail druhé strany (volitelné)')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vytvořit')),
      ],
    ));
    if (ok == true) {
      try {
        final q = double.tryParse(qty.text.replaceAll(',', '.'));
        final p = double.tryParse(price.text.replaceAll(',', '.'));
        if (title.text.trim().isEmpty || item.text.trim().isEmpty || q == null || q <= 0 || p == null || p < 0) {
          throw Exception('Vyplň název, položku, množství a platnou cenu.');
        }
        final agreement = await db.from('agreements').insert({
          'created_by': db.auth.currentUser!.id,
          'title': title.text.trim(),
          'description': description.text.trim(),
          'currency': currency.text.trim().isEmpty ? 'CZK' : currency.text.trim().toUpperCase(),
          'status': 'draft',
        }).select().single();
        await db.from('agreement_items').insert({
          'agreement_id': agreement['id'], 'description': item.text.trim(),
          'quantity': q, 'unit': unit.text.trim().isEmpty ? 'ks' : unit.text.trim(), 'unit_price': p,
        });
        if (invite.text.trim().isNotEmpty) {
          final address = invite.text.trim().toLowerCase();
          if (!address.contains('@')) throw Exception('Zkontroluj e-mail druhé strany.');
          await db.from('agreement_participants').insert({
            'agreement_id': agreement['id'], 'email': address, 'role': 'participant',
          });
          await db.from('agreements').update({'status': 'shared'}).eq('id', agreement['id']);
          await SharePlus.instance.share(ShareParams(
            text: 'Byl(a) jsi pozván(a) do dohody DEALPROOF. Přihlas se nebo si vytvoř účet v aplikaci se stejnou e-mailovou adresou: ' + address,
          ));
        }
        await load();
      } catch (e) { if (mounted) showError(e); }
    }
    for (final c in [title, description, item, qty, unit, price, currency, invite]) { c.dispose(); }
  }
  void showError(Object e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DEALPROOF'), actions: [
      IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      IconButton(onPressed: () => db.auth.signOut(), icon: const Icon(Icons.logout)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: createAgreement, icon: const Icon(Icons.add), label: const Text('Nová dohoda')),
    body: busy ? const Center(child: CircularProgressIndicator()) :
      error.isNotEmpty ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(error))) :
      agreements.isEmpty ? const Center(child: Text('Zatím nemáš žádné dohody. Vytvoř novou nebo přijmi e-mailovou pozvánku.')) :
      RefreshIndicator(onRefresh: load, child: ListView.builder(padding: const EdgeInsets.only(bottom: 90),
        itemCount: agreements.length, itemBuilder: (c, i) {
          final a = agreements[i];
          return Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
            title: Text(a['title']?.toString() ?? ''),
            subtitle: Text(statusLabel(a['status']?.toString() ?? 'draft') + ' • ' + (a['currency']?.toString() ?? 'CZK')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => AgreementPage(agreement: a))).then((_) => load()),
          ));
        })),
  );
}

class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key, required this.agreement});
  final Map<String,dynamic> agreement;
  @override
  State<AgreementPage> createState() => _AgreementPageState();
}
class _AgreementPageState extends State<AgreementPage> {
  List<Map<String,dynamic>> items = [], participants = [], signatures = [], amendments = [], decisions = [];
  bool busy = true;
  String get id => widget.agreement['id'].toString();
  String get me => db.auth.currentUser!.id;
  bool get owner => widget.agreement['created_by'] == me;
  String get currency => widget.agreement['currency']?.toString() ?? 'CZK';
  double get total => items.fold<double>(0, (s, x) => s + numValue(x['quantity']) * numValue(x['unit_price']));
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final r = await Future.wait([
        db.from('agreement_items').select().eq('agreement_id', id).order('created_at'),
        db.from('agreement_participants').select().eq('agreement_id', id),
        db.from('agreement_signatures').select().eq('agreement_id', id).order('signed_at'),
        db.from('amendments').select().eq('agreement_id', id).order('created_at', ascending: false),
      ]);
      items = List<Map<String,dynamic>>.from(r[0]);
      participants = List<Map<String,dynamic>>.from(r[1]);
      signatures = List<Map<String,dynamic>>.from(r[2]);
      amendments = List<Map<String,dynamic>>.from(r[3]);
      if (amendments.isNotEmpty) {
        final ids = amendments.map((x) => x['id']).toList();
        decisions = List<Map<String,dynamic>>.from(await db.from('amendment_signatures').select().inFilter('amendment_id', ids));
      } else { decisions = []; }
    } catch (e) { if (mounted) showError(e); }
    if (mounted) setState(() => busy = false);
  }
  void showError(Object e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  String get termsHash {
    final data = {
      'title': widget.agreement['title'],
      'description': widget.agreement['description'],
      'currency': currency,
      'items': items.map((x) => {
        'description': x['description'], 'quantity': x['quantity'],
        'unit': x['unit'], 'unit_price': x['unit_price'],
      }).toList(),
    };
    return sha256.convert(utf8.encode(jsonEncode(data))).toString();
  }

  Future<void> invite() async {
    final email = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('Pozvat druhou stranu'),
      content: TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zrušit')),
        FilledButton(onPressed: () => Navigator.pop(c, email.text.trim()), child: const Text('Pozvat')),
      ],
    ));
    if (value != null && value.isNotEmpty) {
      try {
        if (!value.contains('@')) throw Exception('Zadej platný e-mail.');
        await db.from('agreement_participants').insert({'agreement_id': id, 'email': value.toLowerCase(), 'role': 'participant'});
        await db.from('agreements').update({'status': 'shared'}).eq('id', id);
        await SharePlus.instance.share(ShareParams(text: 'Pozvánka do dohody DEALPROOF. Přihlas se nebo vytvoř účet se stejnou e-mailovou adresou: ' + value));
        await refresh();
      } catch (e) { if (mounted) showError(e); }
    }
    email.dispose();
  }

  Future<void> sign() async {
    final name = TextEditingController();
    final pen = SignatureController(penStrokeWidth: 3, penColor: Colors.white, exportBackgroundColor: const Color(0xff202a2d));
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Podepsat dohodu'),
      content: SizedBox(width: 350, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Jméno a příjmení')),
        const SizedBox(height: 10),
        Container(height: 150, color: const Color(0xff202a2d), child: Signature(controller: pen, backgroundColor: const Color(0xff202a2d))),
        TextButton(onPressed: pen.clear, child: const Text('Vymazat podpis')),
        const Text('Podpis prstem je elektronický záznam souhlasu, nikoli automaticky kvalifikovaný elektronický podpis.', style: TextStyle(fontSize: 11)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Potvrdit podpis')),
      ],
    ));
    if (ok == true) {
      try {
        if (name.text.trim().isEmpty || pen.isEmpty) throw Exception('Vyplň jméno a podpis.');
        final png = await pen.toPngBytes();
        if (png == null) throw Exception('Podpis nelze zpracovat.');
        await db.from('agreement_signatures').insert({
          'agreement_id': id, 'signer_id': me, 'signer_name': name.text.trim(),
          'signature_png_base64': base64Encode(png), 'terms_hash': termsHash,
        });
        await refresh();
      } catch (e) { if (mounted) showError(e); }
    }
    name.dispose(); pen.dispose();
  }

  Future<void> proposeAmendment() async {
    final description = TextEditingController(), delta = TextEditingController(text: '0'), date = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Návrh dodatku'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: description, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Co se mění?')),
        TextField(controller: delta, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Změna ceny (+ / −)')),
        TextField(controller: date, decoration: const InputDecoration(labelText: 'Nový termín RRRR-MM-DD (volitelné)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Odeslat')),
      ],
    ));
    if (ok == true) {
      try {
        final amount = double.tryParse(delta.text.replaceAll(',', '.'));
        if (description.text.trim().isEmpty || amount == null) throw Exception('Vyplň popis a platnou změnu ceny.');
        final d = date.text.trim();
        if (d.isNotEmpty) DateTime.parse(d);
        await db.from('amendments').insert({
          'agreement_id': id, 'created_by': me, 'description': description.text.trim(),
          'price_delta': amount, 'due_date': d.isEmpty ? null : d, 'status': 'proposed',
        });
        await refresh();
      } catch (e) { if (mounted) showError(e); }
    }
    description.dispose(); delta.dispose(); date.dispose();
  }

  Future<void> decide(Map<String,dynamic> amendment, String choice) async {
    try {
      await db.from('amendment_signatures').insert({
        'amendment_id': amendment['id'], 'user_id': me, 'decision': choice,
      });
      await refresh();
    } catch (e) { if (mounted) showError(e); }
  }

  Future<void> exportPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(build: (context) => [
      pw.Text('DEALPROOF', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      pw.Text(widget.agreement['title']?.toString() ?? ''),
      pw.Text(widget.agreement['description']?.toString() ?? ''),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Položka', 'Množství', 'Jednotka', 'Cena / jednotka', 'Celkem'],
        data: items.map((x) {
          final q = numValue(x['quantity']), p = numValue(x['unit_price']);
          return [x['description'].toString(), q.toString(), x['unit'].toString(), p.toStringAsFixed(2), (q*p).toStringAsFixed(2)];
        }).toList(),
      ),
      pw.SizedBox(height: 10),
      pw.Text('Celkem: ' + total.toStringAsFixed(2) + ' ' + currency),
      pw.SizedBox(height: 16),
      pw.Text('Stav: ' + statusLabel(widget.agreement['status'].toString())),
      pw.Text('Podpisové záznamy', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ...signatures.map((s) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(s['signer_name'].toString() + ' — ' + s['signed_at'].toString()),
        pw.SizedBox(height: 4),
        pw.Image(pw.MemoryImage(base64Decode(s['signature_png_base64'].toString())), width: 150, height: 60, fit: pw.BoxFit.contain),
      ])),
      pw.SizedBox(height: 14),
      pw.Text('Export záznamů aplikace. Právní účinky elektronického podpisu se posuzují podle okolností a právních předpisů.', style: const pw.TextStyle(fontSize: 9)),
    ]));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'dealproof-' + id.substring(0, 8) + '.pdf');
  }

  Widget section(String title, Widget child) => Card(child: Padding(
    padding: const EdgeInsets.all(15),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10), child,
    ]),
  ));

  @override
  Widget build(BuildContext context) {
    final status = widget.agreement['status']?.toString() ?? 'draft';
    final signed = signatures.any((s) => s['signer_id'] == me);
    return Scaffold(
      appBar: AppBar(title: const Text('Dohoda'), actions: [
        IconButton(tooltip: 'PDF', onPressed: exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: (status == 'shared' || status == 'accepted')
        ? FloatingActionButton.extended(onPressed: proposeAmendment, icon: const Icon(Icons.edit_note), label: const Text('Dodatek'))
        : null,
      body: busy ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(14), children: [
        Text(widget.agreement['title']?.toString() ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(statusLabel(status) + ' • ' + currency),
        section('Podmínky', Text(widget.agreement['description']?.toString() ?? '')),
        section('Položky a cena', Column(children: [
          ...items.map((x) {
            final q = numValue(x['quantity']), p = numValue(x['unit_price']);
            return ListTile(contentPadding: EdgeInsets.zero, title: Text(x['description'].toString()),
              subtitle: Text(q.toString() + ' ' + x['unit'].toString() + ' × ' + p.toStringAsFixed(2) + ' ' + currency),
              trailing: Text((q*p).toStringAsFixed(2) + ' ' + currency));
          }),
          const Divider(),
          Align(alignment: Alignment.centerRight, child: Text('Celkem: ' + total.toStringAsFixed(2) + ' ' + currency, style: const TextStyle(fontWeight: FontWeight.bold))),
        ])),
        section('Účastníci', Column(children: [
          ...participants.map((p) => ListTile(contentPadding: EdgeInsets.zero,
            leading: Icon(p['user_id'] == null ? Icons.mail_outline : Icons.person_outline),
            title: Text(p['role'] == 'owner' ? 'Vlastník dohody' : 'Druhá strana'),
            subtitle: Text(p['email']?.toString() ?? (p['user_id'] == me ? 'Tvůj účet' : 'Účet připojen')))),
          if (owner && status == 'draft')
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: invite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Pozvat e-mailem a odeslat'))),
        ])),
        section('Podpisy (' + signatures.length.toString() + '/2)', Column(children: [
          ...signatures.map((s) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.verified_user_outlined),
            title: Text(s['signer_name'].toString()), subtitle: Text('Podepsáno: ' + s['signed_at'].toString()))),
          if (status == 'shared' && !signed)
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: sign, icon: const Icon(Icons.draw), label: const Text('Zkontrolovat a podepsat'))),
          if (status == 'accepted') const Text('Dohoda byla potvrzena oběma účastníky.'),
        ])),
        section('Dodatky – původní dohoda se nepřepisuje', Column(children: [
          if (amendments.isEmpty) const Text('Zatím žádné dodatky.'),
          ...amendments.map((a) {
            final mine = a['created_by'] == me;
            final pending = a['status'] == 'proposed';
            final decided = decisions.any((s) => s['amendment_id'] == a['id'] && s['user_id'] == me);
            final delta = numValue(a['price_delta']);
            return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['description'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Změna ceny: ' + (delta >= 0 ? '+' : '') + delta.toStringAsFixed(2) + ' ' + currency),
              if (a['due_date'] != null) Text('Nový termín: ' + a['due_date'].toString()),
              Text('Stav: ' + statusLabel(a['status'].toString())),
              if (pending && !mine && !decided) Wrap(children: [
                TextButton.icon(onPressed: () => decide(a, 'accepted'), icon: const Icon(Icons.check), label: const Text('Souhlasím')),
                TextButton.icon(onPressed: () => decide(a, 'rejected'), icon: const Icon(Icons.close), label: const Text('Nesouhlasím')),
              ]),
              if (pending && mine) const Text('Čeká na rozhodnutí druhé strany.'),
            ])));
          }),
        ])),
      ]),
    );
  }
}
