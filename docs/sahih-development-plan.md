# Sahih — Smart Contract Development Plan

Scope dokumen ini KHUSUS smart contract (kontrak, deployment, upgrade, test — unit maupun integration, security). Backend (agent, operator service, indexer, API, cron) sengaja TIDAK dibahas di sini — akan didiskusikan dan didokumentasikan terpisah.

Baca berurutan: (1) `sahih-entity-contract-design.md` untuk tahu kontrak apa saja dan payload/response tiap public function, lalu (2) dokumen ini untuk tahu kapan tiap fungsi dipanggil dalam alur sistem, spesifikasi teknis tiap kontrak, dan bagaimana membangun/menguji/mengamankannya.

## Ringkasan Proyek

**Sahih** adalah platform investasi mikro berbasis blockchain untuk patungan modal ke UMKM/badan usaha kecil-menengah dengan skema bagi hasil syariah, mulai Rp100rb. Token yang diterbitkan adalah representasi sukuk, BUKAN aset kripto bebas diperdagangkan — non-transferable, tidak untuk pasar sekunder.

## Constraint yang Harus Dipatuhi (Smart Contract)

- Token: ERC-20 (bukan ERC-1155), transfer dibatasi/non-transferable, satu kontrak per issuer lewat factory pattern
- Kontrak Token & Distribution HARUS upgradable (UUPS proxy), lihat alasan di bagian Upgradability
- SEMUA kalkulasi bisnis (omzet, ratio, proporsi bagi hasil, skor risiko) TIDAK boleh ada di smart contract — kontrak hanya eksekutor final dari payload yang dikirim dari luar
- Hanya address dengan `OPERATOR_ROLE` yang boleh memanggil fungsi sensitif (createIssuerToken, recordDistribution, attest*)
- Stack: Base (L2), Solidity + Foundry, EAS
- JANGAN generate implementasi dari nol untuk hal yang sudah dicover library (access control, upgradable proxy, ERC-20 base, EAS interaction) — pakai OpenZeppelin & EAS SDK resmi

---

## Bagian 1 — Kapan Tiap Fungsi Kontrak Dipanggil (Simulasi Alur)

Simulasi ini untuk memastikan urutan pemanggilan fungsi kontrak benar saat integrasi nanti dilakukan (oleh layer BE yang terpisah). Fungsi kontrak yang dirujuk di sini merujuk ke `sahih-entity-contract-design.md`.

### Konsep dasar attestation

EAS itu registry on-chain berisi record read-only. Sekali attest, tidak bisa diedit, hanya bisa direvoke (kalau schema-nya izinkan) atau dibuat attestation baru untuk periode berikutnya. "Riwayat" bukan disimpan sebagai satu record yang di-update terus, tapi sebagai deretan attestation baru tiap periode, semuanya searchable lewat issuerId.

### T0 — Issuer belum ada apa-apa

State awal: kosong. Tidak ada kontrak, tidak ada attestation.

### T1 — UMKM daftar dan connect QRIS (di luar kontrak)

Tidak ada pemanggilan kontrak di tahap ini. Kontrak token belum dideploy karena issuer belum lolos verifikasi pertama.

### T2 — Verifikasi pertama → `attestVerification`

Setelah proses verifikasi omzet selesai (di luar kontrak), fungsi `attestVerification` dipanggil:
```json
{
  "issuerId": "UMKM-001",
  "period": "2026-W31",
  "avgRevenue": 8500000,
  "volatilityIndex": 0.12,
  "dataRefHash": "0xabc123...",
  "timestamp": "2026-08-03T09:00:00Z"
}
```
EAS registry menerbitkan attestation baru dengan UID unik, misal `0xVERIF001`. `dataRefHash` adalah jangkar — kontrak tidak menyimpan data mentahnya, hanya hash referensinya.

### T3 — Skoring → `attestScore`

Setelah skor risiko dihitung (di luar kontrak, berdasarkan hasil T2), fungsi `attestScore` dipanggil:
```json
{
  "issuerId": "UMKM-001",
  "score": 78,
  "scoringMethodVersion": "v1.0",
  "period": "2026-W31",
  "timestamp": "2026-08-03T09:05:00Z"
}
```
Attestation baru terbit, UID `0xSCORE001`. Independen dari attestation T2, tapi berhubungan lewat issuerId + period yang sama.

### T4 — Issuer lolos verifikasi → `createIssuerToken`

Setelah T2-T3 selesai dan issuer dinyatakan investable, fungsi `createIssuerToken` di Factory Contract dipanggil, kontrak token baru (di belakang UUPS proxy) dideploy untuk issuer ini.

Issuer sekarang punya 2 jejak on-chain terpisah: EAS attestation (bukti proses) dan Token Contract (instrumen investasi). Urutan ini penting — attestation harus ada SEBELUM token contract dideploy, karena verifikasi harus lolos dulu baru issuer boleh menerbitkan sukuk.

### T5 — Investor beli token → `purchaseTokens`

Investor memanggil `purchaseTokens` langsung ke Token Contract issuer yang dipilih. Balance investor bertambah, event `Purchase` tercatat — event ini yang nantinya diindeks pihak lain (BE) untuk keperluan distribusi, tapi indexing itu sendiri di luar scope kontrak.

### T6 — Siklus mingguan berikutnya → `attestVerification` + `attestScore` lagi

Ini yang membentuk pola "riwayat". `attestVerification` dan `attestScore` dipanggil LAGI untuk periode baru (2026-W32), menghasilkan attestation BARU — bukan update ke attestation W31.

**Perubahan state kumulatif untuk issuer UMKM-001:**

| Periode | Verification UID | Score UID | Skor |
|---|---|---|---|
| W31 | 0xVERIF001 | 0xSCORE001 | 78 |
| W32 | 0xVERIF002 | 0xSCORE002 | 82 |

Attestation lama tetap ada selamanya sebagai bukti historis. Ini yang bikin sistem auditable — siapapun bisa tarik seluruh riwayat attestation issuer tertentu lewat `getAttestation` dan lihat progresi skornya minggu demi minggu tanpa bisa dimanipulasi surut.

### T7 — Distribusi bagi hasil W32 → `recordDistribution` + `attestDistribution`

Setelah breakdown per holder selesai dihitung (di luar kontrak, berdasarkan omzet T6 dan balance holder dari indexing event `Purchase` T5):

**Panggil `recordDistribution`:**
```json
{
  "issuerContractAddress": "0x...",
  "period": "2026-W32",
  "totalAmount": 425000,
  "distributions": [
    { "holderAddress": "0xInvestorA", "amount": 127500 },
    { "holderAddress": "0xInvestorB", "amount": 297500 }
  ],
  "calculationRefHash": "0xdef456..."
}
```
Kontrak loop melalui `distributions`, transfer amount ke tiap holderAddress, emit event `Distributed(issuer, period, totalAmount, timestamp)`.

**Lalu panggil `attestDistribution`:**
```json
{
  "issuerId": "UMKM-001",
  "period": "2026-W32",
  "totalAmount": 425000,
  "calculationRefHash": "0xdef456...",
  "timestamp": "2026-08-10T10:00:00Z"
}
```
Attestation baru, UID `0xDIST001`. Total attestation issuer ini sekarang 5 (2 verification, 2 score, 1 distribution).

**Kondisi khusus yang perlu ditangani di level kontrak/caller:**
- Omzet nol/sangat rendah — `recordDistribution` tetap boleh dipanggil dengan totalAmount kecil/nol, supaya ada jejak on-chain bahwa minggu itu memang omzetnya rendah
- `recordDistribution` HARUS gagal/revert kalau total dari array `distributions` tidak sama dengan `totalAmount` yang dikirim, sebagai sanity check di level kontrak

### Ringkasan pola

Setiap siklus mingguan memanggil `attestVerification` dan `attestScore` sebagai entry BARU (bukan update). Setelah 12 minggu, satu issuer akan punya sekitar 36 attestation (3 jenis x 12 minggu), semuanya bisa di-query lewat `getAttestation` untuk membentuk timeline lengkap.

### Kenapa avgRevenue hanya di attestVerification

`avgRevenue` adalah output dari proses verifikasi, bukan output dari distribusi. `attestDistribution` tidak mengulang `avgRevenue`, hanya berisi `totalAmount` hasil kalkulasi (yang sudah melibatkan avgRevenue di dalamnya secara off-chain) plus `calculationRefHash`. Pemisahan ini membuat dua klaim bisa diverifikasi independen: "apakah omzet yang diklaim memang X" (dari attestVerification) vs "apakah dana yang didistribusikan sesuai omzet yang diklaim" (bandingkan totalAmount di attestDistribution terhadap avgRevenue × ratio dari attestVerification periode yang sama).

---

## Bagian 2 — Smart Contract Architecture

### Prinsip Utama

Pakai library yang sudah battle-tested, JANGAN generate ulang dari nol. Setiap kali ada kebutuhan (access control, upgradable proxy, ERC-20 base, attestation client), cek dulu apakah OpenZeppelin/EAS SDK sudah menyediakannya sebelum menulis implementasi custom.

### Upgradability

Pakai pattern **UUPS Proxy** dari OpenZeppelin (`@openzeppelin/contracts-upgradeable`), bukan Transparent Proxy — UUPS lebih ringan gas-nya untuk deployment berulang lewat factory (logic upgrade ada di implementation contract, bukan di proxy, jadi tiap proxy instance lebih murah dideploy).

Kenapa upgradable penting: skema bagi hasil, metodologi skoring, dan struktur payload attestation kemungkinan besar berubah selama iterasi. Kontrak yang tidak upgradable berarti setiap perubahan kecil butuh migrasi penuh + redeploy semua kontrak issuer yang sudah ada.

Library wajib dipakai (jangan reimplementasi):
- `@openzeppelin/contracts-upgradeable` — untuk `AccessControlUpgradeable`, `ERC20Upgradeable`, `UUPSUpgradeable`, `Initializable`
- `@openzeppelin/foundry-upgrades` — untuk deployment & upgrade script di Foundry, termasuk validasi storage layout supaya upgrade tidak merusak state

Factory Contract yang deploy Token Contract per issuer HARUS deploy lewat proxy pattern (minimal proxy/clone ATAU UUPS proxy), bukan deploy kontrak penuh tiap kali — supaya gas deployment per issuer tetap murah dan semua instance bisa di-upgrade serentak lewat implementation contract yang sama.

**Aturan storage layout untuk kontrak upgradable** (wajib dipatuhi setiap kali ada perubahan):
- Semua state variable BARU ditambahkan di AKHIR kontrak, tidak pernah disisipkan di tengah urutan variable yang sudah ada
- Tidak pernah mengubah tipe data variable yang sudah ada, dan tidak pernah menghapus variable yang sudah pernah dideploy (kalau sudah tidak dipakai, biarkan sebagai `deprecated` placeholder)
- Sisakan storage gap (`uint256[50] private __gap;`) di setiap kontrak upgradable dasar (khususnya di kontrak yang akan diwarisi/extended), supaya versi mendatang punya ruang menambah variable tanpa menggeser layout kontrak turunan
- Setiap kali sebelum deploy upgrade, jalankan validator `@openzeppelin/foundry-upgrades` (`Upgrades.validateUpgrade` atau setara) sebagai bagian dari CI/pre-deploy check, bukan cuma dites manual sekali

**Fungsi `initialize()` menggantikan constructor** untuk kontrak upgradable — WAJIB pakai modifier `initializer` dari `Initializable`, dan constructor asli dikosongkan/di-disable (`_disableInitializers()`) supaya implementation contract itu sendiri tidak bisa diinisialisasi langsung (mencegah exploit lewat implementation contract yang belum terlindungi proxy).

### EAS Integration

Pakai EAS SDK resmi (`@ethereum-attestation-service/eas-sdk`) untuk semua operasi attest dan read, JANGAN interact langsung ke EAS contract address secara manual. SDK ini sudah handle schema encoding/decoding yang kalau ditulis manual rawan salah format.

Schema attestation (3 jenis: verification, score, distribution) didaftarkan sekali di awal lewat EAS Schema Registry. schemaUID hasil registrasi ini nantinya jadi salah satu output yang perlu diserahkan ke layer BE (di luar scope dokumen ini).

Definisi schema (representasi field, tipe data Solidity yang dipakai saat registrasi):
- **VerificationSchema**: `string issuerId, string period, uint256 avgRevenue, uint256 volatilityIndex, bytes32 dataRefHash, uint256 timestamp`
- **ScoreSchema**: `string issuerId, uint256 score, string scoringMethodVersion, string period, uint256 timestamp`
- **DistributionSchema**: `string issuerId, string period, uint256 totalAmount, bytes32 calculationRefHash, uint256 timestamp`

Semua attestation dibuat dengan `revocable: false` — sejalan dengan prinsip riwayat immutable yang sudah diputuskan (attestation lama tidak boleh hilang/berubah, hanya ditambah entry baru).

### Folder & File Structure (Contracts Only)

```
sahih-contracts/                        # Foundry project
├── src/
│   ├── Factory.sol
│   ├── IssuerToken.sol                 # implementation, di belakang UUPS proxy
│   ├── Distribution.sol
│   ├── interfaces/
│   │   ├── IIssuerToken.sol
│   │   └── IDistribution.sol
│   └── libraries/                      # HANYA kalau ada logic murni yang tidak dicover OZ
├── script/
│   ├── Deploy.s.sol
│   ├── Upgrade.s.sol
│   └── RegisterSchema.s.sol            # registrasi 3 EAS schema, dijalankan sekali
├── test/
│   ├── unit/                            # satu kontrak diisolasi, dependency di-mock
│   │   ├── Factory.t.sol
│   │   ├── IssuerToken.t.sol
│   │   └── Distribution.t.sol
│   ├── integration/                     # beberapa kontrak berinteraksi via alur nyata
│   │   ├── FullIssuerLifecycle.t.sol    # T1-T7 penuh: create → verify → purchase → distribute
│   │   ├── FactoryToToken.t.sol         # Factory deploy proxy, Token langsung dipakai
│   │   └── UpgradeFlow.t.sol            # deploy → upgrade → state tetap valid
│   ├── invariant/                       # test invariant, lihat bagian Security Checklist
│   │   └── DistributionInvariant.t.sol
│   ├── mocks/                           # mock contract untuk isolasi unit test
│   │   ├── MockEAS.sol                  # simulasi EAS registry tanpa deploy EAS asli
│   │   └── MockToken.sol                # ERC-20 sederhana untuk test Distribution terisolasi
│   └── helpers/                         # fixture & utility dipakai lintas test file
│       ├── DeployHelpers.sol            # deploy Factory+Token+Distribution siap pakai
│       └── TestConstants.sol            # nilai dummy yang konsisten antar test (issuerId, ratio, dst)
├── foundry.toml
└── remappings.txt
```

### Spesifikasi Detail Per Kontrak

#### Factory Contract

**State variables:**
- `mapping(string => address) issuerContracts` — issuerId → alamat proxy Token Contract
- `address[] allIssuerContracts` — untuk enumerasi via `listAllIssuers`
- `address tokenImplementation` — alamat implementation contract yang dipakai semua proxy baru

**Events:**
- `IssuerTokenCreated(string indexed issuerId, address indexed contractAddress, uint256 timestamp)`

**Revert conditions:**
- `createIssuerToken` revert kalau `issuerId` sudah terdaftar sebelumnya (cegah duplikasi issuer)
- `createIssuerToken` revert kalau caller bukan `OPERATOR_ROLE`
- `createIssuerToken` revert kalau `profitSharingRatio` di luar rentang wajar (misal 0 atau >100%), sebagai sanity check dasar

#### IssuerToken Contract (per issuer)

**State variables:**
- Inherited dari `ERC20Upgradeable`: `_balances`, `_totalSupply`, dst (jangan disentuh langsung)
- `uint256 profitSharingRatio`
- `uint256 pricePerUnit`
- `string distributionPeriod`
- `bool transferRestricted`
- `mapping(address => bool) transferWhitelist`
- `uint256[50] __gap` — storage gap untuk upgrade masa depan

**Events:**
- `Purchase(address indexed investor, uint256 amount, uint256 timestamp)`
- Event standar ERC-20 `Transfer` tetap emit (untuk kompatibilitas tooling), meskipun transfer di luar whitelist di-revert sebelum event ini emit

**Revert conditions:**
- `purchaseTokens` revert kalau `amount` melebihi sisa `totalSupply` yang belum terjual
- `purchaseTokens` revert kalau `amount` bernilai nol
- `transfer`/`transferFrom` revert dengan pesan jelas (`"transfer_restricted"`) kalau `toAddress` tidak ada di `transferWhitelist` dan `transferRestricted == true`

#### Distribution Contract

**State variables:**
- `mapping(address => mapping(string => DistributionRecord)) distributionHistory` — issuerContract → period → record
- `mapping(address => Distribution[]) investorDistributions` — investor address → daftar distribusi yang pernah diterima (untuk `getInvestorDistributions`)

**Events:**
- `Distributed(address indexed issuerContract, string period, uint256 totalAmount, uint256 timestamp)` — breakdown per holder TIDAK di event ini (hemat gas), hanya total

**Revert conditions:**
- `recordDistribution` revert kalau jumlah seluruh `amount` di array `distributions` TIDAK SAMA DENGAN `totalAmount` yang dikirim (sanity check kritis, cegah kesalahan kalkulasi off-chain menyebabkan dana salah kirim)
- `recordDistribution` revert kalau `period` untuk `issuerContractAddress` yang sama sudah pernah direcord sebelumnya (cegah distribusi ganda untuk periode yang sama)
- `recordDistribution` revert kalau saldo kontrak (native token atau ERC-20 pembayaran, tergantung desain akhir) tidak cukup untuk menutupi `totalAmount`
- `recordDistribution` revert kalau caller bukan `OPERATOR_ROLE`

### Gas Considerations

- `recordDistribution` yang loop transfer ke banyak holder berisiko kena block gas limit kalau holder-nya banyak (ratusan+). Pertimbangkan batasan jumlah holder per pemanggilan (misal maksimal 100 holder per tx), dengan BE yang melakukan batching kalau holder melebihi itu — detail batching di BE di luar scope dokumen ini, tapi kontrak perlu punya parameter/pola yang mendukung pemanggilan bertahap per periode yang sama
- Enumerasi holder TIDAK dilakukan on-chain (mahal gas) — sudah diputuskan sebelumnya, holder list diindeks dari event `Purchase` oleh BE
- Base sebagai L2 membuat cost per-transaksi jauh lebih murah dibanding L1, tapi loop besar tetap sebaiknya dibatasi sebagai praktik defensif, bukan mengandalkan biaya gas yang rendah saja

### Access Control (recap dari entity design)

- `OPERATOR_ROLE` — bisa panggil createIssuerToken, recordDistribution, attestVerification, attestScore, attestDistribution
- `ADMIN_ROLE` — bisa update/revoke OPERATOR_ROLE, untuk key rotation tanpa redeploy kontrak

### Security Checklist

Selain 4 poin testing priority (di bawah), berikut pertimbangan keamanan tambahan yang perlu di-review sebelum deploy ke mainnet:

- **Reentrancy** — `recordDistribution` melakukan multiple transfer dalam satu transaksi; gunakan pattern checks-effects-interactions (update state dulu sebelum transfer) atau `ReentrancyGuardUpgradeable` dari OpenZeppelin sebagai lapisan tambahan
- **Integer overflow/underflow** — Solidity 0.8+ sudah punya proteksi built-in, tapi tetap perlu test eksplisit untuk kalkulasi proporsi (balance/totalSupply × pool) supaya tidak ada pembulatan yang menyebabkan dana tersisa/kurang di kontrak
- **Front-running pada `purchaseTokens`** — kalau `pricePerUnit` bisa berubah, pastikan investor tidak bisa dirugikan oleh transaksi yang di-front-run; untuk MVP dengan harga tetap per issuer, risiko ini rendah tapi tetap dicatat
- **Access control pada `initialize()`** — pastikan fungsi initialize tidak bisa dipanggil ulang oleh pihak lain setelah deployment pertama (`initializer` modifier menghandle ini, tapi WAJIB ditest eksplisit)
- **Upgrade authority** — fungsi `_authorizeUpgrade` (bagian dari UUPSUpgradeable) HARUS dibatasi hanya untuk `ADMIN_ROLE`, supaya tidak sembarang OPERATOR bisa mengganti implementation contract
- **Signature/replay untuk attestation** — karena semua attest* dipanggil oleh Platform Operator (satu address terpusat), risiko utamanya bukan signature spoofing tapi kompromi private key; ini masuk concern layer BE (secrets management), tapi kontrak sebaiknya tidak assume Platform Operator address tidak akan pernah berganti — sudah tercover lewat `ADMIN_ROLE` yang bisa rotate `OPERATOR_ROLE`
- **Invariant test untuk Distribution** — tambahkan test invariant (bukan cuma unit test) yang mengecek: total dana yang keluar dari kontrak sepanjang waktu untuk satu issuer TIDAK PERNAH melebihi total yang pernah masuk dikali profitSharingRatio secara kumulatif — ini pengecekan tingkat sistem yang tidak tertangkap unit test biasa

### Testability by Design

Supaya kontrak gampang ditest (unit maupun integration), beberapa keputusan desain berikut WAJIB diikuti saat menulis kontrak, bukan ditambahkan belakangan:

- **Setiap kontrak punya interface eksplisit** (`IIssuerToken.sol`, `IDistribution.sol` — sudah ada di folder structure). Test dan kontrak lain berinteraksi lewat interface, bukan langsung ke implementation. Ini bikin unit test bisa mock dependency dengan gampang, tanpa perlu deploy kontrak asli yang berat.
- **Constructor/initializer menerima dependency dari luar, tidak hardcode address.** Contoh: alamat EAS registry, alamat implementation contract di Factory — semua dilewatkan sebagai parameter saat `initialize()`, bukan ditulis langsung di kode. Ini yang memungkinkan `MockEAS.sol` dipasang saat unit test, dan EAS asli (atau EAS di Base Sepolia) dipasang saat integration test/deploy sungguhan, tanpa mengubah kontrak sama sekali.
- **Fungsi internal yang berisi logic kompleks dipisah dari fungsi external/public yang jadi entry point**, supaya logic tersebut bisa ditest lewat harness kalau perlu (misal pakai kontrak test turunan yang expose fungsi internal tertentu sebagai public untuk keperluan test saja), tanpa harus selalu lewat seluruh alur external call.
- **Revert pakai custom error, bukan string message polos** (`error TransferRestricted(); revert TransferRestricted();` alih-alih `revert("transfer_restricted")`). Custom error lebih murah gas DAN lebih gampang di-assert di test (`vm.expectRevert(TransferRestricted.selector)` presisi, tidak bergantung ke string yang gampang typo saat direfactor).
- **Event di-emit untuk setiap perubahan state penting**, bukan cuma yang sudah didaftarkan di spesifikasi (`Purchase`, `Distributed`, `IssuerTokenCreated`). Event adalah cara termurah untuk test memverifikasi sesuatu terjadi tanpa harus baca seluruh storage — `vm.expectEmit` jauh lebih ringkas ketimbang assert storage manual satu-satu.

### Unit Test vs Integration Test — Pembagian Tanggung Jawab

**Unit test** (folder `test/unit/`) menguji SATU kontrak terisolasi, dependency-nya (EAS, kontrak lain) diganti mock:
- `Factory.t.sol` — test `createIssuerToken` dengan `tokenImplementation` yang di-mock/kontrak sederhana, TANPA perlu Distribution atau EAS asli
- `IssuerToken.t.sol` — test `purchaseTokens`, `transfer` restriction, `getIssuerTerms` sebagai kontrak berdiri sendiri
- `Distribution.t.sol` — test `recordDistribution` pakai `MockToken.sol` untuk simulasi saldo/transfer, TANPA perlu Factory atau IssuerToken asli

Unit test harus cepat jalan (idealnya seluruh suite di bawah beberapa detik) karena tidak ada deployment kontrak yang berat berulang kali — pakai `helpers/DeployHelpers.sol` untuk setup minimal yang konsisten di tiap test file.

**Integration test** (folder `test/integration/`) menguji BEBERAPA kontrak yang berinteraksi lewat alur nyata, dependency asli (bukan mock) dipakai sebisa mungkin:
- `FullIssuerLifecycle.t.sol` — reproduksi penuh simulasi T1-T7 di Bagian 1: Factory deploy Token asli → attestVerification & attestScore ke EAS asli (atau EAS yang dideploy di testnet lokal via Foundry fork) → investor `purchaseTokens` → `recordDistribution` → `attestDistribution`. Ini test yang paling dekat merepresentasikan pemakaian sungguhan
- `FactoryToToken.t.sol` — fokus sempit ke interaksi Factory-Token saja: pastikan proxy yang dideploy Factory benar-benar bisa dipanggil sesuai interface `IIssuerToken`, dan `OPERATOR_ROLE` yang di-grant di level Factory konsisten ke instance Token yang baru dideploy
- `UpgradeFlow.t.sol` — deploy versi awal, isi dengan data (investor beli token, ada distribusi), jalankan upgrade, lalu pastikan seluruh data lama masih terbaca benar dan fungsi baru (kalau ada) bisa dipanggil. Ini satu-satunya cara memverifikasi storage layout aman selain validator statis

Aturan pembagian: kalau assertion yang ditulis hanya butuh SATU kontrak untuk membuktikan benar/salah, itu unit test. Begitu assertion butuh membuktikan bahwa OUTPUT satu kontrak jadi INPUT valid untuk kontrak lain (misal: proxy address dari Factory benar-benar bisa menerima panggilan sesuai Token interface), itu integration test.

### Testing Priority

Urutan prioritas test kalau waktu terbatas:
1. **[unit]** Access control — pastikan non-OPERATOR_ROLE tidak bisa panggil fungsi sensitif, dan non-ADMIN_ROLE tidak bisa memanggil upgrade
2. **[unit]** `transfer` restriction — pastikan token benar-benar non-transferable ke address sembarang
3. **[unit]** `recordDistribution` — pastikan total yang ditransfer sama dengan totalAmount, tidak ada dana nyangkut/hilang, dan revert dengan benar kalau breakdown tidak match
4. **[integration]** Upgrade path (`UpgradeFlow.t.sol`) — pastikan storage layout tidak rusak setelah upgrade (pakai validator dari `@openzeppelin/foundry-upgrades`), dan `initialize()` tidak bisa dipanggil ulang
5. **[invariant]** Invariant test Distribution — jalankan setelah 4 poin di atas solid, sebagai pengecekan tambahan sebelum deploy testnet
6. **[integration]** `FullIssuerLifecycle.t.sol` — jalankan terakhir sebagai gerbang akhir sebelum deploy testnet, karena test ini satu-satunya yang membuktikan seluruh kontrak benar-benar bisa dipakai berurutan sesuai simulasi T1-T7 di Bagian 1, bukan cuma benar secara terisolasi

---

## Bagian 3 — Urutan Kerja (Contracts Only)

1. Setup Foundry project + install OpenZeppelin upgradeable contracts
2. Tulis `IssuerToken.sol` (implementation di belakang UUPS proxy) — ERC-20 extended dengan transfer restriction + AccessControl, termasuk `initialize()` dan storage gap
3. Tulis `Factory.sol` — deploy IssuerToken lewat proxy pattern per issuer
4. Tulis `Distribution.sol` — recordDistribution + view functions, AccessControl OPERATOR_ROLE, termasuk revert check total distribusi
5. Tulis `test/mocks/` (MockEAS, MockToken) dan `test/helpers/` (DeployHelpers, TestConstants) — disiapkan SEBELUM menulis test file, karena unit test di langkah berikutnya bergantung pada mock/helper ini
6. Tulis dan jalankan unit test (`test/unit/`) sesuai prioritas 1-3 di atas (access control → transfer restriction → distribution logic)
7. Tulis dan jalankan integration test (`test/integration/`) — mulai dari `FactoryToToken.t.sol`, lalu `UpgradeFlow.t.sol`, terakhir `FullIssuerLifecycle.t.sol` sebagai gerbang akhir sebelum deploy
8. Tulis invariant test (`test/invariant/`) untuk Distribution
9. Review security checklist di atas, terutama reentrancy guard dan `_authorizeUpgrade` restriction
10. Setup EAS schema registration (3 schema: verification, score, distribution) — jalankan sekali via `RegisterSchema.s.sol`, simpan schemaUID
11. Deploy ke Base Sepolia (testnet) untuk keperluan demo/integrasi awal dengan BE

## Yang Sengaja Belum Diputuskan (di luar scope kontrak)

- Semua hal backend (agent kalkulasi, operator signing service, indexer, cron orchestration, secrets management, API, frontend) — akan didiskusikan terpisah
- Threshold approval / multi-sig untuk distribusi nominal besar (pertimbangan production, bukan MVP)
- Mekanisme key rotation detail secara operasional (kontrak sudah mendukung lewat AccessControl role-based, tapi prosedurnya belum didefinisikan)
- Mekanisme pembayaran/token apa yang dipakai untuk `recordDistribution` (native ETH di Base, atau stablecoin ERC-20) — perlu diputuskan sebelum implementasi Distribution Contract dimulai, karena mempengaruhi apakah kontrak perlu approve/transferFrom pattern atau cukup payable function
- Batasan jumlah holder per pemanggilan `recordDistribution` untuk mengatasi gas limit (disebut di bagian Gas Considerations, tapi angka pasti dan mekanisme batching belum ditentukan)
