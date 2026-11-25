import 'package:flutter/material.dart';

class WorkContractDraft {
  const WorkContractDraft({
    required this.title,
    required this.inviteeEmail,
    required this.description,
    required this.contractText,
    required this.contractData,
    required this.items,
    required this.currency,
  });

  final String title;
  final String inviteeEmail;
  final String description;
  final String contractText;
  final Map<String, dynamic> contractData;
  final List<Map<String, dynamic>> items;
  final String currency;

  Map<String, dynamic> toRpcParams() => {
        'p_title': title,
        'p_description': description,
        'p_currency': currency,
        'p_contract_data': contractData,
        'p_contract_text': contractText,
        'p_items': items,
        'p_invitee_email': inviteeEmail,
      };
}

class WorkContractWizard extends StatefulWidget {
  const WorkContractWizard({super.key, required this.initialEmail});
  final String initialEmail;

  @override
  State<WorkContractWizard> createState() => _WorkContractWizardState();
}

class _LineItemInput {
  _LineItemInput()
      : description = TextEditingController(),
        quantity = TextEditingController(text: '1'),
        unit = TextEditingController(text: 'ks'),
        unitPrice = TextEditingController(text: '0');

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController unitPrice;

  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    unitPrice.dispose();
  }
}

class _WorkContractWizardState extends State<WorkContractWizard> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};
  final Map<String, String> _partyKinds = {
    'me': 'osvc',
    'other': 'osvc',
  };
  final List<_LineItemInput> _items = [_LineItemInput()];

  String _creatorRole = 'zhotovitel';
  String _materialProvider = 'zhotovitel';
  String _priceMode = 'fixed';
  String _vatMode = 'not_selected';
  String _warrantyMode = 'none';
  bool _consumerOrderer = false;
  bool _saving = false;

  TextEditingController _controller(String key, [String initial = '']) {
    return _c.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  @override
  void initState() {
    super.initState();
    _controller('me_email', widget.initialEmail);
    for (final key in [
      'other_email', 'me_name', 'other_name', 'me_address', 'other_address',
      'me_ico', 'other_ico', 'me_dic', 'other_dic', 'me_phone', 'other_phone',
      'me_representative', 'other_representative', 'work_location', 'work_scope',
      'work_quality', 'work_exclusions', 'materials_description', 'start_date',
      'completion_date', 'payment_schedule', 'payment_method', 'payment_due',
      'handover_place', 'handover_rules', 'defect_contact', 'extra_work',
      'warranty_description', 'termination_terms', 'other_terms', 'contract_date'
    ]) {
      _controller(key);
    }
    _controller('payment_schedule',
        'Záloha se nepožaduje. Cena bude uhrazena po řádném předání díla na základě faktury.');
    _controller('payment_method',
        'Bankovním převodem na účet zhotovitele uvedený na faktuře, případně hotově proti potvrzení.');
    _controller('payment_due', '14 kalendářních dnů ode dne doručení faktury');
    _controller('handover_place', 'V místě provádění díla');
    _controller('handover_rules',
        'Předání bude zaznamenáno v předávacím protokolu s datem, popisem předaného díla a případnými výhradami, vadami a nedodělky. Strany mohou pořídit fotodokumentaci.');
    _controller('defect_contact',
        'Vady a nedodělky budou oznámeny druhé straně bez zbytečného odkladu po jejich zjištění, nejlépe písemně s popisem a fotodokumentací.');
    _controller('termination_terms',
        'Každá strana může od smlouvy odstoupit v případech stanovených zákonem nebo touto smlouvou. Odstoupení musí být druhé straně oznámeno prokazatelně. Strany vypořádají již provedené práce, účelně vynaložené náklady, předaný materiál a poskytnutá plnění podle občanského zákoníku.');
    _controller('extra_work',
        'Změna rozsahu, vícepráce, méněpráce, záměna materiálu nebo změna termínu se před provedením zachytí v samostatném dodatku či změnovém listu. Ten uvede popis změny, dopad na cenu a termín a musí být potvrzen oběma stranami. Původní znění dohody se nepřepisuje.');
    _controller('contract_date', _today());
  }

  String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  void dispose() {
    for (final value in _c.values) {
      value.dispose();
    }
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Toto pole je povinné.' : null;

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'E-mail je povinný.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
      return 'Zadej platnou e-mailovou adresu.';
    }
    return null;
  }

  String? _icoValidator(String? value) {
    final ico = (value ?? '').trim();
    if (!RegExp(r'^\d{8}$').hasMatch(ico)) {
      return 'IČO musí obsahovat přesně 8 číslic.';
    }
    final digits = ico.split('').map(int.parse).toList();
    final sum = digits[0] * 8 +
        digits[1] * 7 +
        digits[2] * 6 +
        digits[3] * 5 +
        digits[4] * 4 +
        digits[5] * 3 +
        digits[6] * 2;
    final remainder = sum % 11;
    final checkDigit = remainder == 0 ? 1 : remainder == 1 ? 0 : 11 - remainder;
    if (digits[7] != checkDigit) {
      return 'IČO nemá správnou kontrolní číslici.';
    }
    return null;
  }

  String? _dateValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Datum je povinné.';
    final match = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(value.trim());
    if (match == null) return 'Použij formát DD.MM.RRRR.';
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return 'Zadej skutečné kalendářní datum.';
    }
    return null;
  }

  String? _numberValidator(String? value, {required bool positive}) {
    if (value == null || value.trim().isEmpty) return 'Vyplň číselnou hodnotu.';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null || !n.isFinite || (positive ? n <= 0 : n < 0)) {
      return positive ? 'Zadej číslo větší než nula.' : 'Zadej nulu nebo kladné číslo.';
    }
    return null;
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _controller(key),
        keyboardType: keyboard ?? (lines > 1 ? TextInputType.multiline : TextInputType.text),
        minLines: lines,
        maxLines: lines > 1 ? lines : 1,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          alignLabelWithHint: lines > 1,
        ),
        validator: validator ?? (required ? _required : null),
      ),
    );
  }

  Widget _partySection(String prefix, String title, {required bool invitee}) {
    final kind = _partyKinds[prefix]!;
    final icoRequired = kind != 'person';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: kind,
              decoration: const InputDecoration(labelText: 'Typ osoby / subjektu', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'person', child: Text('Fyzická osoba')),
                DropdownMenuItem(value: 'osvc', child: Text('Podnikající fyzická osoba (OSVČ)')),
                DropdownMenuItem(value: 'company', child: Text('Právnická osoba / společnost')),
              ],
              onChanged: (v) => setState(() => _partyKinds[prefix] = v ?? kind),
            ),
            const SizedBox(height: 10),
            _field('${prefix}_name', kind == 'company' ? 'Obchodní firma / název' : 'Jméno a příjmení', required: true),
            _field('${prefix}_address', kind == 'company' ? 'Sídlo zapsané ve veřejném rejstříku' : 'Adresa bydliště / místa podnikání', required: true, lines: 2),
            if (icoRequired)
              _field('${prefix}_ico', 'IČO (8 číslic)', required: true, keyboard: TextInputType.number, validator: _icoValidator),
            _field('${prefix}_dic', 'DIČ (pokud je přiděleno)'),
            _field('${prefix}_email', 'Kontaktní e-mail', required: true, keyboard: TextInputType.emailAddress, validator: _emailValidator),
            _field('${prefix}_phone', 'Telefon (doporučeno)', keyboard: TextInputType.phone),
            if (kind == 'company')
              _field('${prefix}_representative', 'Jméno a funkce osoby oprávněné jednat', required: true),
            if (invitee)
              const Text('Na tento e-mail bude odeslána pozvánka do DEALPROOF.', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  List<Map<String, dynamic>> _buildItems() => _items.map((item) {
        return {
          'description': item.description.text.trim(),
          'quantity': double.parse(item.quantity.text.trim().replaceAll(',', '.')),
          'unit': item.unit.text.trim(),
          'unit_price': double.parse(item.unitPrice.text.trim().replaceAll(',', '.')),
        };
      }).toList();

  Map<String, dynamic> _partyData(String prefix, String role) => {
        'role': role,
        'type': _partyKinds[prefix],
        'name': _c['${prefix}_name']!.text.trim(),
        'address': _c['${prefix}_address']!.text.trim(),
        'ico': _c['${prefix}_ico']?.text.trim(),
        'dic': _c['${prefix}_dic']!.text.trim(),
        'email': _c['${prefix}_email']!.text.trim().toLowerCase(),
        'phone': _c['${prefix}_phone']!.text.trim(),
        'representative': _c['${prefix}_representative']?.text.trim(),
      };

  String _buildText(
    Map<String, dynamic> orderer,
    Map<String, dynamic> contractor,
    List<Map<String, dynamic>> items,
    double total,
  ) {
    final date = _c['contract_date']!.text.trim();
    final priceLabel = switch (_priceMode) {
      'estimate' => 'odhad ceny',
      'calculation' => 'cena určená podle jednotkových cen a skutečného množství',
      _ => 'pevná smluvní cena',
    };
    final vat = switch (_vatMode) {
      'included' => 'Ceny položek jsou uvedeny včetně DPH.',
      'extra' => 'DPH bude k uvedeným cenám připočtena v zákonné sazbě, je-li zhotovitel povinen ji uplatnit.',
      'not_payer' => 'Zhotovitel prohlašuje, že není plátcem DPH; DPH se k ceně nepřipočítává.',
      _ => 'Režim DPH nebyl vybrán.',
    };

    final priceRule = switch (_priceMode) {
      'fixed' =>
        'Cena je sjednána pevnou částkou podle položkového rozpočtu uvedeného v této smlouvě. Podle § 2620 odst. 1 občanského zákoníku nelze požadovat změnu ceny jen proto, že provedení díla vyžádalo jiné úsilí nebo náklady, než se předpokládalo. Tím nejsou dotčeny zákonné výjimky, zejména § 2620 odst. 2 občanského zákoníku.',
      'estimate' =>
        'Cena je stanovena odhadem. Zjistí-li zhotovitel, že bude nutné odhad podstatně překročit, oznámí to objednateli bez zbytečného odkladu, odůvodní zvýšení a uvede nově určenou cenu. Práva objednatele včetně možnosti odstoupení se řídí § 2612 občanského zákoníku.',
      'calculation' =>
        'Konečná cena bude určena podle skutečně provedeného a doloženého množství a sjednaných jednotkových cen. Změny rozsahu a položek se předem potvrzují postupem pro vícepráce a dodatky.',
      _ => 'Způsob určení ceny musí být před potvrzením smlouvy zvolen.',
    };

    final warrantyClause = _warrantyMode == 'agreed'
        ? 'Zhotovitel poskytuje výslovnou záruku za jakost v tomto rozsahu a po tuto dobu: ${_c['warranty_description']!.text.trim()}. Záruční doba počíná běžet předáním díla.'
        : 'Strany výslovně nesjednávají smluvní záruku za jakost nad rámec zákonných práv z vadného plnění.';
    String party(Map<String, dynamic> p) {
      final company = p['type'] == 'company';
      final ico = p['ico']?.toString().trim() ?? '';
      final dic = p['dic']?.toString().trim() ?? '';
      final representative = p['representative']?.toString().trim() ?? '';
      return '${p['role'].toString().toUpperCase()}: ${p['name']}\n'
          '${company ? 'Sídlo' : 'Adresa'}: ${p['address']}\n'
          '${ico.isEmpty ? '' : 'IČO: ${ico}\n'}'
          '${dic.isEmpty ? '' : 'DIČ: ${dic}\n'}'
          '${representative.isEmpty ? '' : 'Jednající osoba: ${representative}\n'}'
          'E-mail: ${p['email']}\n'
          '${(p['phone'] as String).isEmpty ? '' : 'Telefon: ${p['phone']}\n'}';
    }

    final itemLines = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final amount = (item['quantity'] as num) * (item['unit_price'] as num);
      itemLines.add('${i + 1}. ${item['description']} — ${item['quantity']} ${item['unit']} × '
          '${item['unit_price']} Kč = ${amount.toStringAsFixed(2)} Kč');
    }

    return '''
SMLOUVA O DÍLO
uzavřená podle § 2586 a násl. zákona č. 89/2012 Sb., občanský zákoník

Datum vyhotovení: ${date}

I. SMLUVNÍ STRANY
${party(orderer)}
${party(contractor)}

II. PŘEDMĚT A ROZSAH DÍLA
Zhotovitel se zavazuje provést pro objednatele dílo vlastním jménem, na svůj náklad a nebezpečí a s odbornou péčí. Objednatel se zavazuje poskytnout sjednanou součinnost, dokončené dílo převzít a zaplatit sjednanou cenu.

Místo provedení: ${_c['work_location']!.text.trim()}
Přesný rozsah a výsledek díla:
${_c['work_scope']!.text.trim()}

Požadovaná kvalita, technické parametry a způsob provedení:
${_c['work_quality']!.text.trim()}

Práce a plnění, které nejsou zahrnuty:
${_c['work_exclusions']!.text.trim().isEmpty ? 'Nejsou výslovně sjednány.' : _c['work_exclusions']!.text.trim()}

III. MATERIÁL A SOUČINNOST
Popis materiálu a ujednání o jeho zajištění:
${_c['materials_description']!.text.trim()}
Materiál zajišťuje: ${_materialProvider == 'zhotovitel' ? 'zhotovitel' : 'objednatel'}.

Objednatel umožní přístup na místo plnění v dohodnutých termínech a poskytne informace a součinnost potřebnou k provedení díla. Strany si bez zbytečného odkladu oznámí okolnosti, které mohou ovlivnit rozsah, cenu nebo termín. Zhotovitel upozorní na nevhodný materiál nebo pokyn v rozsahu stanoveném právními předpisy; případný pokyn objednatele trvat na takovém postupu bude zachycen písemně.

Zjistí-li zhotovitel při provádění stavby nebo její změny skrytou překážku místa plnění, která znemožňuje provést dílo dohodnutým způsobem, oznámí ji bez zbytečného odkladu objednateli, navrhne změnu díla a do dosažení dohody může dotčené práce přerušit. Nedohodnou-li se strany v přiměřené lhůtě, mohou postupovat podle § 2627 občanského zákoníku včetně odstoupení a vypořádání již provedených prací.

Objednatel má právo kontrolovat provádění díla v rozsahu odpovídajícím povaze díla. Zjistí-li porušení povinností zhotovitele, může požadovat nápravu; další práva včetně odstoupení se řídí § 2593 občanského zákoníku. Kontrola nesmí bezdůvodně narušovat postup prací.

IV. TERMÍNY
Předpokládané zahájení: ${_c['start_date']!.text.trim().isEmpty ? 'bude upřesněno písemnou dohodou' : _c['start_date']!.text.trim()}
Sjednané dokončení: ${_c['completion_date']!.text.trim().isEmpty ? 'bude upřesněno písemnou dohodou' : _c['completion_date']!.text.trim()}

Termín se přiměřeně posune o dobu, po kterou provedení brání neposkytnutí sjednané součinnosti, změna díla potvrzená stranami nebo jiná překážka, za kterou podle zákona či této smlouvy neodpovídá zhotovitel. Důvod a předpokládaný dopad oznámí dotčená strana druhé straně bez zbytečného odkladu.

V. CENA A PLATEBNÍ PODMÍNKY
Způsob určení ceny: ${priceLabel}.
Součet uvedených položek / výchozí kalkulace: ${total.toStringAsFixed(2)} Kč.
${vat}

Položkový rozpis:
${itemLines.join('\n')}

Zálohy a průběžné platby:
${_c['payment_schedule']!.text.trim()}

Způsob úhrady:
${_c['payment_method']!.text.trim()}

Splatnost:
${_c['payment_due']!.text.trim()}.

${priceRule}

VI. ZMĚNY ROZSAHU A VÍCEPRÁCE
${_c['extra_work']!.text.trim()}

VII. DOKONČENÍ, PŘEDÁNÍ A PŘEVZETÍ
Dílo bude předáno: ${_c['handover_place']!.text.trim()}.
${_c['handover_rules']!.text.trim()}

Dílo je provedeno jeho dokončením a předáním. Objednatel při převzetí uvede, zda přebírá dílo bez výhrad, nebo s výhradami; konkrétní vady a nedodělky se popíší v předávacím protokolu. Je-li to vzhledem k povaze díla vhodné, mohou strany dohodnout předání po oddělitelných částech.

Je-li předmětem díla stavba nebo její část, použije se § 2628 občanského zákoníku: objednatel nemůže odmítnout převzetí pouze pro ojedinělé drobné vady, které nebrání funkčnímu ani estetickému užívání stavby a její užívání podstatně neomezují. Tím nejsou dotčena práva z vadného plnění ani možnost odmítnout převzetí při vadách, které těmto podmínkám neodpovídají.

VIII. VADY DÍLA A ZÁKONNÁ PRÁVA
${_c['defect_contact']!.text.trim()}

Práva z vadného plnění se řídí občanským zákoníkem, zejména § 2615 až § 2619. Objednatel oznámí zjištěné vady bez zbytečného odkladu. Tato smlouva nevylučuje ani nezkracuje práva, která nelze podle zákona vyloučit nebo omezit.

${warrantyClause}

IX. UKONČENÍ SMLOUVY A VYPOŘÁDÁNÍ
${_c['termination_terms']!.text.trim()}

X. SPOTŘEBITELSKÁ UJEDNÁNÍ
${_consumerOrderer ? 'Objednatel vystupuje jako spotřebitel. Uplatní se kogentní ochrana spotřebitele, informační povinnosti a pravidla reklamací. Pokud je smlouva uzavírána na dálku nebo mimo obchodní prostory, musí být před jejím potvrzením poskytnuty také informace a poučení vyžadované právními předpisy; tento vzor sám o sobě nenahrazuje individuální posouzení těchto povinností.' : 'Strany uvádějí, že objednatel podle zadaných údajů nevystupuje jako spotřebitel. Ukáže-li se toto zařazení jako nesprávné, použijí se příslušná kogentní ustanovení na ochranu spotřebitele.'}

XI. ZÁVĚREČNÁ UJEDNÁNÍ
Tato smlouva zachycuje ujednání stran v okamžiku jejího potvrzení. Je uzavřena okamžikem, kdy obě strany v aplikaci DEALPROOF výslovně potvrdí totožné znění smlouvy. Aplikace uchová verzi dokumentu, čas potvrzení a kontrolní otisk obsahu. Potvrzení v aplikaci není samo o sobě kvalifikovaným elektronickým podpisem.

Jakékoli pozdější změny se zachytí samostatným dodatkem nebo změnovým listem potvrzeným oběma stranami. Původní smlouva zůstává zachována a dodatek ji mění pouze v rozsahu výslovně uvedeném v dodatku.

Další ujednání:
${_c['other_terms']!.text.trim().isEmpty ? 'Žádná.' : _c['other_terms']!.text.trim()}

Smluvní strany potvrzují, že si text přečetly, jeho obsahu rozumějí a měly možnost zkontrolovat všechny údaje před potvrzením.
'''.trim();
  }

  Future<void> _finish() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zkontroluj povinná pole a oprav označené chyby.')),
      );
      return;
    }

    final ordererPrefix = _creatorRole == 'objednatel' ? 'me' : 'other';
    final contractorPrefix = _creatorRole == 'zhotovitel' ? 'me' : 'other';
    final orderer = _partyData(ordererPrefix, 'objednatel');
    final contractor = _partyData(contractorPrefix, 'zhotovitel');
    final inviteEmail = _c['other_email']!.text.trim().toLowerCase();

    final consumerLikeCombination = orderer['type'] == 'person' &&
        (contractor['type'] == 'osvc' || contractor['type'] == 'company');

    if (_consumerOrderer || consumerLikeCombination) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tato kombinace může spadat do spotřebitelského režimu. '
            'Aplikace zatím nepovoluje smlouvu mezi podnikatelem a soukromou fyzickou osobou, '
            'dokud nebude doplněno zákonné poučení a odstoupení.',
          ),
        ),
      );
      return;
    }

    if (inviteEmail == _c['me_email']!.text.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail druhé strany musí být odlišný od vašeho e-mailu.')),
      );
      return;
    }

    DateTime toDate(String value) {
      final parts = value.split('.');
      return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    }
    if (toDate(_c['start_date']!.text.trim()).isAfter(toDate(_c['completion_date']!.text.trim()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Termín zahájení nesmí být později než termín dokončení.')),
      );
      return;
    }

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.description.text.trim().isEmpty ||
          _numberValidator(item.quantity.text, positive: true) != null ||
          _numberValidator(item.unitPrice.text, positive: false) != null ||
          item.unit.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zkontroluj popis, množství, jednotku a cenu položky ${i + 1}.')),
        );
        return;
      }
    }

    if (_saving) return;
    setState(() => _saving = true);
    try {
      final items = _buildItems();
      final total = items.fold<double>(
        0,
        (sum, item) => sum + (item['quantity'] as double) * (item['unit_price'] as double),
      );
      final contractText = _buildText(orderer, contractor, items, total);
      final data = <String, dynamic>{
        'template_key': 'cz_work_contract',
        'template_version': 1,
        'contract_date': _c['contract_date']!.text.trim(),
        'creator_role': _creatorRole,
        'orderer': orderer,
        'contractor': contractor,
        'work': {
          'location': _c['work_location']!.text.trim(),
          'scope': _c['work_scope']!.text.trim(),
          'quality': _c['work_quality']!.text.trim(),
          'exclusions': _c['work_exclusions']!.text.trim(),
          'materials': _c['materials_description']!.text.trim(),
          'material_provider': _materialProvider,
        },
        'schedule': {
          'start_date': _c['start_date']!.text.trim(),
          'completion_date': _c['completion_date']!.text.trim(),
        },
        'price': {
          'mode': _priceMode,
          'currency': 'CZK',
          'vat_mode': _vatMode,
          'items_total': total,
          'payment_schedule': _c['payment_schedule']!.text.trim(),
          'payment_method': _c['payment_method']!.text.trim(),
          'payment_due': _c['payment_due']!.text.trim(),
        },
        'handover': {
          'place': _c['handover_place']!.text.trim(),
          'rules': _c['handover_rules']!.text.trim(),
        },
        'defects': {'contact': _c['defect_contact']!.text.trim()},
        'change_control': {'rule': _c['extra_work']!.text.trim()},
        'warranty': {'mode': _warrantyMode, 'description': _c['warranty_description']!.text.trim()},
        'termination': {'terms': _c['termination_terms']!.text.trim()},
        'consumer_orderer': _consumerOrderer,
        'other_terms': _c['other_terms']!.text.trim(),
      };
      final draft = WorkContractDraft(
        title: 'Smlouva o dílo',
        inviteeEmail: inviteEmail,
        description: contractText,
        contractText: contractText,
        contractData: data,
        items: items,
        currency: 'CZK',
      );
      if (_vatMode == 'not_selected') {
        throw StateError('Vyber, jak bude ve smlouvě řešena DPH.');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kontrola smlouvy o dílo'),
          content: SizedBox(
            width: 560,
            height: MediaQuery.of(dialogContext).size.height * 0.62,
            child: SingleChildScrollView(child: SelectableText(contractText)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Zpět upravit')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Potvrdit znění a pokračovat')),
          ],
        ),
      );
      if (confirmed == true && mounted) Navigator.of(context).pop(draft);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meIsContractor = _creatorRole == 'zhotovitel';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smlouva o dílo'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _finish,
            child: const Text('Zkontrolovat'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            const Text(
              'Vyplň konkrétní podmínky. Dohoda se druhé straně odešle až po kontrole celého znění.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            _section('1. Role a smluvní strany', [
              DropdownButtonFormField<String>(
                value: _creatorRole,
                decoration: const InputDecoration(labelText: 'V této smlouvě vystupuji jako', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'zhotovitel', child: Text('Zhotovitel – provádím dílo')),
                  DropdownMenuItem(value: 'objednatel', child: Text('Objednatel – objednávám dílo')),
                ],
                onChanged: (v) => setState(() => _creatorRole = v ?? _creatorRole),
              ),
              const SizedBox(height: 12),
              _partySection('me', meIsContractor ? 'Moje údaje – zhotovitel' : 'Moje údaje – objednatel', invitee: false),
              _partySection('other', meIsContractor ? 'Druhá strana – objednatel' : 'Druhá strana – zhotovitel', invitee: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _consumerOrderer,
                onChanged: (v) => setState(() => _consumerOrderer = v),
                title: const Text('Objednatel jedná jako spotřebitel'),
                subtitle: const Text('Spotřebitelská verze se připravuje. Dokud nejsou doplněny povinné informace a poučení, aplikace takovou smlouvu neodešle.'),
              ),
            ]),
            _section('2. Rozsah díla a místo', [
              _field('work_location', 'Přesná adresa / místo provádění díla', required: true, lines: 2),
              _field('work_scope', 'Podrobný popis díla a jednotlivých činností', required: true, lines: 5,
                  hint: 'Co přesně má být provedeno, v jakém rozsahu a jaký výsledek má vzniknout?'),
              _field('work_quality', 'Požadovaná kvalita, materiály, rozměry a technické parametry', required: true, lines: 4),
              _field('work_exclusions', 'Co není součástí ceny / díla', lines: 3),
            ]),
            _section('3. Materiál a součinnost', [
              _field('materials_description', 'Jaký materiál se použije a kdo jej zajistí', required: true, lines: 3),
              DropdownButtonFormField<String>(
                value: _materialProvider,
                decoration: const InputDecoration(labelText: 'Materiál zajišťuje', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'zhotovitel', child: Text('Zhotovitel')),
                  DropdownMenuItem(value: 'objednatel', child: Text('Objednatel')),
                ],
                onChanged: (v) => setState(() => _materialProvider = v ?? _materialProvider),
              ),
            ]),
            _section('4. Termíny', [
              _field('start_date', 'Datum zahájení (DD.MM.RRRR)', validator: _dateValidator, hint: 'Např. 01.12.2026'),
              _field('completion_date', 'Datum dokončení (DD.MM.RRRR)', validator: _dateValidator, hint: 'Např. 15.12.2026'),
              const Text('Termíny nevyplňuj odhadem, pokud mají být závazné.'),
            ]),
            _section('5. Cena a položkový rozpočet', [
              DropdownButtonFormField<String>(
                value: _priceMode,
                decoration: const InputDecoration(labelText: 'Způsob určení ceny', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'fixed', child: Text('Pevná smluvní cena')),
                  DropdownMenuItem(value: 'estimate', child: Text('Cena určená odhadem')),
                  DropdownMenuItem(value: 'calculation', child: Text('Jednotkové ceny podle skutečného množství')),
                ],
                onChanged: (v) => setState(() => _priceMode = v ?? _priceMode),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _vatMode == 'not_selected' ? null : _vatMode,
                hint: const Text('Vyber režim DPH'),
                validator: (v) => v == null ? 'Vyber režim DPH.' : null,
                decoration: const InputDecoration(labelText: 'DPH', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'not_payer', child: Text('Zhotovitel není plátcem DPH')),
                  DropdownMenuItem(value: 'included', child: Text('Ceny jsou včetně DPH')),
                  DropdownMenuItem(value: 'extra', child: Text('DPH se připočítá podle zákona')),
                ],
                onChanged: (v) => setState(() => _vatMode = v ?? _vatMode),
              ),
              const SizedBox(height: 12),
              ..._items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: Text('Položka ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        if (_items.length > 1)
                          IconButton(
                            tooltip: 'Odebrat položku',
                            onPressed: () => setState(() {
                              _items.removeAt(index).dispose();
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ]),
                      TextFormField(controller: item.description, decoration: const InputDecoration(labelText: 'Popis práce / materiálu', border: OutlineInputBorder()), validator: _required, minLines: 1, maxLines: 3),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextFormField(controller: item.quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Množství', border: OutlineInputBorder()), validator: (v) => _numberValidator(v, positive: true))),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: item.unit, decoration: const InputDecoration(labelText: 'Jednotka', border: OutlineInputBorder()), validator: _required)),
                      ]),
                      const SizedBox(height: 8),
                      TextFormField(controller: item.unitPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cena za jednotku v Kč', border: OutlineInputBorder()), validator: (v) => _numberValidator(v, positive: false)),
                    ]),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _items.add(_LineItemInput())),
                  icon: const Icon(Icons.add),
                  label: const Text('Přidat položku'),
                ),
              ),
              _field('payment_schedule', 'Zálohy a splátky – částky a termíny', required: true, lines: 3),
              _field('payment_method', 'Způsob platby', required: true, lines: 2),
              _field('payment_due', 'Splatnost faktury / doplatku', required: true),
            ]),
            _section('6. Předání a vady', [
              _field('handover_place', 'Kde a jak bude dílo předáno', required: true),
              _field('handover_rules', 'Předávací protokol, zkoušky a zápis výhrad', required: true, lines: 4),
              _field('defect_contact', 'Jak oznámit vady a komu', required: true, lines: 3),
            ]),
            _section('7. Záruka a ukončení smlouvy', [
              DropdownButtonFormField<String>(
                value: _warrantyMode,
                decoration: const InputDecoration(labelText: 'Smluvní záruka za jakost', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Záruka se výslovně nesjednává')),
                  DropdownMenuItem(value: 'agreed', child: Text('Sjednat záruku za jakost')),
                ],
                onChanged: (v) => setState(() => _warrantyMode = v ?? _warrantyMode),
              ),
              if (_warrantyMode == 'agreed')
                _field('warranty_description', 'Délka záruky, její rozsah a případné výjimky', required: true, lines: 3,
                    hint: 'Např. 24 měsíců od předání na hydroizolaci podle přiloženého technického listu.'),
              _field('termination_terms', 'Odstoupení a vypořádání po ukončení smlouvy', required: true, lines: 4),
              const Text('Tato ustanovení nesmějí omezit práva, která nelze podle zákona smluvně vyloučit.'),
            ]),
            _section('8. Změny a vícepráce', [
              _field('extra_work', 'Postup při změně rozsahu, ceny nebo termínu', required: true, lines: 5),
              const Text('Pravidlo je nastaveno tak, aby se vícepráce neprováděly pouze na základě nejasné ústní domluvy.'),
            ]),
            _section('9. Závěrečná ustanovení', [
              _field('contract_date', 'Datum vyhotovení (DD.MM.RRRR)', required: true, validator: _dateValidator),
              _field('other_terms', 'Další konkrétní ujednání (nepovinné)', lines: 3),
            ]),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Důležité: Tento vzor je právně strukturovaný návrh podle českého občanského zákoníku, nikoli právní posudek ani advokátem revidovaný formulář. U spotřebitelských smluv, stavebních prací, smluv uzavíraných na dálku a složitých zakázek je před použitím nutné doplnit případné zvláštní informace a nechat znění zkontrolovat českým advokátem.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saving ? null : _finish,
              icon: const Icon(Icons.preview),
              label: Text(_saving ? 'Kontroluji…' : 'Zkontrolovat a připravit smlouvu'),
            ),
          ],
        ),
      ),
    );
  }
}
