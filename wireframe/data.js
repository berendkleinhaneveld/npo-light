// The example catalogue behind the wireframe. Every title is invented: the
// wireframe shows how the app behaves, not what NPO broadcasts.
(function () {
  'use strict';

  const MIN = 60;

  // An episode's description comes from `describe(title, season, number)`,
  // or is absent: NPO usually has one, but the page must cope without it.
  function series(id, title, description, options) {
    const unavailable = options.unavailable || [];
    const describe = options.describe || (() => '');
    return {
      id,
      kind: 'series',
      title,
      description,
      youth: Boolean(options.youth),
      available: !options.gone,
      seasons: options.seasons.map((titles, seasonIndex) => ({
        number: seasonIndex + 1,
        episodes: titles.map((episodeTitle, episodeIndex) => {
          const season = seasonIndex + 1;
          const number = episodeIndex + 1;
          return {
            id: `${id}-s${season}e${number}`,
            kind: 'episode',
            seriesId: id,
            season,
            number,
            title: episodeTitle,
            description: describe(episodeTitle, season, number),
            duration: options.minutes * MIN,
            available: !options.gone && !unavailable.includes(`${season}.${number}`),
          };
        }),
      })),
    };
  }

  function film(id, title, description, minutes, options) {
    return {
      id,
      kind: 'film',
      title,
      description,
      duration: minutes * MIN,
      youth: Boolean(options && options.youth),
      available: !(options && options.unavailable),
    };
  }

  function standalone(id, title, description, minutes, options) {
    return {
      id,
      kind: 'episode',
      seriesId: null,
      title,
      description,
      duration: minutes * MIN,
      youth: Boolean(options && options.youth),
      available: true,
    };
  }

  const POLDERPOST = {
    'De aangetekende brief': 'Henk bezorgt een aangetekende brief bij de burgemeester. Een dag later is de brief weg, en de burgemeester ontkent dat hij hem ooit kreeg.',
    Stempels: 'Op het postkantoor blijkt een stempel te missen. Henk ontdekt dat iemand al weken post doorzoekt voordat die de deur uit gaat.',
    'Retour afzender': 'Een pakket komt terug zonder afzender. Henk volgt het handschrift naar een boerderij aan de rand van het dorp.',
    'Poste restante': 'Iemand haalt al jaren post op onder een naam die niet bestaat. Henk wacht een middag achter de balie.',
    'Nieuwe wijk': 'Het dorp krijgt een nieuwbouwwijk, en Henk een route die hij niet kent. De eerste brief daar is aan hemzelf gericht.',
    'Het pakket': 'Een zwaar pakket voor de dominee. Niemand wil zeggen wat erin zit, maar iedereen wil weten wie het stuurde.',
    Onbestelbaar: 'Een stapel onbestelbare post brengt Henk bij een huis dat al twintig jaar leegstaat.',
    'Laatste ronde': 'Henks laatste werkdag. Hij heeft de verdwenen brief eindelijk gevonden, en moet beslissen of hij hem bezorgt.',
  };

  const WADDEN = {
    Lente: 'De lepelaars komen terug en de wadpieren worden wakker. Op Schiermonnikoog begint het broedseizoen vroeg.',
    Zomer: 'Hoogtij voor zeehonden en toeristen. Hoe delen ze het wad zonder elkaar in de weg te zitten?',
    Herfst: 'Miljoenen trekvogels tanken bij op het wad voordat ze naar Afrika vliegen.',
    Winter: 'Storm, ijs en stilte. Wie blijft er op het wad als iedereen weg is?',
  };

  // A consumer programme that has run for decades: 27 seasons, to try the
  // season picker on (FR-CONTENT-07).
  const PRODUCTS = [
    'Pindakaas', 'Kipnuggets', 'Jus d’orange', 'Vissticks', 'Hagelslag', 'Muesli',
    'Frikandellen', 'Tomatenketchup', 'Olijfolie', 'Koffiecreamer', 'Honing', 'Zalm',
    'Volkorenbrood', 'Energiedrank', 'Kaas', 'Thee', 'Chocoladepasta', 'Garnalen',
    'Sportdrank', 'Mayonaise', 'Vegaburger', 'Ontbijtkoek', 'Appelmoes', 'Rookworst',
    'Yoghurt', 'Pasta', 'Zout', 'Kokoswater', 'Cola', 'Babyvoeding', 'Stroopwafels',
    'Bouillon', 'Pizza', 'Oesters', 'Sushi', 'Paprikachips', 'Koffie', 'Avocado',
    'Kaneel', 'Vanille', 'Speculaas', 'Ijs', 'Haring', 'Rijst', 'Water', 'Bier',
  ];

  const WAT_ZIT_ERIN = Array.from({ length: 27 }, (unused, season) => (
    Array.from({ length: 8 }, (alsoUnused, episode) => PRODUCTS[(season * 8 + episode * 7) % PRODUCTS.length])
  ));

  function aboutProduct(product, season, number) {
    const angles = [
      'Wat zit er echt in? Het team volgt het van de fabriek tot het schap',
      'Waarom is de ene twee keer zo duur als de andere? Een blinde proef en een kijkje achter de schermen',
      'Wat betekent de tekst op de verpakking eigenlijk, en wie bedacht die?',
      'Hoe wordt het gemaakt, en hoeveel ervan komt van waar het etiket zegt?',
    ];
    return `${product}. ${angles[(season + number) % angles.length]}`;
  }

  const items = [
    series('polderpost', 'De Polderpost',
      'Een postbode in de Alblasserwaard kent de geheimen van het hele dorp. Dan verdwijnt er een aangetekende brief.',
      {
        minutes: 45,
        seasons: [
          ['De aangetekende brief', 'Stempels', 'Retour afzender', 'Poste restante'],
          ['Nieuwe wijk', 'Het pakket', 'Onbestelbaar', 'Laatste ronde'],
        ],
        describe: (title) => POLDERPOST[title] || '',
        unavailable: ['1.4'],
      }),
    series('wadden', 'Wadden in Vier Seizoenen',
      'Een jaar lang op het wad, van de eerste lepelaar tot de laatste zeehond.',
      { describe: (title) => WADDEN[title] || '', minutes: 50, seasons: [['Lente', 'Zomer', 'Herfst', 'Winter']] }),
    series('bakfiets', 'Het Grote Bakfietsdebat',
      'Zes avonden praten over de vraag die elke Nederlandse stoep verdeelt.',
      {
        describe: (title, season, number) => `Avond ${number}: ${title}. Voor- en tegenstanders aan één tafel, en een stoep vol publiek.`,
        minutes: 30,
        seasons: [[
          'Wie gaat er voor?', 'De stoep is van iedereen', 'Elektrisch of niet',
          'Regen', 'Drie kinderen, één bak', 'De finale',
        ]],
      }),
    series('kaas', 'Kaas & Klompen',
      'De quiz over alles wat typisch Nederlands is, en alles wat dat stiekem niet is.',
      {
        minutes: 25,
        seasons: [['Ronde 1: Gouda', 'Ronde 2: Edam', 'Ronde 3: Leerdam', 'Halve finale', 'Finale']],
      }),
    series('fleurwild', 'Fleur in het Wild',
      'Bioloog Fleur trekt drie weken door de laatste echte wildernis van Nederland.',
      { describe: (title) => `Fleur trekt een week door ${title.replace(/^Het |^De /, 'het ').replace('het Biesbosch', 'de Biesbosch')}, met alleen een rugzak en een camera.`, minutes: 40, seasons: [['Het Veluwse woud', 'De Biesbosch', 'Texel']] }),
    film('storm', 'Storm over Urk',
      'Een vissersfamilie wacht een nacht lang op nieuws van zee.', 112),
    film('veerpont', 'De Laatste Veerpont',
      'Een veerman vaart zijn laatste dienst voordat de brug opengaat.', 98),
    film('zeeland', 'Zomer in Zeeland',
      'Drie vriendinnen, één camping, en de zomer waarin alles verandert.', 104,
      { unavailable: true }),
    standalone('afsluitdijk', 'Het Geheim van de Afsluitdijk',
      'Wat er onder de dijk gebeurt, en waarom hij er over honderd jaar nog ligt.', 55),
    standalone('sterren', 'De Nacht van de Sterrenkijkers',
      'Een nacht op de donkerste plek van Nederland, met iedereen die omhoog wil kijken.', 52),
    series('dijkwachters', 'De Dijkwachters',
      'Als het water stijgt, staat een dorp in Zeeland er alleen voor. Wie houdt de dijk?',
      {
        describe: (title, season, number) => `Deel ${number}. ${title}: het water staat hoger dan ooit, en het dorp moet kiezen wie er blijft.`,
        minutes: 50,
        seasons: [['Springtij', 'De bres', 'Zandzakken', 'Nachtdienst', 'Laagwater']],
      }),
    series('grachten', 'Achter de Grachten',
      'Wie woont er eigenlijk in de grachtenpanden? Zes huizen, zes verhalen.',
      {
        describe: (title) => `Achter de gevels van ${title.replace(/^De |^Het /, 'de ')}: wie woont daar nu, en wie woonde er vroeger?`,
        minutes: 30,
        seasons: [['De Herengracht', 'De Keizersgracht', 'De Prinsengracht', 'Het Singel', 'De Bloemgracht', 'De Lauriergracht']],
      }),
    series('kantoor', 'Kantoor aan het IJ',
      'Een komedie over een reclamebureau dat elke week bijna failliet gaat.',
      {
        describe: (title) => `${title}. Het bureau staat weer eens op omvallen, en iedereen denkt dat hij het gaat redden.`,
        minutes: 25,
        seasons: [['De pitch', 'Teamuitje', 'De nieuwe stagiair', 'Vrijdagmiddagborrel', 'De klant', 'Kerstdiner']],
      }),
    series('treinreis', 'Met de Trein naar Tromsø',
      'Vier weken, vierentwintig treinen en geen enkel vliegtuig: van Utrecht naar het noorden.',
      { describe: (title, season, number) => `Etappe ${number}: ${title}. Overstappen, wachten, en onderweg de mensen die er wonen.`, minutes: 45, seasons: [['Utrecht–Hamburg', 'Hamburg–Stockholm', 'Stockholm–Narvik', 'Narvik–Tromsø']] }),
    series('kustwacht', 'De Kustwacht',
      'Een jaar mee met de reddingsboten van Terschelling.',
      { minutes: 40, seasons: [['Storm op komst', 'Vermist', 'De oefening']], gone: true }),
    series('watziterin', 'Wat Zit Erin?',
      'Elke week één product uit de supermarkt, en de vraag wat er werkelijk in zit. Al 27 seizoenen.',
      { minutes: 25, seasons: WAT_ZIT_ERIN, describe: aboutProduct }),
    film('peelland', 'Mist over de Peel',
      'Een boswachter vindt een verlaten auto in het veen, en niemand in het dorp mist iemand.', 101),
    film('tulpen', 'Het Tulpenbedrijf',
      'Drie zussen erven een bollenkwekerij die al jaren verlies maakt.', 94),
    standalone('elfsteden', 'De Elfstedentocht die Nooit Kwam',
      'Dertig jaar wachten op ijs, verteld door de mensen die elke winter klaarstaan.', 58),

    series('fleurtuin', 'Fleurs Wilde Tuin',
      'Fleur laat zien wat er allemaal leeft in een gewone achtertuin.',
      {
        youth: true,
        describe: (title) => `Wat leeft er in de tuin? Vandaag: ${title.toLowerCase()}.`,
        minutes: 12,
        seasons: [['De egel', 'Het vogelhuisje', 'Regenwormen', 'De vijver', 'Bijen', 'Winterslaap']],
      }),
    series('bram', 'Bram de Brandweerbeer',
      'Bram en zijn ploeg helpen iedereen in Berendorp, ook als het niet brandt.',
      {
        youth: true,
        describe: (title) => `${title} Bram en de ploeg rukken uit.`.replace(/([^.!?]) Bram/, '$1. Bram'),
        minutes: 10,
        seasons: [
          ['De kat in de boom', 'Blussen maar!', 'De ladder'],
          ['Nieuwe helm', 'Brand in de bakkerij', 'Feest op de kazerne'],
        ],
      }),
    series('pim', 'Proefjes met Pim',
      'Pim doet proefjes die je thuis ook kunt doen, als er een grote mee kijkt.',
      {
        youth: true,
        describe: (title) => `Pim doet een proefje: ${title.toLowerCase()}. Doe je mee?`,
        minutes: 15,
        seasons: [['Vulkaan in de keuken', 'Drijven of zinken', 'Onzichtbare inkt', 'Raketje van een fles']],
      }),
    film('fietsje', 'Het Vliegende Fietsje',
      'Noor vindt op zolder een fiets die kan vliegen, maar alleen als niemand kijkt.', 75,
      { youth: true }),
    standalone('dierenfeest', 'Het Grote Dierenfeest',
      'Alle dieren van de kinderboerderij geven samen een feest.', 40, { youth: true }),
  ];

  const byId = new Map();
  items.forEach((item) => {
    byId.set(item.id, item);
    if (item.kind === 'series') {
      item.seasons.forEach((season) => season.episodes.forEach((episode) => {
        episode.youth = item.youth;
        byId.set(episode.id, episode);
      }));
    }
  });

  window.CATALOGUE = {
    items,
    get(id) {
      return byId.get(id) || null;
    },
    episodes(seriesItem) {
      return seriesItem.seasons.flatMap((season) => season.episodes);
    },
  };
})();
