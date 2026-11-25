import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'contracts/work_contract_wizard.dart';

const supaUrl=String.fromEnvironment('SUPABASE_URL');
const supaKey=String.fromEnvironment('SUPABASE_ANON_KEY');
Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 if(supaUrl.startsWith('https://')&&supaKey.isNotEmpty) await Supabase.initialize(url:supaUrl,anonKey:supaKey);
 runApp(const App());
}
class App extends StatelessWidget {
 const App({super.key});
 @override Widget build(BuildContext c)=>MaterialApp(title:'DEALPROOF',debugShowCheckedModeBanner:false,
 theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff16a6a0),brightness:Brightness.dark),scaffoldBackgroundColor:const Color(0xff101719)),
 home:supaUrl.startsWith('https://')&&supaKey.isNotEmpty?const Gate():const Scaffold(body:Center(child:Padding(padding:EdgeInsets.all(24),child:Text('DEALPROOF potřebuje nastavit cloud Supabase. Nejprve vytvoříme cloudový projekt a připojíme jej přes GitHub Secrets.',textAlign:TextAlign.center)))));
}
class Gate extends StatelessWidget {
 const Gate({super.key});
 @override Widget build(BuildContext c)=>StreamBuilder<AuthState>(stream:Supabase.instance.client.auth.onAuthStateChange,builder:(c,s)=>Supabase.instance.client.auth.currentSession==null?const LoginPage():const HomePage());
}
class LoginPage extends StatefulWidget {const LoginPage({super.key});@override State<LoginPage> createState()=>_LoginState();}
class _LoginState extends State<LoginPage>{
 final email=TextEditingController(),pass=TextEditingController(),name=TextEditingController();bool signup=false,busy=false;String error='';
 Future<void> submit() async {setState(()=>busy=true);try{final a=Supabase.instance.client.auth;if(signup){final r=await a.signUp(email:email.text.trim(),password:pass.text,emailRedirectTo:'dealproof://login-callback');if(r.session!=null){try{await Supabase.instance.client.rpc('accept_agreement_invitations');}catch(_){}}if(r.session==null)error='Potvrď registrační e-mail a potom se přihlas.';}else{await a.signInWithPassword(email:email.text.trim(),password:pass.text);try{await Supabase.instance.client.rpc('accept_agreement_invitations');}catch(_){}}}catch(e){
 error=e.toString();
 final checks=<String>[];
 for(final host in [Uri.parse(supaUrl).host,'example.com']){
  try{
   final addresses=await InternetAddress.lookup(host).timeout(const Duration(seconds:8));
   checks.add('$host: OK ('+addresses.map((x)=>x.address).join(', ')+')');
  }catch(d){
   checks.add('$host: CHYBA ('+d.toString()+')');
  }
 }
 error+='\n\nDiagnostika DNS:\n'+checks.join('\n');
}if(mounted)setState(()=>busy=false);}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('DEALPROOF')),body:ListView(padding:const EdgeInsets.all(22),children:[const Icon(Icons.handshake_outlined,size:58,color:Colors.tealAccent),Text(signup?'Registrace':'Přihlášení',style:Theme.of(c).textTheme.headlineMedium),if(signup)TextField(controller:name,decoration:const InputDecoration(labelText:'Jméno')),TextField(controller:email,decoration:const InputDecoration(labelText:'E-mail')),TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'Heslo')),if(error.isNotEmpty)Text(error),FilledButton(onPressed:busy?null:submit,child:Text(signup?'Zaregistrovat':'Přihlásit')),TextButton(onPressed:()=>setState(()=>signup=!signup),child:Text(signup?'Mám účet':'Vytvořit účet'))]));}
class HomePage extends StatefulWidget {const HomePage({super.key});@override State<HomePage> createState()=>_HomeState();}
class _HomeState extends State<HomePage>{
 final db=Supabase.instance.client;List<Map<String,dynamic>> items=[];bool busy=true;
 @override void initState(){super.initState();load();}
 Future<void> load() async {try{items=List<Map<String,dynamic>>.from(await db.from('agreements').select().order('created_at',ascending:false));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}if(mounted)setState(()=>busy=false);}
 Future<void> create() async {
  final draft = await Navigator.of(context).push<WorkContractDraft>(
    MaterialPageRoute(
      builder: (_) => WorkContractWizard(
        initialEmail: db.auth.currentUser?.email ?? '',
      ),
    ),
  );
  if (draft == null) return;

  dynamic id;
  try {
    id = await db.rpc(
      'create_work_agreement_with_invite',
      params: draft.toRpcParams(),
    );
    await load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Smlouva je uložena. Připravuje se pozvánka pro druhou stranu.')),
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Smlouvu se nepodařilo vytvořit: ${e.toString()}')),
      );
    }
    return;
  }

  try {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Pozvánka do smlouvy o dílo v aplikaci DEALPROOF. '
            'Přihlas se e-mailem ${draft.inviteeEmail}. ID dohody: ${id.toString()}',
      ),
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Smlouva je uložena, ale nabídku sdílení pozvánky se nepodařilo otevřít.')),
      );
    }
  }
 }
 Future<void> join() async {try{final r=await db.rpc('accept_agreement_invitations');await load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Přijaté pozvánky: '+(r is List?r.length:0).toString())));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
 @override Widget build(BuildContext c)=>Scaffold(
  appBar:AppBar(title:const Text('DEALPROOF'),actions:[
   IconButton(tooltip:'Přijmout pozvánky',onPressed:join,icon:const Icon(Icons.mark_email_read_outlined)),
   IconButton(tooltip:'Odhlásit',onPressed:()=>db.auth.signOut(),icon:const Icon(Icons.logout))
  ]),
  floatingActionButton:FloatingActionButton.extended(onPressed:create,icon:const Icon(Icons.add),label:const Text('Nová dohoda')),
  body:busy?const Center(child:CircularProgressIndicator()):RefreshIndicator(
   onRefresh:load,
   child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
    Container(
     padding:const EdgeInsets.all(20),
     decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[Color(0xff126d68),Color(0xff183d42)],begin:Alignment.topLeft,end:Alignment.bottomRight)),
     child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.verified_user_outlined,size:34,color:Colors.white),
      SizedBox(height:14),
      Text('Dohody jasně.\nPodmínky černé na bílém.',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold,color:Colors.white)),
      SizedBox(height:8),
      Text('Vytvoř dohodu, pošli ji druhé straně a uchovej si potvrzené znění i všechny dodatky.',style:TextStyle(color:Colors.white70,fontSize:14))
     ])
    ),
    const SizedBox(height:20),
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
     const Text('Moje dohody',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
     Text(items.length.toString()+' celkem',style:TextStyle(color:Theme.of(c).colorScheme.secondary))
    ]),
    const SizedBox(height:10),
    if(items.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
     const Icon(Icons.description_outlined,size:42,color:Colors.tealAccent),
     const SizedBox(height:10),
     const Text('Zatím tu žádná dohoda není',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
     const SizedBox(height:6),
     const Text('Začni výběrem vzoru. Připravili jsme smlouvu o dílo, kupní smlouvu, zápůjčku, nájemní dohodu i vlastní vzor.',textAlign:TextAlign.center),
     const SizedBox(height:12),
     FilledButton.icon(onPressed:create,icon:const Icon(Icons.auto_awesome),label:const Text('Vybrat vzor a začít'))
    ]))),
    ...items.map((x)=>Card(child:ListTile(
     contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:7),
     leading:CircleAvatar(backgroundColor:Colors.teal.withValues(alpha:.18),child:const Icon(Icons.description_outlined,color:Colors.tealAccent)),
     title:Text(x['title']??'Bez názvu',style:const TextStyle(fontWeight:FontWeight.w600)),
     subtitle:Text((x['status']??'').toString()+' • '+(x['currency']??'CZK').toString()),
     trailing:const Icon(Icons.chevron_right),
     onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>DealPage(deal:x))).then((_)=>load())
    )))
   ])
  )
 );
}
class DealPage extends StatefulWidget {const DealPage({super.key,required this.deal});final Map<String,dynamic> deal;@override State<DealPage> createState()=>_DealState();}
class _DealState extends State<DealPage>{
 final db=Supabase.instance.client;List<Map<String,dynamic>> signatures=[],amendments=[],lineItems=[];bool loading=true;
 String get id=>widget.deal['id'].toString();
 String get terms=>(widget.deal['title']??'').toString()+'\n'+(widget.deal['description']??'').toString()+'\n'+(widget.deal['currency']??'CZK').toString();
 String get hash=>(widget.deal['content_hash']??sha256.convert(utf8.encode(terms)).toString()).toString();
 @override void initState(){super.initState();refresh();}
 Future<void> refresh() async {try{signatures=List<Map<String,dynamic>>.from(await db.from('agreement_signatures').select().eq('agreement_id',id));lineItems=List<Map<String,dynamic>>.from(await db.from('agreement_items').select().eq('agreement_id',id).order('position').order('created_at'));amendments=List<Map<String,dynamic>>.from(await db.from('amendments').select().eq('agreement_id',id).order('created_at',ascending:false));}catch(_){}if(mounted)setState(()=>loading=false);}
 Future<void> invite() async {final rows=await db.from('agreement_participants').select('email').eq('agreement_id',id);final emails=(rows as List).where((x)=>x['email']!=null).map((x)=>x['email'].toString()).join(', ');await SharePlus.instance.share(ShareParams(text:'Dohoda DEALPROOF: '+(widget.deal['title']??'').toString()+'. Pozvaný e-mail: '+(emails.isEmpty?'není uveden':emails)+'. Přihlas se v aplikaci stejným e-mailem, pozvánka se přijme automaticky.'));}
 Future<void> sign() async {final n=TextEditingController();final pen=SignatureController(penStrokeWidth:3,penColor:Colors.white,exportBackgroundColor:const Color(0xff202a2d));final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Podepsat dohodu'),content:SizedBox(width:330,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Jméno')),const SizedBox(height:10),Container(height:150,color:const Color(0xff202a2d),child:Signature(controller:pen,backgroundColor:const Color(0xff202a2d))),TextButton(onPressed:pen.clear,child:const Text('Vymazat podpis')),const Text('Podpis prstem není automaticky kvalifikovaný elektronický podpis.',style:TextStyle(fontSize:12))])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Zrušit')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Potvrdit'))]));if(ok==true){try{if(n.text.trim().isEmpty||pen.isEmpty)throw Exception('Vyplň jméno a podpis.');final png=await pen.toPngBytes();if(png==null)throw Exception('Podpis nelze zpracovat.');await db.from('agreement_signatures').insert({'agreement_id':id,'signer_id':db.auth.currentUser!.id,'signer_name':n.text.trim(),'signature_png_base64':base64Encode(png),'terms_hash':hash});await refresh();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}n.dispose();pen.dispose();}
 Future<void> amend() async {final d=TextEditingController(),a=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Návrh dodatku'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:d,decoration:const InputDecoration(labelText:'Co se mění?')),TextField(controller:a,decoration:const InputDecoration(labelText:'Změna ceny'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Zrušit')),FilledButton(onPressed:()=>Navigator.pop(c,d.text.trim().isNotEmpty),child:const Text('Odeslat'))]));if(ok==true){try{await db.from('amendments').insert({'agreement_id':id,'created_by':db.auth.currentUser!.id,'description':d.text.trim(),'price_delta':double.tryParse(a.text.trim().replaceAll(',','.'))??0,'status':'proposed'});await refresh();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}d.dispose();a.dispose();}
 Future<void> decide(Map<String,dynamic> x,bool accept) async {try{await db.from('amendment_signatures').insert({'amendment_id':x['id'],'user_id':db.auth.currentUser!.id,'decision':accept?'accepted':'rejected'});await refresh();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
 Future<void> exportPdf() async {
  try {
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final document = pw.Document(
      title: (widget.deal['title'] ?? 'Dohoda DEALPROOF').toString(),
      author: 'DEALPROOF',
      subject: 'Dohoda a záznam potvrzení',
    );
    final content = (widget.deal['contract_text'] ??
            widget.deal['description'] ??
            'Text smlouvy není k dispozici.')
        .toString();
    final currency = (widget.deal['currency'] ?? 'CZK').toString();
    final widgets = <pw.Widget>[
      pw.Header(
        level: 0,
        child: pw.Text(
          'DEALPROOF — ${(widget.deal['title'] ?? 'Dohoda').toString()}',
          style: pw.TextStyle(font: boldFont, fontSize: 18),
        ),
      ),
      pw.Text('ID dohody: $id',
          style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey700)),
      pw.SizedBox(height: 12),
      pw.Text(content, style: pw.TextStyle(font: regularFont, fontSize: 9.5, lineSpacing: 2)),
      pw.SizedBox(height: 18),
      pw.Header(level: 1, child: pw.Text('Položkový rozpočet', style: pw.TextStyle(font: boldFont))),
    ];

    if (lineItems.isEmpty) {
      widgets.add(pw.Text('K dohodě nejsou uloženy žádné samostatné položky.',
          style: pw.TextStyle(font: regularFont, fontSize: 9)));
    } else {
      for (var i = 0; i < lineItems.length; i++) {
        final item = lineItems[i];
        final quantity = (item['quantity'] as num?) ?? 1;
        final unitPrice = (item['unit_price'] as num?) ?? 0;
        final amount = quantity * unitPrice;
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(
            '${i + 1}. ${item['description']} — $quantity ${item['unit']} × $unitPrice $currency = ${amount.toStringAsFixed(2)} $currency',
            style: pw.TextStyle(font: regularFont, fontSize: 9),
          ),
        ));
      }
    }

    widgets.add(pw.SizedBox(height: 16));
    widgets.add(pw.Header(
      level: 1,
      child: pw.Text('Elektronické potvrzení v aplikaci', style: pw.TextStyle(font: boldFont)),
    ));
    widgets.add(pw.Text('Kontrolní otisk znění (SHA-256): $hash',
        style: pw.TextStyle(font: regularFont, fontSize: 8)));
    widgets.add(pw.SizedBox(height: 8));

    if (signatures.isEmpty) {
      widgets.add(pw.Text('K této dohodě zatím není uložen žádný podpis.',
          style: pw.TextStyle(font: regularFont, fontSize: 9)));
    } else {
      for (final signature in signatures) {
        final signerName = (signature['signer_name'] ?? 'Podepisující').toString();
        final signedAtRaw = signature['signed_at']?.toString() ?? '';
        final signedAt = DateTime.tryParse(signedAtRaw)?.toLocal();
        final signedAtText = signedAt == null
            ? signedAtRaw
            : '${signedAt.day.toString().padLeft(2, '0')}.${signedAt.month.toString().padLeft(2, '0')}.${signedAt.year} ${signedAt.hour.toString().padLeft(2, '0')}:${signedAt.minute.toString().padLeft(2, '0')}';
        widgets.add(pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(signerName, style: pw.TextStyle(font: boldFont, fontSize: 10)),
              pw.Text('Potvrzeno: $signedAtText',
                  style: pw.TextStyle(font: regularFont, fontSize: 8)),
              if ((signature['signature_png_base64'] ?? '').toString().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 5),
                  child: pw.Image(
                    pw.MemoryImage(base64Decode(signature['signature_png_base64'].toString())),
                    height: 42,
                    fit: pw.BoxFit.contain,
                  ),
                ),
            ],
          ),
        ));
      }
    }

    widgets.add(pw.SizedBox(height: 10));
    widgets.add(pw.Text(
      'Poznámka: Tento dokument je exportem obsahu a záznamů uložených v aplikaci DEALPROOF. Potvrzení prstem ani tento export samy o sobě nepředstavují kvalifikovaný elektronický podpis.',
      style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey700),
    ));

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 36, 38, 42),
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Strana ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (context) => widgets,
    ));

    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'DEALPROOF-${safeId.isEmpty ? 'dohoda' : safeId}.pdf',
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF se nepodařilo připravit: $e')),
      );
    }
  }
 }
 Widget section(String title,Widget child)=>Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),const SizedBox(height:10),child])));
 @override Widget build(BuildContext c){final me=db.auth.currentUser!.id;return Scaffold(appBar:AppBar(title:const Text('Dohoda'),actions:[IconButton(tooltip:'Exportovat do PDF',onPressed:exportPdf,icon:const Icon(Icons.picture_as_pdf)),IconButton(onPressed:invite,icon:const Icon(Icons.qr_code_2))]),floatingActionButton:FloatingActionButton.extended(onPressed:amend,icon:const Icon(Icons.edit_note),label:const Text('Dodatek')),body:ListView(padding:const EdgeInsets.all(14),children:[
 Text(widget.deal['title']??'',style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
 section('Text smlouvy',Text((widget.deal['contract_text']??widget.deal['description']??'').toString()+'\nStav: '+(widget.deal['status']??'').toString()+'\nMěna: '+(widget.deal['currency']??'CZK').toString())),
 section('Položky dohody',Column(children:[if(lineItems.isEmpty)const Text('Bez položek.'),...lineItems.map((it)=>ListTile(title:Text(it['description']??''),subtitle:Text((it['quantity']??1).toString()+' '+(it['unit']??'ks')+' × '+(it['unit_price']??0).toString()+' '+(widget.deal['currency']??'CZK').toString())))])),
 section('Podpisy ('+signatures.length.toString()+'/2)',Column(children:[if(loading)const LinearProgressIndicator(),...signatures.map((s)=>ListTile(title:Text(s['signer_name']??''),subtitle:Text('Podepsáno: '+s['signed_at'].toString()))),if(signatures.isEmpty)const Text('Zatím nikdo nepodepsal.'),if(!signatures.any((s)=>s['signer_id']==me))FilledButton.icon(onPressed:sign,icon:const Icon(Icons.draw),label:const Text('Zkontrolovat a podepsat'))])),
 section('Dodatky – původní dohoda se nepřepisuje',Column(children:[if(amendments.isEmpty)const Text('Zatím žádné dodatky.'),...amendments.map((x){final mine=x['created_by']==me;final pending=x['status']=='proposed';return ListTile(title:Text(x['description']),subtitle:Text('Změna ceny: '+(x['price_delta']??0).toString()+' • '+x['status'].toString()),trailing:pending&&!mine?Wrap(children:[IconButton(onPressed:()=>decide(x,true),icon:const Icon(Icons.check,color:Colors.green)),IconButton(onPressed:()=>decide(x,false),icon:const Icon(Icons.close,color:Colors.red))]):null);})])),
 ]));}
}
