import 'package:flutter/material.dart';

void main() => runApp(const DealProofApp());

class DealProofApp extends StatelessWidget {
  const DealProofApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DEALPROOF',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF16A6A0),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF101719),
          cardTheme: CardThemeData(
            color: const Color(0xFF1A2427),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF1A2427),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        home: const DealsPage(),
      );
}

class Deal {
  Deal({
    required this.title,
    required this.otherParty,
    required this.description,
    required this.amount,
  });

  final String title;
  final String otherParty;
  final String description;
  final String amount;
  final DateTime createdAt = DateTime.now();
  final List<Amendment> amendments = [];
  bool confirmedByMe = false;
  bool confirmedByOther = false;
}

class Amendment {
  Amendment(this.description, this.priceChange)
      : proposedAt = DateTime.now();

  final String description;
  final String priceChange;
  final DateTime proposedAt;
  String status = 'Čeká na odpověď';
}

class DealsPage extends StatefulWidget {
  const DealsPage({super.key});

  @override
  State<DealsPage> createState() => _DealsPageState();
}

class _DealsPageState extends State<DealsPage> {
  final List<Deal> deals = [];

  Future<void> createDeal() async {
    final deal = await Navigator.push<Deal>(
      context,
      MaterialPageRoute(builder: (_) => const CreateDealPage()),
    );
    if (deal != null && mounted) setState(() => deals.insert(0, deal));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('DEALPROOF',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => showAboutDialog(
                context: context,
                applicationName: 'DEALPROOF',
                applicationVersion: '0.1.0',
                children: const [
                  Text('První prototyp. Cloudové účty a sdílení budou doplněny.'),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: createDeal,
          icon: const Icon(Icons.add),
          label: const Text('Nová dohoda'),
        ),
        body: deals.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.handshake_outlined,
                          size: 64, color: Color(0xFF16A6A0)),
                      const SizedBox(height: 18),
                      const Text(
                        'Dohody přehledně a na jednom místě',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Zaznamenej, na čem jste se domluvili.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: createDeal,
                        icon: const Icon(Icons.add),
                        label: const Text('Vytvořit dohodu'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: deals.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final deal = deals[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(deal.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          'Druhá strana: ${deal.otherParty}\n'
                          '${deal.amount.isEmpty ? 'Cena neuvedena' : deal.amount}',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DealDetailPage(deal: deal),
                        ),
                      ).then((_) => setState(() {})),
                    ),
                  );
                },
              ),
      );
}

class CreateDealPage extends StatefulWidget {
  const CreateDealPage({super.key});

  @override
  State<CreateDealPage> createState() => _CreateDealPageState();
}

class _CreateDealPageState extends State<CreateDealPage> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final otherParty = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    otherParty.dispose();
    description.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nová dohoda')),
        body: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Název dohody *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Vyplň název dohody' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: otherParty,
                decoration: const InputDecoration(labelText: 'Druhá strana *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Vyplň druhou stranu' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amount,
                decoration: const InputDecoration(
                    labelText: 'Cena / částka (nepovinné)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'Popis podmínek a rozsahu',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    Deal(
                      title: title.text.trim(),
                      otherParty: otherParty.text.trim(),
                      description: description.text.trim(),
                      amount: amount.text.trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Uložit dohodu'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Prototyp zatím ukládá data pouze do paměti. Po restartu aplikace zmizí a druhá strana je neuvidí.',
              ),
            ],
          ),
        ),
      );
}

class DealDetailPage extends StatefulWidget {
  const DealDetailPage({super.key, required this.deal});
  final Deal deal;

  @override
  State<DealDetailPage> createState() => _DealDetailPageState();
}

class _DealDetailPageState extends State<DealDetailPage> {
  Future<void> proposeAmendment() async {
    final description = TextEditingController();
    final price = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Navrhnout dodatek'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Co se má změnit?'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: price,
              decoration: const InputDecoration(
                  labelText: 'Změna ceny (nepovinné)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              description.text.trim().isNotEmpty,
            ),
            child: const Text('Přidat návrh'),
          ),
        ],
      ),
    );
    if (add == true && mounted) {
      setState(() => widget.deal.amendments.add(
            Amendment(description.text.trim(), price.text.trim()),
          ));
    }
    description.dispose();
    price.dispose();
  }

  String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final deal = widget.deal;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail dohody')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: proposeAmendment,
        icon: const Icon(Icons.edit_note),
        label: const Text('Navrhnout dodatek'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(deal.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Druhá strana: ${deal.otherParty}'),
          const SizedBox(height: 16),
          _Section(
            title: 'Původní dohoda',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.description.isEmpty
                    ? 'Bez podrobného popisu.'
                    : deal.description),
                const SizedBox(height: 8),
                Text('Částka: ${deal.amount.isEmpty ? 'neuvedena' : deal.amount}'),
                Text('Vytvořeno: ${date(deal.createdAt)}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Potvrzení účastníků',
            child: Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deal.confirmedByMe,
                  title: const Text('Potvrzuji za sebe'),
                  onChanged: (v) =>
                      setState(() => deal.confirmedByMe = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deal.confirmedByOther,
                  title: const Text('Potvrzení druhé strany – ukázka'),
                  subtitle: const Text(
                      'V tomto prototypu může stav změnit jen toto zařízení.'),
                  onChanged: (v) =>
                      setState(() => deal.confirmedByOther = v ?? false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Historie dodatků',
            child: deal.amendments.isEmpty
                ? const Text('Zatím nebyl navržen žádný dodatek.')
                : Column(
                    children: deal.amendments.map((a) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: Text(a.description),
                        subtitle: Text(
                          '${date(a.proposedAt)} • ${a.status}'
                          '${a.priceChange.isEmpty ? '' : '\nZměna ceny: ${a.priceChange}'}',
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Dodatek je pouze lokální návrh. Původní dohoda se nepřepisuje. '
            'Schválení druhou stranou a neměnná cloudová historie budou doplněny později.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}
