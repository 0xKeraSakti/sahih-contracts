# Sahih — Foundry Linter & Formatter Best Practice

Scope dokumen ini KHUSUS linting dan formatting kode Solidity di project Foundry (`sahih-contracts/`). Tidak mencakup TypeScript/backend — itu akan punya konvensi linting terpisah kalau/ketika dibahas.

Baca bersamaan dengan `sahih-development-plan.md` — dokumen ini melengkapi bagian Testability by Design di sana dengan lapisan tambahan: kode yang gampang ditest juga harus gampang dibaca dan konsisten gayanya, supaya reviewer (manusia atau AI lain) tidak terdistraksi oleh gaya penulisan yang berbeda-beda antar file.

## Tooling

**Formatter: `forge fmt`** — bawaan Foundry, tidak perlu install terpisah. Ini yang dipakai, BUKAN Prettier plugin Solidity, supaya tidak ada dua sumber kebenaran soal format dan tidak perlu dependency Node.js tambahan cuma untuk format kode Solidity di project yang toolchain utamanya sudah Foundry.

**Linter: `solhint`** — linter Solidity paling umum dipakai ekosistem, cek kualitas kode dan potensi masalah keamanan (bukan cuma gaya penulisan). Install sebagai dev dependency lewat npm/bun di root `sahih-contracts/` (butuh `package.json` minimal meski project intinya Foundry, karena solhint didistribusikan lewat npm registry).

Jangan pakai Slither sebagai pengganti solhint di tahap ini — Slither itu static analyzer yang lebih berat (butuh Python, analisis lebih dalam), cocok untuk audit sebelum mainnet, bukan linting harian selama development. Slither bisa jadi langkah terpisah nanti, disebut di bagian "Yang Sengaja Belum Dicakup" di bawah.

## Konfigurasi `forge fmt`

Taruh di `foundry.toml`, bagian `[fmt]`:

```toml
[fmt]
line_length = 120
tab_width = 4
bracket_spacing = true
int_types = "long"
multiline_func_header = "params_first"
quote_style = "double"
number_underscore = "thousands"
```

Alasan tiap pilihan:
- `line_length = 120` — lebih lega dari default 80 karena nama fungsi dan parameter di kontrak ini cenderung panjang (`profitSharingRatio`, `calculationRefHash`, dst), 80 karakter akan memaksa wrap berlebihan
- `int_types = "long"` — tulis `uint256` bukan `uint`, eksplisit lebih baik untuk kontrak yang expected diaudit
- `number_underscore = "thousands"` — angka besar (kalau ada hardcoded constant) ditulis `1_000_000` bukan `1000000`, lebih gampang dibaca sekilas

## Konfigurasi `solhint`

File `.solhint.json` di root `sahih-contracts/`:

```json
{
  "extends": "solhint:recommended",
  "rules": {
    "compiler-version": ["error", "^0.8.20"],
    "func-visibility": ["error", { "ignoreConstructors": true }],
    "not-rely-on-time": "off",
    "reason-string": ["error", { "maxLength": 64 }],
    "custom-errors": "error",
    "gas-custom-errors": "error",
    "no-empty-blocks": "error",
    "ordering": "error",
    "max-states-count": ["warn", 15],
    "state-visibility": "error",
    "explicit-types": ["error", "explicit"]
  }
}
```

Alasan tiap rule non-default yang relevan ke keputusan desain proyek ini:
- `custom-errors` dan `gas-custom-errors` di-set `error` (bukan cuma warning) — ini MENEGAKKAN aturan "revert pakai custom error, bukan string message polos" yang sudah ditetapkan di bagian Testability by Design pada `sahih-development-plan.md`. Kalau ada yang menulis `revert("transfer_restricted")`, linter harus gagal, bukan cuma warning yang bisa diabaikan
- `not-rely-on-time` di-set `off` — solhint default punya rule ini karena `block.timestamp` bisa dimanipulasi miner beberapa detik. Untuk kontrak ini, `timestamp` yang dipakai di payload attestation sifatnya untuk pencatatan periode (mingguan), bukan untuk logic kritis yang butuh presisi detik, jadi false positive rule ini di-nonaktifkan
- `ordering` di-set `error` — memaksa urutan standar (state variables → events → errors → modifiers → constructor/initializer → external → public → internal → private functions), supaya reviewer tahu persis di mana mencari sesuatu tanpa harus scroll seluruh file
- `explicit-types` di-set `explicit` — konsisten dengan `int_types = "long"` di formatter, mencegah campuran `uint` dan `uint256` dalam kontrak yang sama
- `max-states-count` sebagai `warn` bukan `error` — ini sinyal awal kalau satu kontrak mulai terlalu gemuk state variable-nya, tapi tidak memblokir kerja karena kadang penambahan sah (misal storage gap yang memang besar)

`.solhintignore` untuk exclude folder yang tidak perlu di-lint:
```
node_modules/
lib/
out/
cache/
```

`lib/` di-exclude karena isinya dependency eksternal (OpenZeppelin, forge-std, dst) yang sudah punya standar sendiri — tidak perlu (dan tidak boleh) diubah untuk memenuhi linter proyek ini.

## Kapan Dijalankan

**Sebelum commit (lokal, wajib):**
```bash
forge fmt
solhint 'src/**/*.sol'
```

Kalau memungkinkan, pasang sebagai pre-commit hook (misal via `lefthook` atau `husky` kalau sudah ada tooling Node di project, atau shell script sederhana di `.git/hooks/pre-commit`) supaya kontributor tidak perlu ingat menjalankan manual. Tidak wajib untuk MVP scope, tapi disebutkan sebagai langkah lanjutan yang murah untuk diterapkan.

**Di CI (kalau/ketika CI dipasang):**
```bash
forge fmt --check   # gagal kalau ada file yang belum diformat, TIDAK auto-fix di CI
solhint 'src/**/*.sol' --max-warnings 0
```

`--check` dipakai di CI (bukan `forge fmt` polos) karena CI tidak boleh diam-diam mengubah kode — tugasnya cuma memberi tahu kalau ada yang belum sesuai format, developer yang menjalankan `forge fmt` sendiri secara lokal lalu commit ulang.

`--max-warnings 0` di CI supaya warning solhint (seperti `max-states-count` di atas) tidak menumpuk dan diabaikan selamanya — begitu ada warning baru, CI merah dan harus di-review apakah warning itu valid atau memang perlu di-suppress secara eksplisit dengan alasan (lihat bagian Suppress Aturan di bawah).

## Aturan Tambahan yang Tidak Tercakup Tool (Manual Review)

Beberapa hal dari `sahih-development-plan.md` tidak bisa dicek otomatis oleh formatter/linter generik, jadi tetap perlu perhatian manual saat review kode atau PR:

- **Storage layout rules** (variable baru selalu di akhir, tidak pernah disisipkan di tengah, storage gap disisakan) — solhint tidak tahu konteks upgrade ini. Validasi sebenarnya tetap harus lewat `@openzeppelin/foundry-upgrades` validator seperti sudah disebut di development plan, linter di sini hanya menjaga gaya penulisan, bukan menggantikan validator upgrade
- **Constructor kosong dan `_disableInitializers()`** di implementation contract — solhint bisa menangkap `no-empty-blocks` kalau ada blok kosong yang tidak disengaja, tapi tidak tahu bahwa constructor SEHARUSNYA kosong khusus untuk pattern upgradeable ini. Kalau muncul warning `no-empty-blocks` di file yang memang implementasi upgradeable, itu false positive yang perlu di-suppress dengan komentar, bukan dihapus konstruktornya

## Suppress Aturan (Kalau Diperlukan)

Kalau ada baris yang secara sah melanggar satu rule tapi memang disengaja (misal false positive `no-empty-blocks` di atas), suppress SATU baris spesifik dengan komentar di atasnya, JANGAN suppress seluruh file:

```solidity
// solhint-disable-next-line no-empty-blocks
constructor() {
    _disableInitializers();
}
```

Jangan pernah pakai `/* solhint-disable */` tanpa nama rule spesifik di awal file — itu mematikan SEMUA rule untuk seluruh file, menghilangkan gunanya linter sama sekali untuk file tersebut.

## Yang Sengaja Belum Dicakup

- Static analyzer lebih dalam (Slither, Mythril) untuk audit keamanan pra-mainnet — di luar scope linting harian, jadi langkah terpisah menjelang deploy production
- Linting untuk TypeScript backend (agent, operator, indexer) — akan dibahas terpisah bersamaan dengan development plan BE
- Pre-commit hook otomatis — disebutkan sebagai opsi, tapi belum diputuskan tool mana (`lefthook` vs `husky` vs shell script manual) dan belum wajib untuk MVP scope
