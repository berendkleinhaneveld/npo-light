// The example catalogue behind the wireframe. Every title is invented: the
// wireframe shows how the app behaves, not what NPO broadcasts.
(function () {
  'use strict';

  const MIN = 60;

  function series(id, title, description, options) {
    const unavailable = options.unavailable || [];
    return {
      id,
      kind: 'series',
      title,
      description,
      youth: Boolean(options.youth),
      available: true,
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
            duration: options.minutes * MIN,
            available: !unavailable.includes(`${season}.${number}`),
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

  const items = [
    series('polderpost', 'De Polderpost',
      'Een postbode in de Alblasserwaard kent de geheimen van het hele dorp. Dan verdwijnt er een aangetekende brief.',
      {
        minutes: 45,
        seasons: [
          ['De aangetekende brief', 'Stempels', 'Retour afzender', 'Poste restante'],
          ['Nieuwe wijk', 'Het pakket', 'Onbestelbaar', 'Laatste ronde'],
        ],
        unavailable: ['1.4'],
      }),
    series('wadden', 'Wadden in Vier Seizoenen',
      'Een jaar lang op het wad, van de eerste lepelaar tot de laatste zeehond.',
      { minutes: 50, seasons: [['Lente', 'Zomer', 'Herfst', 'Winter']] }),
    series('bakfiets', 'Het Grote Bakfietsdebat',
      'Zes avonden praten over de vraag die elke Nederlandse stoep verdeelt.',
      {
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
      { minutes: 40, seasons: [['Het Veluwse woud', 'De Biesbosch', 'Texel']] }),
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

    series('fleurtuin', 'Fleurs Wilde Tuin',
      'Fleur laat zien wat er allemaal leeft in een gewone achtertuin.',
      {
        youth: true,
        minutes: 12,
        seasons: [['De egel', 'Het vogelhuisje', 'Regenwormen', 'De vijver', 'Bijen', 'Winterslaap']],
      }),
    series('bram', 'Bram de Brandweerbeer',
      'Bram en zijn ploeg helpen iedereen in Berendorp, ook als het niet brandt.',
      {
        youth: true,
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
