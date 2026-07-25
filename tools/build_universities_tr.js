const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const raw = JSON.parse(
  fs.readFileSync(path.join(root, 'landing/data/raw_enhanced.json'), 'utf8'),
);
const list = Array.isArray(raw) ? raw : Object.values(raw);
const byCity = {};

function pushUni(city, name) {
  const c = String(city || '').trim().replace(/\s+/g, ' ');
  const n = String(name || '').trim();
  if (!c || !n) return;
  if (!byCity[c]) byCity[c] = [];
  const key = n.toLocaleUpperCase('tr-TR');
  if (byCity[c].some((x) => x.toLocaleUpperCase('tr-TR') === key)) return;
  byCity[c].push(n);
}

for (const u of list) {
  pushUni(u.city || u.province, u.name);
}

const cityMap = {
  ADANA: 'Adana',
  ADIYAMAN: 'Adıyaman',
  AFYON: 'Afyonkarahisar',
  AFYONKARAHISAR: 'Afyonkarahisar',
  AGRI: 'Ağrı',
  AKSARAY: 'Aksaray',
  AMASYA: 'Amasya',
  ANKARA: 'Ankara',
  ANTALYA: 'Antalya',
  ARDAHAN: 'Ardahan',
  ARTVIN: 'Artvin',
  AYDIN: 'Aydın',
  BALIKESIR: 'Balıkesir',
  BARTIN: 'Bartın',
  BATMAN: 'Batman',
  BAYBURT: 'Bayburt',
  BILECIK: 'Bilecik',
  BINGOL: 'Bingöl',
  BITLIS: 'Bitlis',
  BOLU: 'Bolu',
  BURDUR: 'Burdur',
  BURSA: 'Bursa',
  CANAKKALE: 'Çanakkale',
  CANKIRI: 'Çankırı',
  CORUM: 'Çorum',
  DENIZLI: 'Denizli',
  DIYARBAKIR: 'Diyarbakır',
  DUZCE: 'Düzce',
  EDIRNE: 'Edirne',
  ELAZIG: 'Elazığ',
  ERZINCAN: 'Erzincan',
  ERZURUM: 'Erzurum',
  ESKISEHIR: 'Eskişehir',
  GAZIANTEP: 'Gaziantep',
  GIRESUN: 'Giresun',
  GUMUSHANE: 'Gümüşhane',
  HAKKARI: 'Hakkâri',
  HATAY: 'Hatay',
  IGDIR: 'Iğdır',
  ISPARTA: 'Isparta',
  ISTANBUL: 'İstanbul',
  IZMIR: 'İzmir',
  KAHRAMANMARAS: 'Kahramanmaraş',
  KARABUK: 'Karabük',
  KARAMAN: 'Karaman',
  KARS: 'Kars',
  KASTAMONU: 'Kastamonu',
  KAYSERI: 'Kayseri',
  KIRIKKALE: 'Kırıkkale',
  KIRKLARELI: 'Kırklareli',
  KIRSEHIR: 'Kırşehir',
  KILIS: 'Kilis',
  KOCAELI: 'Kocaeli',
  KONYA: 'Konya',
  KUTAHYA: 'Kütahya',
  MALATYA: 'Malatya',
  MANISA: 'Manisa',
  MARDIN: 'Mardin',
  MERSIN: 'Mersin',
  ICEL: 'Mersin',
  MUGLA: 'Muğla',
  MUS: 'Muş',
  NEVSEHIR: 'Nevşehir',
  NIGDE: 'Niğde',
  ORDU: 'Ordu',
  OSMANIYE: 'Osmaniye',
  RIZE: 'R' + 'ize',
  SAKARYA: 'Sakarya',
  SAMSUN: 'Samsun',
  SIIRT: 'Siirt',
  SINOP: 'Sinop',
  SIVAS: 'Sivas',
  SANLIURFA: 'Şanlıurfa',
  SIRNAK: 'Şırnak',
  TEKIRDAG: 'Tekirdağ',
  TOKAT: 'Tokat',
  TRABZON: 'Trabzon',
  TUNCELI: 'Tunceli',
  USAK: 'Uşak',
  VAN: 'Van',
  YALOVA: 'Yalova',
  YOZGAT: 'Yozgat',
  ZONGULDAK: 'Zonguldak',
};

function asciiKey(s) {
  return String(s || '')
    .toLocaleUpperCase('tr-TR')
    .replace(/İ/g, 'I')
    .replace(/Ş/g, 'S')
    .replace(/Ğ/g, 'G')
    .replace(/Ü/g, 'U')
    .replace(/Ö/g, 'O')
    .replace(/Ç/g, 'C')
    .replace(/\s+/g, '')
    .replace(/\./g, '');
}

function cityName(province) {
  const key = asciiKey(province);
  if (cityMap[key]) return cityMap[key];
  return String(province)
    .split(' ')
    .map((w) => {
      const lower = w.toLocaleLowerCase('tr-TR');
      return lower.charAt(0).toLocaleUpperCase('tr-TR') + lower.slice(1);
    })
    .join(' ');
}

const prov = JSON.parse(
  fs.readFileSync(path.join(root, 'landing/data/raw_province.json'), 'utf8'),
);
for (const p of prov) {
  const city = cityName(p.province);
  for (const u of p.universities || []) {
    const name = String(u.name || '').trim();
    if (!name) continue;
    const pretty = name
      .split(' ')
      .map((w) => {
        const lower = w.toLocaleLowerCase('tr-TR');
        return lower.charAt(0).toLocaleUpperCase('tr-TR') + lower.slice(1);
      })
      .join(' ');
    pushUni(city, pretty);
  }
}

const cities = Object.keys(byCity).sort((a, b) => a.localeCompare(b, 'tr'));
for (const c of cities) {
  byCity[c].sort((a, b) => a.localeCompare(b, 'tr'));
}

const out = {
  updatedAt: '2026-07-23',
  source: 'YÖK Atlas 2024 (enhanced) + YÖK il/üniversite listesi',
  cityCount: cities.length,
  universityCount: cities.reduce((n, c) => n + byCity[c].length, 0),
  cities,
  byCity,
};

const landingOut = path.join(root, 'landing/data/universities-tr.json');
const assetsDir = path.join(root, 'assets/data');
fs.mkdirSync(assetsDir, { recursive: true });
fs.writeFileSync(landingOut, JSON.stringify(out));
fs.writeFileSync(path.join(assetsDir, 'universities-tr.json'), JSON.stringify(out));

console.log(
  'OK cities=%s unis=%s sampleGaziantep=%j size=%s',
  out.cityCount,
  out.universityCount,
  byCity['Gaziantep'] || byCity.Gaziantep,
  fs.statSync(landingOut).size,
);
